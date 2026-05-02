import 'dart:async';

import 'package:niuma_player/niuma_player.dart';

/// 测试用的 [NiumaPlayerController] 替身。
///
/// 不真正初始化 backend——本身就是 [NiumaPlayerController] 的子类，
/// 重写所有用户 API（[play] / [pause] / [seekTo] 等）成同步计数器。
/// 控件 widget test 只关心"点了按钮 → 调没调对方法 / 传了什么参数"，
/// 不关心 backend 是否真起来，所以这套就够。
class FakeNiumaPlayerController extends NiumaPlayerController {
  FakeNiumaPlayerController({
    NiumaMediaSource? source,
  }) : super(
          source ??
              NiumaMediaSource.single(
                NiumaDataSource.network('https://example.com/sample.mp4'),
              ),
        );

  int playCount = 0;
  int pauseCount = 0;
  Duration? lastSeek;
  double? lastSpeed;
  double? lastVolume;
  bool? lastLooping;
  String? lastSwitchLineId;

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
  }

  @override
  Future<void> seekTo(Duration position) async {
    lastSeek = position;
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    lastSpeed = speed;
  }

  @override
  Future<void> setVolume(double volume) async {
    lastVolume = volume;
  }

  @override
  Future<void> setLooping(bool looping) async {
    lastLooping = looping;
  }

  @override
  Future<void> switchLine(String lineId) async {
    lastSwitchLineId = lineId;
  }

  @override
  Future<void> initialize() async {
    // no-op for widget tests.
  }

  /// PiP 测试计数。
  int enterPictureInPictureCalled = 0;
  int exitPictureInPictureCalled = 0;

  @override
  Future<bool> enterPictureInPicture() async {
    enterPictureInPictureCalled++;
    return true;
  }

  @override
  Future<bool> exitPictureInPicture() async {
    exitPictureInPictureCalled++;
    return true;
  }

  /// 测试辅助：直接改 [value.position] 并触发 notifyListeners。
  void setPosition(Duration p) {
    value = value.copyWith(position: p);
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    // 父类 dispose 会动 _backend / event stream / thumbnail cache，
    // 我们没起 backend 也没在 widget test 里走完整生命周期，让父类
    // 跑一次干净就够。但跳过 super.dispose()——那条路会去关从未打开
    // 的 stream，在某些路径下会报错。
    super.dispose();
  }
}
