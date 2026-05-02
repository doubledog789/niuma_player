import AVKit
import AVFoundation
import Flutter
import UIKit

/// PiP（画中画）插件——iOS 端 niuma_player/pip 通道实现。
///
/// 通过 Obj-C runtime 反射访问 video_player_avfoundation 的内部
/// `playersByIdentifier` 字典，拿到 AVPlayer 实例后创建
/// AVPictureInPictureController。
///
/// **风险点：** 反射依赖 video_player 内部字段名，未来 video_player
/// 升级可能改名导致 lookupAVPlayer 返 nil。pubspec 锁
/// `video_player: ">=2.8.0 <3.0.0"` 范围。
@objc public class NiumaPipPlugin: NSObject, FlutterPlugin {

    /// 静态保存 registrar 引用，反射查找 video_player plugin 实例时用。
    private static weak var pluginRegistrar: FlutterPluginRegistrar?

    /// 当前 PiP controller（仅一个 PiP 实例）。
    private var pipController: AVPictureInPictureController?
    private var pipLayer: AVPlayerLayer?
    private var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        Self.pluginRegistrar = registrar

        let methodChannel = FlutterMethodChannel(
            name: "niuma_player/pip",
            binaryMessenger: registrar.messenger()
        )
        let instance = NiumaPipPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: "niuma_player/pip/events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enterPictureInPicture":
            handleEnter(call, result: result)
        case "exitPictureInPicture":
            handleExit(result: result)
        case "queryPictureInPictureSupport":
            if #available(iOS 15.0, *) {
                result(AVPictureInPictureController.isPictureInPictureSupported())
            } else {
                result(false)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleEnter(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 15.0, *) else {
            result(false)
            return
        }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            result(false)
            return
        }
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64 else {
            result(false)
            return
        }

        // 配置 audio session（PiP 需要 background audio category）
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .moviePlayback
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("[NiumaPipPlugin] audio session 配置失败: \(error)")
        }

        // 通过反射拿 AVPlayer
        guard let avPlayer = lookupAVPlayer(textureId: textureId) else {
            NSLog("[NiumaPipPlugin] 找不到 textureId=\(textureId) 对应的 AVPlayer")
            result(false)
            return
        }

        // 创建隐藏的 AVPlayerLayer（PiP 需要 layer 在 view hierarchy 中）
        let layer = AVPlayerLayer(player: avPlayer)
        layer.frame = .zero
        guard let window = keyWindow() else {
            result(false)
            return
        }
        window.layer.insertSublayer(layer, at: 0)
        self.pipLayer = layer

        let pip = AVPictureInPictureController(playerLayer: layer)
        pip?.delegate = self
        self.pipController = pip

        // 等下一帧再启动（layer 必须先在 hierarchy 里）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            pip?.startPictureInPicture()
        }
        result(true)
    }

    private func handleExit(result: @escaping FlutterResult) {
        guard let pip = pipController else {
            result(false)
            return
        }
        pip.stopPictureInPicture()
        result(true)
    }

    /// 通过 Obj-C runtime 反射读 video_player_avfoundation 的
    /// `playersByIdentifier[textureId].player` 拿 AVPlayer。
    ///
    /// **依赖** video_player_avfoundation 2.10+ 的内部字段名 `playersByIdentifier`。
    /// 如果反射失败（field 改名 / video_player 升级 / 实例没注册），返 nil。
    private func lookupAVPlayer(textureId: Int64) -> AVPlayer? {
        // Step 1: 找 video_player 的 plugin 实例
        // Flutter plugin 名通常是 "FVPVideoPlayerPlugin" 或 "FLTVideoPlayerPlugin"
        // 通过 messenger 取 registrar 后，访问其 publish 的 plugin 字典
        guard let registrar = Self.pluginRegistrar else { return nil }

        // valuePublishedByPlugin 在 iOS Flutter SDK 中暴露
        // registrar 是协议类型，需要先 cast 到 NSObject 才能用 KVC 反射
        let candidatePluginNames = [
            "FVPVideoPlayerPlugin",
            "FLTVideoPlayerPlugin",
        ]
        var videoPlayerPlugin: NSObject? = nil
        if let registrarObj = registrar as? NSObject {
            // 尝试通过 KVC 读 registrar 内部的 valuePublishedByPlugin 字典
            let publishedValue = registrarObj.value(forKey: "valuePublishedByPlugin")
            if let publishedDict = publishedValue as? NSDictionary {
                for name in candidatePluginNames {
                    if let plugin = publishedDict[name] as? NSObject {
                        videoPlayerPlugin = plugin
                        break
                    }
                }
            }
        }
        // valuePublishedByPlugin 可能不暴露——退路：stub 返 nil
        if videoPlayerPlugin == nil {
            // 注：实测可能需要遍历其他字段。先记日志，stub 返 nil。
            NSLog("[NiumaPipPlugin] 找不到 video_player plugin 实例（反射方案需要真机调试）")
            return nil
        }

        // Step 2: 反射读 playersByIdentifier 字典
        // 候选字段名（不同版本可能不同）
        let candidateFieldNames = [
            "playersByIdentifier",
            "playersByTextureId",
        ]
        var players: [NSNumber: NSObject]? = nil
        for fieldName in candidateFieldNames {
            if let dict = videoPlayerPlugin?.value(forKey: fieldName) as? [NSNumber: NSObject] {
                players = dict
                break
            }
        }
        guard let players = players else {
            NSLog("[NiumaPipPlugin] video_player 内部字典字段名未知（反射方案需要真机调试）")
            return nil
        }

        // Step 3: 拿到 FVPVideoPlayer 后反射读 player（AVPlayer）
        guard let videoPlayer = players[NSNumber(value: textureId)] else {
            return nil
        }
        let avPlayer = videoPlayer.value(forKey: "player") as? AVPlayer
        return avPlayer
    }

    /// iOS 13+ 多 scene 兼容的 keyWindow 取法。
    private func keyWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.keyWindow
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension NiumaPipPlugin: AVPictureInPictureControllerDelegate {
    public func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        eventSink?(["event": "pipStarted"])
    }

    public func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        eventSink?(["event": "pipStopped"])
        // 清理 layer + controller
        pipLayer?.removeFromSuperlayer()
        pipLayer = nil
        pipController = nil
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        NSLog("[NiumaPipPlugin] PiP 启动失败: \(error)")
        pipLayer?.removeFromSuperlayer()
        pipLayer = nil
        pipController = nil
    }
}

// MARK: - FlutterStreamHandler

extension NiumaPipPlugin: FlutterStreamHandler {
    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
