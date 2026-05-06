import Flutter
import UIKit

public class NiumaPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "niuma_player", binaryMessenger: registrar.messenger())
    let instance = NiumaPlayerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // M12: 注册 PiP 子插件
    NiumaPipPlugin.register(with: registrar)
    // M13: 注册 NiumaSystemPlugin
    NiumaSystemPlugin.register(with: registrar)
    // M15: 投屏 AirPlay 子插件（SDK 内置无需 host app 单独注册）
    NiumaAirPlayPlugin.register(with: registrar)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
