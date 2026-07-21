import AVKit
import AVFoundation
import Flutter
import ObjectiveC
import UIKit

/// PiP 插件（niuma_player/pip）：反射 video_player_avfoundation 内部字典拿
/// AVPlayer 后创建 AVPictureInPictureController。
/// 风险：反射依赖 video_player 内部字段名，升级可能失效（pubspec 锁 <3.0.0）。
@objc public class NiumaPipPlugin: NSObject, FlutterPlugin {

    /// 静态保存 registrar 引用，反射查找 video_player plugin 实例时用。
    private static weak var pluginRegistrar: FlutterPluginRegistrar?

    /// 当前 PiP controller（仅一个 PiP 实例）。
    private var pipController: AVPictureInPictureController?
    private var pipLayer: AVPlayerLayer?
    private var eventSink: FlutterEventSink?
    /// KVO 观察 isPictureInPicturePossible——AVKit ready 后才翻 true，
    /// 固定 delay 启动不靠谱。
    private var pipPossibleObservation: NSKeyValueObservation?
    private var pipReadyTimeout: DispatchWorkItem?

    /// 双发日志：NSLog 进系统 console，print 进 stdout 让 `flutter run`
    /// terminal 直接显示。前缀 `>>> NIUMA-PIP` 显眼，方便用户 grep。
    private static func log(_ msg: String) {
        let line = ">>> NIUMA-PIP: \(msg)"
        NSLog(line)
        print(line)
    }

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

    /// 彻底清理 PiP 内部状态，让 handleEnter 总能在干净状态下重新拉起。
    private func teardownPipState() {
        pipPossibleObservation?.invalidate()
        pipPossibleObservation = nil
        pipReadyTimeout?.cancel()
        pipReadyTimeout = nil
        pipLayer?.removeFromSuperlayer()
        pipLayer = nil
        pipController = nil
    }

    private func handleEnter(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        Self.log("handleEnter called")
        // 先清旧状态——残留 pipController / pipLayer 会让 AVKit 把二次启动
        // 当"重复启动"静默拒绝。
        teardownPipState()
        guard #available(iOS 15.0, *) else {
            Self.log("iOS < 15.0，PiP 不支持")
            result(false)
            return
        }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            Self.log("AVPictureInPictureController.isPictureInPictureSupported = false (设备不支持)")
            result(false)
            return
        }
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64 else {
            Self.log("arguments 中无 textureId 或类型错")
            result(false)
            return
        }
        let unsafeAutoBackground = (args["unsafeAutoBackground"] as? Bool) ?? false
        Self.log("textureId=\(textureId), unsafeAutoBackground=\(unsafeAutoBackground)")

        // PiP 需要 background-capable category + longFormVideo policy。
        do {
            let session = AVAudioSession.sharedInstance()
            if #available(iOS 13.0, *) {
                try session.setCategory(
                    .playback,
                    mode: .moviePlayback,
                    policy: .longFormVideo
                )
            } else {
                try session.setCategory(.playback, mode: .moviePlayback)
            }
            try session.setActive(true)
            Self.log("audio session OK (category=\(session.category.rawValue), mode=\(session.mode.rawValue))")
        } catch {
            Self.log("audio session 配置失败: \(error)")
        }

        // 通过反射拿 AVPlayer
        guard let avPlayer = lookupAVPlayer(textureId: textureId) else {
            Self.log("lookupAVPlayer 失败 textureId=\(textureId)")
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            result(false)
            return
        }
        Self.log("反射成功，拿到 AVPlayer=\(avPlayer)")

        // iOS 16+ PiP 要求 layer 真正可见、未被完全遮挡，否则 start 静默失败。
        guard let window = keyWindow() else {
            Self.log("拿不到 keyWindow")
            result(false)
            return
        }
        guard let rootView = window.rootViewController?.view else {
            Self.log("拿不到 rootViewController.view")
            result(false)
            return
        }
        // 折中：rootView 顶层 4×4 小块、opacity 1.0——AVKit 视为 visible 且
        // 用户几乎看不见；didStart 后再 opacity=0 完全隐藏。
        let layer = AVPlayerLayer(player: avPlayer)
        layer.frame = CGRect(x: 0, y: 0, width: 4, height: 4)
        layer.videoGravity = .resizeAspect
        rootView.layer.addSublayer(layer)
        self.pipLayer = layer
        Self.log("AVPlayerLayer 已 addSublayer 到 rootView 顶层，frame=\(layer.frame)（4×4 极小可见）")

        guard let pip = AVPictureInPictureController(playerLayer: layer) else {
            Self.log("AVPictureInPictureController 初始化返 nil")
            result(false)
            return
        }
        pip.delegate = self
        // iOS 14.5+ 关键 flag：允许 app 切后台时自动进入 PiP——即使 explicit
        // start 在某些 iOS 版本上静默失败，user 上滑切主屏时也能自动起。
        if #available(iOS 14.2, *) {
            pip.canStartPictureInPictureAutomaticallyFromInline = true
            Self.log("已设 canStartPictureInPictureAutomaticallyFromInline=true")
        }
        self.pipController = pip
        Self.log("AVPictureInPictureController 初始化 OK，初始 isPictureInPicturePossible=\(pip.isPictureInPicturePossible)")
        Self.log("avPlayer.status=\(avPlayer.status.rawValue), currentItem.status=\(avPlayer.currentItem?.status.rawValue ?? -99), rate=\(avPlayer.rate)")

        // 两条启动路径：possible 已 true 直接 start（不 observe / 不 timeout，
        // 防误杀）；否则 KVO 等翻 true 再 start，5s timeout 兜底。不能用
        // `.initial` 同步 fire——callback 早于字段赋值，observation 取消不掉。
        let startPip: (AVPictureInPictureController) -> Void = { p in
            DispatchQueue.main.async {
                Self.log("调 startPictureInPicture()，pip.isPictureInPictureActive(start前)=\(p.isPictureInPictureActive)")
                p.startPictureInPicture()
                if unsafeAutoBackground {
                    // ⚠️ 私有 API suspend selector：app 立即后台使 PiP 飘出，无法过审。
                    // NiumaObjCExceptionCatcher 抓 NSException（Swift do-catch 抓不到）。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        Self.log("⚠️ 触发 unsafe auto-background（私有 API suspend selector）")
                        let app = UIApplication.shared
                        let suspendSel = NSSelectorFromString("suspend")
                        guard app.responds(to: suspendSel) else {
                            Self.log("UIApplication 不响应 suspend selector，自动后台失败")
                            return
                        }
                        do {
                            try NiumaObjCExceptionCatcher.catchExceptions {
                                app.perform(suspendSel)
                            }
                        } catch let error as NSError {
                            Self.log("perform(suspend) 抛 NSException——可能 iOS 版本封了私有 API: \(error.userInfo)")
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    Self.log("0.5s 后 pip.isPictureInPictureActive=\(p.isPictureInPictureActive), suspended=\(p.isPictureInPictureSuspended)")
                }
            }
        }
        if pip.isPictureInPicturePossible {
            Self.log("isPictureInPicturePossible 已 true，跳过 KVO 直接启动")
            startPip(pip)
        } else {
            pipPossibleObservation = pip.observe(
                \.isPictureInPicturePossible,
                options: .new
            ) { [weak self] obj, _ in
                guard obj.isPictureInPicturePossible else { return }
                // 一次性：先取消 observation + timeout 再启动
                self?.pipPossibleObservation?.invalidate()
                self?.pipPossibleObservation = nil
                self?.pipReadyTimeout?.cancel()
                self?.pipReadyTimeout = nil
                Self.log("isPictureInPicturePossible 变 true → 启动")
                startPip(obj)
            }
            // 5s 兜底防 layer 永不 ready（视频未 init / 设备问题）
            let timeout = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.pipPossibleObservation != nil {
                    Self.log("等 isPictureInPicturePossible 超时（5s），放弃")
                    self.teardownPipState()
                }
            }
            pipReadyTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeout)
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

    /// KVC 安全读取：先用 ObjC runtime 确认 selector / property / ivar 存在再
    /// value(forKey:)，避免 valueForUndefinedKey: 抛 NSException 死锁线程。
    private static func safeKVCValue(_ obj: NSObject, key: String) -> Any? {
        let cls: AnyClass = type(of: obj)
        // method-based accessors
        let firstUpper = key.prefix(1).uppercased() + key.dropFirst()
        let selectors = [
            Selector(key),
            Selector("is\(firstUpper)"),
            Selector("_\(key)"),
        ]
        for sel in selectors {
            if class_getInstanceMethod(cls, sel) != nil {
                return obj.value(forKey: key)
            }
        }
        // ObjC @property
        if class_getProperty(cls, key) != nil {
            return obj.value(forKey: key)
        }
        // ivar `_<key>` 或 `<key>`
        if class_getInstanceVariable(cls, "_\(key)") != nil ||
           class_getInstanceVariable(cls, key) != nil {
            return obj.value(forKey: key)
        }
        return nil
    }

    /// 反射链：registrar → flutterEngine → valuePublishedByPlugin(FVPVideoPlayerPlugin)
    /// → playersByIdentifier[textureId] → .player；注意 valuePublishedByPlugin:
    /// 在 FlutterEngine 上而非 registrar。任一步失败返 nil，不抛异常。
    private func lookupAVPlayer(textureId: Int64) -> AVPlayer? {
        guard let registrar = Self.pluginRegistrar else { return nil }
        guard let registrarObj = registrar as? NSObject else { return nil }

        // Step 1: registrar → FlutterEngine（私有 ivar，试两个 key）
        var engine: NSObject? = nil
        for key in ["flutterEngine", "_flutterEngine"] {
            if let e = Self.safeKVCValue(registrarObj, key: key) as? NSObject {
                engine = e
                break
            }
        }
        guard let engine = engine else {
            Self.log("拿不到 registrar 内的 FlutterEngine 引用")
            return nil
        }

        // Step 2: engine.valuePublishedByPlugin(...)——ObjC method，用 perform。
        let valuePublishedSel = NSSelectorFromString("valuePublishedByPlugin:")
        guard engine.responds(to: valuePublishedSel) else {
            Self.log("FlutterEngine 不暴露 valuePublishedByPlugin:")
            return nil
        }
        let candidatePluginNames = [
            "FVPVideoPlayerPlugin",
            "FLTVideoPlayerPlugin",
        ]
        var videoPlayerPlugin: NSObject? = nil
        for name in candidatePluginNames {
            let unmanaged = engine.perform(valuePublishedSel, with: name)
            if let plugin = unmanaged?.takeUnretainedValue() as? NSObject {
                videoPlayerPlugin = plugin
                break
            }
        }
        guard let plugin = videoPlayerPlugin else {
            Self.log("FlutterEngine 内未找到 video_player plugin"
                + "（FVPVideoPlayerPlugin / FLTVideoPlayerPlugin）。"
                + "video_player 是否已 register？")
            return nil
        }

        // Step 3: 反射读 playersByIdentifier 字典
        let candidateFieldNames = [
            "playersByIdentifier",
            "playersByTextureId",
        ]
        var players: [NSNumber: NSObject]? = nil
        for fieldName in candidateFieldNames {
            if let dict = Self.safeKVCValue(plugin, key: fieldName)
                as? [NSNumber: NSObject] {
                players = dict
                break
            }
        }
        guard let players = players else {
            Self.log("video_player plugin 内部字典字段名未知"
                + "（试过 playersByIdentifier / playersByTextureId）")
            return nil
        }

        // Step 4: FVPVideoPlayer.player → AVPlayer
        guard let videoPlayer = players[NSNumber(value: textureId)] else {
            Self.log("textureId=\(textureId) 在 players 字典中不存在")
            return nil
        }
        guard let avPlayer = Self.safeKVCValue(videoPlayer, key: "player")
            as? AVPlayer else {
            Self.log("FVPVideoPlayer 不暴露 player KVC key")
            return nil
        }
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
    public func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Self.log("delegate: willStart")
    }

    public func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Self.log("delegate: didStart ✓ PiP 真启动了")
        // 启动后隐藏 source layer——否则 inline placeholder 叠在 Flutter
        // 纹理上出现"双画面"。
        pipLayer?.opacity = 0.0
        eventSink?(["event": "pipStarted"])
    }

    public func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Self.log("delegate: willStop")
        // AVKit 需要 source layer visible 做退出过渡动画。
        pipLayer?.opacity = 1.0
    }

    public func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Self.log("delegate: didStop")
        eventSink?(["event": "pipStopped"])
        // 完全清理——下次 handleEnter 会重新建。
        teardownPipState()
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Self.log("delegate: failedToStart \(error)")
        teardownPipState()
    }

    /// user 从 PiP 小窗"返回 app"时触发；缺这个 method 会打乱部分 iOS 版本
    /// 的 cleanup 时序，导致下次 start 失败。
    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
            completionHandler: @escaping (Bool) -> Void
    ) {
        Self.log("delegate: restoreUserInterface (user 点了 PiP 返回 app)")
        completionHandler(true)
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
