import '../presentation/niuma_player_controller.dart';
import 'cast_device.dart';
import 'cast_session.dart';

/// 投屏协议实现接口。子包 extends 它（DlnaCastService / AirPlayCastService）。
abstract class CastService {
  /// 协议唯一 id，全小写，如 `dlna` / `airplay`。
  String get protocolId;

  /// 发现设备。返回 stream，扫到一个吐一次累计列表（合并 dedup 由调用方做）。
  /// [timeout] 内 stream 关闭。8s 是 DLNA SSDP 推荐 MX。
  Stream<List<CastDevice>> discover({
    Duration timeout = const Duration(seconds: 8),
  });

  /// 连接到 [device]，返回 session。失败抛异常（业务侧捕获显示 toast）。
  /// [controller] 用于读取当前播放 url / position 喂给 TV 端。
  Future<CastSession> connect(
    CastDevice device,
    NiumaPlayerController controller,
  );
}
