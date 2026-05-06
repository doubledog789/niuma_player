import Flutter
import UIKit
import AVKit

public class NiumaAirPlayPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "niuma_player_airplay/main",
      binaryMessenger: registrar.messenger()
    )
    let instance = NiumaAirPlayPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "showRoutePicker":
      DispatchQueue.main.async {
        let view = AVRoutePickerView()
        view.frame = CGRect(x: 0, y: 0, width: 0, height: 0)
        // 通过遍历 subviews 找到 UIButton 并触发——iOS 13+ AVRoutePickerView 内部
        // 用 UIButton 实现"打开 picker"，模拟其 sendActions 即可弹起原生 picker
        if let btn = view.subviews.compactMap({ $0 as? UIButton }).first {
          btn.sendActions(for: .touchUpInside)
          result(true)
        } else {
          result(false)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
