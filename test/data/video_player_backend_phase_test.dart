import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/data/video_player_backend.dart';
import 'package:video_player/video_player.dart';

VideoPlayerValue _v({
  bool initialized = true,
  bool isPlaying = false,
  bool isBuffering = false,
  bool isCompleted = false,
  String? error,
  Duration position = const Duration(seconds: 1),
}) {
  return VideoPlayerValue(
    duration: const Duration(seconds: 10),
    isInitialized: initialized,
    isPlaying: isPlaying,
    isBuffering: isBuffering,
    isCompleted: isCompleted,
    errorDescription: error,
    position: position,
  );
}

PlayerPhase _phase(VideoPlayerValue v, {required bool userWantsPlay}) =>
    VideoPlayerBackend.derivePhaseFor(v, userWantsPlay: userWantsPlay);

void main() {
  group('VideoPlayerBackend.derivePhaseFor', () {
    test('error 优先于一切', () {
      expect(
        _phase(_v(error: 'boom', isPlaying: true), userWantsPlay: true),
        PlayerPhase.error,
      );
    });

    test('未初始化 → opening', () {
      expect(
        _phase(_v(initialized: false), userWantsPlay: true),
        PlayerPhase.opening,
      );
    });

    test('completed → ended，意图为播也不例外', () {
      expect(
        _phase(_v(isCompleted: true), userWantsPlay: true),
        PlayerPhase.ended,
      );
    });

    test('isPlaying 优先于 isBuffering——vp Android 会把 isBuffering 卡在 true', () {
      // 回归：video_player_android 播放中 isBuffering 常驻 true，若 buffering
      // 优先，phase 永远出不了 buffering → 皮肤 spinner 不灭、isPlaying 恒 false。
      expect(
        _phase(_v(isPlaying: true, isBuffering: true), userWantsPlay: true),
        PlayerPhase.playing,
      );
    });

    test('有播放意图但缺数据 → buffering', () {
      expect(
        _phase(_v(isBuffering: true), userWantsPlay: true),
        PlayerPhase.buffering,
      );
    });

    test('用户已暂停 → paused，即便底层仍报 isBuffering', () {
      // 本 bug 的直接用例：在缓冲窗口内按暂停。ExoPlayer 暂停不改
      // playbackState → 收不到 bufferingEnd，isBuffering 会一直挂着 true。
      expect(
        _phase(
          _v(isBuffering: true, position: const Duration(seconds: 5)),
          userWantsPlay: false,
        ),
        PlayerPhase.paused,
      );
    });

    test('未起播就暂停（position=0）→ ready，即便仍报 isBuffering', () {
      expect(
        _phase(
          _v(isBuffering: true, position: Duration.zero),
          userWantsPlay: false,
        ),
        PlayerPhase.ready,
      );
    });

    test('缓冲中暂停再恢复播放 → 不卡在 paused', () {
      final stalled =
          _v(isBuffering: true, position: const Duration(seconds: 5));
      expect(_phase(stalled, userWantsPlay: false), PlayerPhase.paused);
      expect(_phase(stalled, userWantsPlay: true), PlayerPhase.buffering);
      expect(
        _phase(_v(isPlaying: true, position: const Duration(seconds: 5)),
            userWantsPlay: true),
        PlayerPhase.playing,
      );
    });

    test('paused / ready 基础推导', () {
      expect(
        _phase(_v(position: Duration.zero), userWantsPlay: true),
        PlayerPhase.ready,
      );
      expect(_phase(_v(), userWantsPlay: true), PlayerPhase.paused);
      expect(_phase(_v(), userWantsPlay: false), PlayerPhase.paused);
    });

    test('播完即作废播放意图——vp 内部 pause() 绕过了本类的 pause()', () {
      // 播完 → 拖进度回中间：_updatePosition 会把 isCompleted 翻回 false，
      // 若意图还停在 true，就会推导成永远转圈的 buffering。
      expect(
        VideoPlayerBackend.nextUserWantsPlay(true, _v(isCompleted: true)),
        isFalse,
      );
      expect(
        VideoPlayerBackend.nextUserWantsPlay(true, _v()),
        isTrue,
        reason: '没播完不能动意图',
      );
      expect(
        VideoPlayerBackend.nextUserWantsPlay(false, _v()),
        isFalse,
      );
    });

    test('播完后拖回中间 → paused，不是 buffering', () {
      final ended = _v(isCompleted: true, position: const Duration(seconds: 10));
      final intent = VideoPlayerBackend.nextUserWantsPlay(true, ended);
      // seek 回中间：isCompleted 变回 false，底层正在重新缓冲。
      final afterSeek =
          _v(isBuffering: true, position: const Duration(seconds: 4));
      expect(
        _phase(afterSeek, userWantsPlay: intent),
        PlayerPhase.paused,
      );
    });

    test('不变量：无播放意图时永不产出 buffering', () {
      for (final playing in <bool>[true, false]) {
        for (final buffering in <bool>[true, false]) {
          for (final pos in <Duration>[
            Duration.zero,
            const Duration(seconds: 3),
          ]) {
            final phase = _phase(
              _v(isPlaying: playing, isBuffering: buffering, position: pos),
              userWantsPlay: false,
            );
            expect(phase, isNot(PlayerPhase.buffering),
                reason: 'playing=$playing buffering=$buffering pos=$pos');
          }
        }
      }
    });
  });
}
