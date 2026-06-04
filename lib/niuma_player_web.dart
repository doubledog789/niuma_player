/// Web platform stub registrar.
///
/// This package's web support is implemented entirely in pure Dart via
/// conditional imports — see `lib/src/data/default_backend_factory_web.dart`,
/// which uses `package:web` + `dart:ui_web` without going through a platform
/// channel.
///
/// This file exists solely so that the `flutter_web_plugins` plugin discovery
/// machinery can satisfy the `pubspec.yaml` `flutter.plugin.platforms.web`
/// entry. The registrar is a deliberate no-op.
library;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// No-op web plugin registrar. See library doc.
class NiumaPlayerWebRegistrar {
  /// Called by Flutter's web plugin host. Intentionally empty — all web
  /// behavior is handled in `WebVideoBackend` through Dart-side conditional
  /// imports.
  static void registerWith(Registrar registrar) {
    // intentional no-op
  }
}
