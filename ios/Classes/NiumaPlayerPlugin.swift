import Flutter
import UIKit

public class NiumaPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "niuma_player", binaryMessenger: registrar.messenger())
    let instance = NiumaPlayerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // M13: 注册 NiumaSystemPlugin
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
