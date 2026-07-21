import Flutter
import UIKit

public class NiumaPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "niuma_player", binaryMessenger: registrar.messenger())
    let instance = NiumaPlayerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // 注册 PiP / System 子插件
    NiumaPipPlugin.register(with: registrar)
    NiumaSystemPlugin.register(with: registrar)
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
