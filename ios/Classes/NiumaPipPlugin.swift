import AVKit
import AVFoundation
import Flutter
import ObjectiveC
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
    /// KVO 观察 isPictureInPicturePossible 的 token——AVKit 在 layer
    /// readyForDisplay + frame 有效后才把这个 flag 翻 true，固定 delay
    /// 调 startPictureInPicture 不靠谱。
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

    /// 彻底清理 PiP 内部状态——layer / controller / KVO observation /
    /// timeout work item 一次性清，让 [handleEnter] 总能在干净状态下重新
    /// 拉起。defer 在每个 handleEnter 入口和 didStop delegate 中调用。
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
        // 每次入口先彻底清旧状态——user 从 PiP 小窗返回 app 后再次点 PiP
        // 时若残留旧 pipController / pipLayer，AVKit 会把第二次启动 视为
        // "重复启动" 静默拒绝。
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

        // 配置 audio session：PiP 需要 background-capable category +
        // longFormVideo route policy（iOS 13+）让 AVKit 把 audio 视为
        // 视频伴音而不是普通媒体。
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

        // 创建 AVPlayerLayer——iOS 16+ PiP 要求 layer 在 view hierarchy
        // 中**真正可见、未被完全 cover**。之前放在 window.layer 底层被
        // Flutter view 完全遮挡，AVKit 视为 occluded → startPictureInPicture
        // 静默失败（delegate 一条都不回）。
        // 修法：放到 rootViewController.view.layer 顶层 + opacity=0.01，
        // user 几乎看不见但 AVKit 视为 visible。
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
        // 关键平衡点：
        //   - frame 必须有真实尺寸 + 不被 cover——AVKit 才视为 visible
        //   - 但 frame 全屏 + opacity 0.01 在 ProMotion 屏上 1% 仍然
        //     可见，叠在 Flutter video texture 上 → 用户"双画面"
        // 折中：屏幕左上角 4×4 像素一小点，opacity 1.0（完全显示）。
        // 用户视觉上是个 4×4 微小色块（在状态栏底下/导航栏区域），AVKit
        // 视为完全可见 visible layer，PiP 启动条件满足。
        // didStart 后会被 opacity=0.0 完全隐藏（PiP placeholder 行为）。
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

        // 启动 PiP——分两条路径：
        //   - possible 已 true（PiP layer ready，常发生在 user 第二次点
        //     PiP 时 AVKit 状态有缓存）：直接 start，不 observe，不 schedule
        //     timeout，避免 timeout 误杀已启动的 PiP。
        //   - possible 仍 false（首次启动 / cold layer）：KVO 等翻 true
        //     再 start，5s timeout 兜底防永等。
        //
        // 之前用 `.initial` 同步 fire callback——但 callback 早于 field
        // assignment，self.pipPossibleObservation 在 callback 内仍是 nil，
        // invalidate() 是 no-op，observation 永远没被取消，5s 后 timeout
        // 把已启动的 PiP 误杀。
        let startPip: (AVPictureInPictureController) -> Void = { p in
            DispatchQueue.main.async {
                Self.log("调 startPictureInPicture()，pip.isPictureInPictureActive(start前)=\(p.isPictureInPictureActive)")
                p.startPictureInPicture()
                if unsafeAutoBackground {
                    // ⚠️ 私有 API：调 home 键 selector 让 app 进入后台，PiP
                    // 小窗立刻飘出。host app 无法过 App Store 审核。Apple
                    // 后续 iOS 升级可能让此 selector 失效或抛异常——所以
                    // 包 try?，失败时不影响 PiP 本身。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        Self.log("⚠️ 触发 unsafe auto-background（私有 API suspend selector）")
                        let app = UIApplication.shared
                        let suspendSel = NSSelectorFromString("suspend")
                        if app.responds(to: suspendSel) {
                            app.perform(suspendSel)
                        } else {
                            Self.log("UIApplication 不响应 suspend selector，自动后台失败")
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

    /// KVC 安全读取——key 不存在时返 nil 而不是抛 `valueForUndefinedKey:`
    /// 让线程死锁。检测顺序参考 KVC 默认查找规则：
    ///   `<key>` selector → `is<Key>` → `_<key>` → ObjC property → ivar
    /// 全都不命中才返 nil；命中再调 `value(forKey:)`。
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

    /// 通过 Obj-C runtime 反射读 video_player_avfoundation 的
    /// `playersByIdentifier[textureId].player` 拿 AVPlayer。
    ///
    /// 反射链（4 步）：
    /// ```
    /// registrar — KVC: flutterEngine —→ FlutterEngine
    ///     — perform(valuePublishedByPlugin:) —→ FVPVideoPlayerPlugin
    ///     — KVC: playersByIdentifier[textureId] —→ FVPVideoPlayer
    ///     — KVC: player —→ AVPlayer
    /// ```
    ///
    /// **`valuePublishedByPlugin:` 在 `FlutterPluginRegistry` 协议（即
    /// `FlutterEngine`）上**——不在 `FlutterEngineRegistrar` 上。之前的
    /// 实现把它当 KVC key 直接在 registrar 上读，撞 valueForUndefinedKey:
    /// 抛异常死锁线程。修法：先从 registrar 拿 `_flutterEngine` 弱引用
    /// 再调 engine 的方法。
    ///
    /// 任意一步失败都返 nil（并 NSLog 标注哪步），不抛异常。
    private func lookupAVPlayer(textureId: Int64) -> AVPlayer? {
        guard let registrar = Self.pluginRegistrar else { return nil }
        guard let registrarObj = registrar as? NSObject else { return nil }

        // Step 1: registrar → FlutterEngine（私有 ivar `_flutterEngine`，
        // KVC 默认查找会 fallback 到 `flutterEngine` 或 `_flutterEngine`）
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

        // Step 2: engine.valuePublishedByPlugin("FVPVideoPlayerPlugin")
        // 这是 ObjC method（不是 KVC property），用 selector + perform。
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
        // PiP 启动后把 source layer 完全隐藏：之前 opacity=0.01 是为了让
        // AVKit 视为 visible（不被 cover），但 PiP 启动后 inline 这层
        // layer 会渲染 placeholder/frozen frame，叠在 Flutter 自己的 video
        // texture 上 → 用户视觉上看到"两个播放器"。
        pipLayer?.opacity = 0.0
        eventSink?(["event": "pipStarted"])
    }

    public func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Self.log("delegate: willStop")
        // 即将退出 PiP——AVKit 需要 source layer visible 做过渡动画。
        // 恢复 opacity 到 1.0（layer 本身就是 4×4 极小可见块，opacity
        // 1.0 也几乎看不到）。
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

    /// PiP 标准 delegate：user 从 PiP 小窗"返回 app"按钮触发——业务侧
    /// 应该在 completion(true) 之前把 UI 恢复到适合 PiP 退出的状态。
    /// 我们没特殊 UI 状态，直接 completion(true)；缺这个 method 会让
    /// iOS 在某些版本上把"返回 app"路径上的 cleanup 时序搞乱，导致
    /// 下次 startPictureInPicture 失败。
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
