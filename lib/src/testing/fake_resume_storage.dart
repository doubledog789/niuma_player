import 'package:niuma_player/src/orchestration/resume_position.dart';

/// 用于 widget 和单元测试的内存版 [ResumeStorage] 测试替身。
///
/// 所有状态都存放在一个普通 [Map] 中——不会写入磁盘。在自己的 widget
/// 测试里通过 `lib/testing.dart` 导出（或直接从
/// `package:niuma_player/src/testing/fake_resume_storage.dart` 引入）该
/// 类，即可注入一个可控的存储后端，避免接触文件系统或 shared
/// preferences。
///
/// 使用 `implements` 而非 `extends`，这样将来 [ResumeStorage] 新增的
/// protected 行为不会泄漏到本测试替身中。
class FakeResumeStorage implements ResumeStorage {
  final Map<String, Duration> _store = {};

  @override
  Future<Duration?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, Duration position) async {
    _store[key] = position;
  }

  @override
  Future<void> clear(String key) async {
    _store.remove(key);
  }

  /// 当前内存存储的只读快照。
  ///
  /// 用于在测试断言中校验存储的精确内容，无需走 [read] API。
  Map<String, Duration> get snapshot => Map.unmodifiable(_store);
}
