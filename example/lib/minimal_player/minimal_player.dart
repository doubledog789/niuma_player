import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

const _sampleUrl = 'https://artplayer.org/assets/sample/bbb-video.mp4';

/// 最小接入：controller + NiumaPlayerView + ValueListenableBuilder 控件。
class MinimalPlayerPage extends StatefulWidget {
  const MinimalPlayerPage({super.key});

  @override
  State<MinimalPlayerPage> createState() => _MinimalPlayerPageState();
}

class _MinimalPlayerPageState extends State<MinimalPlayerPage> {
  late final NiumaPlayerController _controller;
  late Future<void> _initializeFuture;

  @override
  void initState() {
    super.initState();
    _controller = NiumaPlayerController.dataSource(
      NiumaDataSource.network(_sampleUrl),
    );
    _initializeFuture = _initializeAndPlay();
  }

  Future<void> _initializeAndPlay() async {
    await _controller.initialize();
    if (mounted) await _controller.play();
  }

  void _retry() {
    setState(() {
      _initializeFuture = _initializeAndPlay();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('最小播放器')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NiumaPlayerView(_controller),
                      FutureBuilder<void>(
                        future: _initializeFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError) {
                            return _ErrorOverlay(
                              message: snapshot.error.toString(),
                              onRetry: _retry,
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              ValueListenableBuilder<NiumaPlayerValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  return _Controls(
                    value: value,
                    onPlayPause:
                        value.isPlaying ? _controller.pause : _controller.play,
                    onSeek: _controller.seekTo,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.value,
    required this.onPlayPause,
    required this.onSeek,
  });

  final NiumaPlayerValue value;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final maxMs = value.duration.inMilliseconds;
    final hasDuration = maxMs > 0;
    final positionMs = hasDuration
        ? value.position.inMilliseconds.clamp(0, maxMs).toDouble()
        : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: value.initialized ? onPlayPause : null,
          ),
          Expanded(
            child: Slider(
              value: positionMs,
              max: hasDuration ? maxMs.toDouble() : 1,
              onChanged: hasDuration
                  ? (v) => onSeek(Duration(milliseconds: v.round()))
                  : null,
            ),
          ),
          Text(
            '${formatVideoTime(value.position)} / '
            '${formatVideoTime(value.duration)}',
          ),
        ],
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}
