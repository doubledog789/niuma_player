import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../data/video_player_backend.dart';
import '../domain/player_backend.dart';
import '../domain/player_state.dart';
import 'niuma_player_controller.dart';

/// Renders the currently active backend for a [NiumaPlayerController].
///
/// Automatically rebuilds when the backend swaps (e.g. fallback to IJK) so
/// callers can just drop this into their widget tree.
class NiumaPlayerView extends StatelessWidget {
  const NiumaPlayerView(this.controller, {super.key, this.aspectRatio});

  final NiumaPlayerController controller;

  /// If null, we fall back to `controller.value.size`. If both are
  /// unavailable we render a 16:9 box so layout stays stable.
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NiumaPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final backend = controller.backend;
        final ratio = aspectRatio ?? _ratioFromValue(value);
        final Widget child;
        if (backend is VideoPlayerBackend) {
          child = VideoPlayer(backend.innerController);
        } else if (backend != null &&
            backend.kind == PlayerBackendKind.ijk &&
            controller.textureId != null) {
          child = Texture(textureId: controller.textureId!);
        } else {
          child = const SizedBox.shrink();
        }
        return AspectRatio(
          aspectRatio: ratio,
          child: child,
        );
      },
    );
  }

  double _ratioFromValue(NiumaPlayerValue value) {
    if (value.initialized &&
        value.size.width > 0 &&
        value.size.height > 0) {
      return value.size.width / value.size.height;
    }
    return 16 / 9;
  }
}
