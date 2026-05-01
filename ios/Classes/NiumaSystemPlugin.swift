import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// 系统亮度 / 音量 channel：niuma_player/system。
///
/// 亮度通过 UIScreen.main.brightness 直接读写。
/// 音量通过隐藏的 MPVolumeView slider 读写（iOS 唯一不需要 entitlement
/// 的系统音量控制方式）。
@objc public class NiumaSystemPlugin: NSObject, FlutterPlugin {

    /// 隐藏的 MPVolumeView——0px 加 keyWindow，通过其 UISlider 操作系统音量。
    private var volumeView: MPVolumeView?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "niuma_player/system",
            binaryMessenger: registrar.messenger()
        )
        let instance = NiumaSystemPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getBrightness":
            result(Double(UIScreen.main.brightness))
        case "setBrightness":
            guard let args = call.arguments as? [String: Any],
                  let value = args["value"] as? Double else {
                result(false)
                return
            }
            UIScreen.main.brightness = CGFloat(max(0, min(1, value)))
            result(true)
        case "getSystemVolume":
            ensureVolumeView()
            let slider = volumeView?.subviews
                .compactMap { $0 as? UISlider }
                .first
            result(Double(slider?.value ?? 0))
        case "setSystemVolume":
            guard let args = call.arguments as? [String: Any],
                  let value = args["value"] as? Double else {
                result(false)
                return
            }
            ensureVolumeView()
            let slider = volumeView?.subviews
                .compactMap { $0 as? UISlider }
                .first
            slider?.value = Float(max(0, min(1, value)))
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// iOS 13+ 多 scene 兼容地拿 keyWindow，加隐藏 MPVolumeView。
    /// iOS 12 fallback：UIApplication.shared.keyWindow（deprecated in iOS 13 but valid on 12）。
    private func ensureVolumeView() {
        if volumeView != nil { return }
        let view = MPVolumeView(frame: .zero)
        view.isHidden = true
        let keyWindow: UIWindow?
        if #available(iOS 13.0, *) {
            keyWindow = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })
        } else {
            keyWindow = UIApplication.shared.keyWindow
        }
        keyWindow?.addSubview(view)
        volumeView = view
    }
}
