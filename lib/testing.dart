/// 供 niuma_player 使用方编写 widget 测试用的公共测试替身。
///
/// 通过 `package:niuma_player/testing.dart` 引入。提供编排层抽象的
/// 内存版 fake 实现，使应用无需搭建真实的存储 / 网络 / analytics
/// 基础设施即可编写 widget 测试。
library;

export 'src/testing/fake_resume_storage.dart';
export 'src/testing/fake_analytics_emitter.dart';
