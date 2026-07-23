import Flutter
import UIKit

/// iOS 插件入口：iOS 主路径走官方 video_player，这里只负责注册
/// PiP / System 子插件（无自有播放 channel）。
public class NiumaPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    NiumaPipPlugin.register(with: registrar)
    NiumaSystemPlugin.register(with: registrar)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }
}
