/// Public test doubles for niuma_player consumers' widget tests.
///
/// Import as `package:niuma_player/testing.dart`. Exposes in-memory
/// fake implementations of the orchestration-layer abstractions so apps
/// can write widget tests without standing up real storage / network /
/// analytics infrastructure.
library;

export 'src/testing/fake_resume_storage.dart';
export 'src/testing/fake_analytics_emitter.dart';
