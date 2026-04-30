import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/data_source.dart';

/// 单视频续播位置的可插拔持久化契约。
///
/// 具体实现可以包装 SharedPreferences、Hive、SQLite 或远端云存储。
/// 播放器核心只依赖该接口，方便宿主 app 接入合适的后端。
abstract class ResumeStorage {
  const ResumeStorage();

  /// 返回 [key] 对应的已保存播放位置；不存在则返回 `null`。
  Future<Duration?> read(String key);

  /// 将 [position] 以 [key] 持久化，覆盖之前的值。
  Future<void> write(String key, Duration position);

  /// 删除 [key] 对应的已保存位置。
  ///
  /// 播放器在 `phase = ended` 时调用，避免下次重新播放同一视频时
  /// 还提示已过时的续播点。
  Future<void> clear(String key);
}

/// 基于 [SharedPreferences] 的默认 [ResumeStorage] 实现。
///
/// 位置以整数毫秒形式存在 `<prefix><key>` 下。这样存储紧凑，
/// 也避免浮点精度问题。宿主 app 可覆盖 [prefix] 把条目纳入应用
/// 作用域的命名空间，避免与其它库冲突。
class SharedPreferencesResumeStorage extends ResumeStorage {
  /// 创建一个 [SharedPreferencesResumeStorage]。
  ///
  /// [prefix] 会拼到每个存储 key 之前以避免与 SharedPreferences 中
  /// 其它 key 冲突；默认 `'niuma_player.resume.'`。
  const SharedPreferencesResumeStorage({this.prefix = 'niuma_player.resume.'});

  /// 用于避免冲突、拼到每个存储 key 之前的字符串。
  ///
  /// 默认 `'niuma_player.resume.'`。当宿主 app 还把
  /// SharedPreferences 用于其它数据并希望有独立命名空间时覆盖此值。
  final String prefix;

  String _k(String key) => '$prefix$key';

  @override
  Future<Duration?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_k(key));
    if (ms == null) return null;
    return Duration(milliseconds: ms);
  }

  @override
  Future<void> write(String key, Duration position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_k(key), position.inMilliseconds);
  }

  @override
  Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_k(key));
  }
}

/// 在 [NiumaPlayerController.initialize] 期间发现已保存续播位置时
/// 播放器要自动执行什么动作。
enum ResumeBehaviour {
  /// 初始化时静默 seek 到已保存位置，无需用户交互。
  auto,

  /// 触发 `onResumePrompt` 回调，让宿主 app 弹窗后再决定是否 seek。
  askUser,

  /// 加载存储、提供已保存位置，但不自动 seek。
  /// 调用方自行决定如何处理这个位置。
  disabled,
}

/// 从 [NiumaDataSource] 派生稳定存储 key 的函数类型。
///
/// 返回值会作为 [ResumeStorage.read]、[ResumeStorage.write]、
/// [ResumeStorage.clear] 的 key 使用。
typedef ResumeKeyOf = String Function(NiumaDataSource source);

/// 默认 key 派生：`video:<uri>`。
///
/// 只要 URL 一致，跨多次启动都稳定。适用于绝大多数 URI 不会随
/// 会话变化的点播场景。
String defaultResumeKey(NiumaDataSource source) => 'video:${source.uri}';

/// 传给续播编排器的配置袋。
///
/// 封装续播行为的所有可调维度：使用哪个存储后端、如何派生 key、
/// 何时不写入、发现已保存位置时怎么处理。
@immutable
class ResumePolicy {
  /// 用合理的生产环境默认值创建一个 [ResumePolicy]。
  const ResumePolicy({
    this.storage = const SharedPreferencesResumeStorage(),
    this.keyOf = defaultResumeKey,
    this.behaviour = ResumeBehaviour.auto,
    this.minSavedPosition = const Duration(seconds: 30),
    this.discardIfNearEnd = const Duration(seconds: 30),
    this.savePeriod = const Duration(seconds: 5),
  });

  /// 用于读写续播位置的可插拔存储层。
  ///
  /// 默认 [SharedPreferencesResumeStorage]。可以换成 Hive、SQLite、
  /// 远端云存储，或测试中用 [FakeResumeStorage]。
  final ResumeStorage storage;

  /// 应用于当前 [NiumaDataSource] 的 key 派生函数。
  ///
  /// 默认 [defaultResumeKey]，产出 `video:<uri>`。
  final ResumeKeyOf keyOf;

  /// 初始化时发现已保存续播位置后要执行什么动作。
  ///
  /// 默认 [ResumeBehaviour.auto]。
  final ResumeBehaviour behaviour;

  /// 至少播到多远才值得保存位置。
  ///
  /// 防止"每次重新播放都被 skip 到 5 秒"的惊吓：若用户在该阈值
  /// 之前就放弃，不保存位置。默认 30 秒。
  final Duration minSavedPosition;

  /// 距视频结尾小于该值时，已保存位置直接丢弃，下次播放不再恢复。
  ///
  /// 避免每次都从片尾前 2 秒接着播。默认 30 秒。
  final Duration discardIfNearEnd;

  /// 活跃播放期间播放器把当前 position 写入 [storage] 的频率。
  ///
  /// 值越小崩溃时丢失越少，但 I/O 开销越大。默认每 5 秒一次。
  final Duration savePeriod;
}

/// 位于 controller 生命周期事件与 [ResumeStorage] 之间。
///
/// init 时读取已保存位置；若配置为 [ResumeBehaviour.auto] 则 seek。
/// 播放期间周期性写入当前位置。在 `phase = ended` 时清掉条目，
/// 已看完的视频下次不再提示残留续播。
class ResumeOrchestrator {
  /// 创建一个 [ResumeOrchestrator]。
  ///
  /// 四个参数都必填；测试中传入 [FakeResumeStorage] 和 stub lambda。
  ResumeOrchestrator({
    required this.policy,
    required this.source,
    required this.seekTo,
    required this.currentPosition,
  });

  /// 控制存储后端、key 派生、init 行为和保存频率的配置组。
  final ResumePolicy policy;

  /// URI（经 [ResumePolicy.keyOf]）决定存储 key 的数据源。
  final NiumaDataSource source;

  /// 桥接到 controller 的回调；当发现已保存位置且 behaviour 为
  /// [ResumeBehaviour.auto] 时，会被调用以 seek 到该位置。
  final Future<void> Function(Duration) seekTo;

  /// 同步返回当前播放位置的函数。
  ///
  /// 每个周期 tick 和 [dispose] 时都会被调用。
  final Duration Function() currentPosition;

  Timer? _saveTimer;
  String get _key => policy.keyOf(source);

  /// 在 controller 的 `initialize()` 完成后调用。
  ///
  /// 从存储中读取已保存位置；若存在且 [ResumePolicy.behaviour] 为
  /// [ResumeBehaviour.auto] 则立即 seek。[ResumeBehaviour.askUser]
  /// 由调用方负责触发自己的 prompt 回调。
  Future<void> onInitialized() async {
    if (policy.behaviour == ResumeBehaviour.disabled) return;
    final saved = await policy.storage.read(_key);
    if (saved == null) return;
    if (policy.behaviour == ResumeBehaviour.auto) {
      await seekTo(saved);
    }
    // askUser：由调用方负责触发 onResumePrompt。
  }

  /// 启动周期性保存定时器。
  ///
  /// 通常在第一次 `play` 事件时调用。会先取消已有 timer，因此该
  /// 方法是幂等的。
  void startPeriodicSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(policy.savePeriod, (_) => _saveIfApplicable());
  }

  Future<void> _saveIfApplicable() async {
    final pos = currentPosition();
    if (pos < policy.minSavedPosition) return;
    await policy.storage.write(_key, pos);
  }

  /// 在 `phase = ended` 时调用，无条件清除续播条目。
  ///
  /// 用户已经把视频看完了，下次播放没有有意义的位置可恢复。
  Future<void> onEnded() async {
    await policy.storage.clear(_key);
  }

  /// 取消周期性保存定时器；若当前 position ≥
  /// [ResumePolicy.minSavedPosition]，做一次最终写入。
  Future<void> dispose() async {
    _saveTimer?.cancel();
    final pos = currentPosition();
    if (pos >= policy.minSavedPosition) {
      await policy.storage.write(_key, pos);
    }
  }
}
