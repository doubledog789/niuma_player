import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

import 'samples.dart';

/// Demo player page. Surfaces every state field exposed by the M1/M2
/// contract so the user can visually confirm that:
///   - phase transitions correctly across opening / ready / playing /
///     paused / buffering / ended / error
///   - looping doesn't flicker through "ended"
///   - errors come back with a [PlayerErrorCategory]
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.sample});

  final Sample sample;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final NiumaPlayerController _controller;
  StreamSubscription<NiumaPlayerEvent>? _eventsSub;

  /// Newest-first event log, capped to keep the UI responsive.
  final List<String> _eventLog = <String>[];
  static const int _eventLogCap = 30;

  BackendSelected? _backendSelected;

  // Runtime control state.
  bool _looping = false;
  double _speed = 1.0;
  double _volume = 1.0;

  /// While the user is dragging the scrubber, show the drag value instead of
  /// the live position so the thumb doesn't jump back mid-gesture.
  double? _scrubMs;

  @override
  void initState() {
    super.initState();
    _looping = widget.sample.startsLooping;

    _controller = NiumaPlayerController.dataSource(
      NiumaDataSource.network(widget.sample.url),
      options: NiumaPlayerOptions(
        forceIjkOnAndroid: widget.sample.forceIjkOnAndroid,
      ),
    );

    _eventsSub = _controller.events.listen((event) {
      if (!mounted) return;
      setState(() {
        _eventLog.insert(0, event.toString());
        if (_eventLog.length > _eventLogCap) {
          _eventLog.removeRange(_eventLogCap, _eventLog.length);
        }
        if (event is BackendSelected) _backendSelected = event;
      });
    });

    _controller.addListener(_onValueChanged);

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      // Apply runtime config that's already settled before initialize lands.
      // M2's command queueing means these would also work if invoked earlier,
      // but doing it post-initialize keeps the demo flow obvious.
      if (_looping) await _controller.setLooping(true);
      if (_speed != 1.0) await _controller.setPlaybackSpeed(_speed);
      if (_volume != 1.0) await _controller.setVolume(_volume);
      await _controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() => _eventLog.insert(0, 'initialize() threw: $e'));
    }
  }

  void _onValueChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onValueChanged);
    unawaited(_eventsSub?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _controller.value;

    return Scaffold(
      appBar: AppBar(title: Text(widget.sample.label)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: <Widget>[
          const SizedBox(height: 8),
          _videoArea(v),
          const SizedBox(height: 12),
          _StatusPanel(value: v, backendSelected: _backendSelected),
          const SizedBox(height: 12),
          _Scrubber(
            value: v,
            scrubMs: _scrubMs,
            onChanged: (x) => setState(() => _scrubMs = x),
            onChangeEnd: (x) async {
              await _controller.seekTo(Duration(milliseconds: x.toInt()));
              if (mounted) setState(() => _scrubMs = null);
            },
          ),
          _PlayPauseSkipRow(
            value: v,
            onPlay: () => _controller.play(),
            onPause: () => _controller.pause(),
            onSeek: (d) => _controller.seekTo(d),
          ),
          const SizedBox(height: 8),
          _RuntimeControls(
            looping: _looping,
            speed: _speed,
            volume: _volume,
            onLoopingChanged: (b) {
              setState(() => _looping = b);
              _controller.setLooping(b);
            },
            onSpeedChanged: (x) {
              setState(() => _speed = x);
              _controller.setPlaybackSpeed(x);
            },
            onVolumeChanged: (x) {
              setState(() => _volume = x);
              _controller.setVolume(x);
            },
          ),
          const SizedBox(height: 16),
          _EventLog(events: _eventLog),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _videoArea(NiumaPlayerValue v) {
    final aspect = _aspectRatio(v);
    return AspectRatio(
      aspectRatio: aspect,
      child: ColoredBox(
        color: Colors.black,
        child: _videoContent(v),
      ),
    );
  }

  Widget _videoContent(NiumaPlayerValue v) {
    if (v.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Error: ${v.error?.message ?? "unknown"}',
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!v.initialized) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
        ),
      );
    }
    return NiumaPlayerView(_controller);
  }

  double _aspectRatio(NiumaPlayerValue v) {
    if (v.size.width <= 0 || v.size.height <= 0) return 16 / 9;
    return v.size.width / v.size.height;
  }
}

// ─────────────────────────── Status panel ────────────────────────────────

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.value, required this.backendSelected});

  final NiumaPlayerValue value;
  final BackendSelected? backendSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _StatusChip(
                label: 'phase',
                value: value.phase.name,
                color: _phaseColor(value.phase),
              ),
              _StatusChip(
                label: 'backend',
                value: backendSelected?.kind.name ?? '—',
                color: Colors.indigo,
              ),
              if (backendSelected?.fromMemory == true)
                const _StatusChip(
                  label: 'fromMemory',
                  value: 'true',
                  color: Colors.purple,
                ),
              if (value.openingStage != null)
                _StatusChip(
                  label: 'stage',
                  value: value.openingStage!,
                  color: Colors.blueGrey,
                ),
              if (value.error != null) ...<Widget>[
                _StatusChip(
                  label: 'error.category',
                  value: value.error!.category.name,
                  color: Colors.red,
                ),
                if (value.error!.code != null)
                  _StatusChip(
                    label: 'error.code',
                    value: value.error!.code!,
                    color: Colors.red.shade300,
                  ),
              ],
            ],
          ),
          if (value.error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              value.error!.message,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Color _phaseColor(PlayerPhase phase) {
    switch (phase) {
      case PlayerPhase.idle:
      case PlayerPhase.opening:
        return Colors.grey;
      case PlayerPhase.ready:
      case PlayerPhase.paused:
        return Colors.blue;
      case PlayerPhase.playing:
        return Colors.green;
      case PlayerPhase.buffering:
        return Colors.orange;
      case PlayerPhase.ended:
        return Colors.deepPurple;
      case PlayerPhase.error:
        return Colors.red;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text.rich(
        TextSpan(
          children: <TextSpan>[
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w400,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Scrubber ────────────────────────────────────

class _Scrubber extends StatelessWidget {
  const _Scrubber({
    required this.value,
    required this.scrubMs,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final NiumaPlayerValue value;
  final double? scrubMs;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final durMs = value.duration.inMilliseconds.toDouble();
    final posMs = value.position.inMilliseconds.toDouble();
    final bufMs = value.bufferedPosition.inMilliseconds.toDouble();
    final hasDuration = durMs > 0;
    final displayMs = scrubMs ?? posMs;

    final theme = Theme.of(context);
    final timeStyle = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return Row(
      children: <Widget>[
        SizedBox(
          width: 56,
          child: Text(
            _fmtDuration(Duration(milliseconds: displayMs.toInt())),
            textAlign: TextAlign.center,
            style: timeStyle,
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Buffered fill: thin grey bar behind the scrubber.
              if (hasDuration)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (bufMs / durMs).clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: Colors.transparent,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                ),
                child: Slider(
                  value: hasDuration ? displayMs.clamp(0, durMs) : 0,
                  min: 0,
                  max: hasDuration ? durMs : 1,
                  onChanged: hasDuration ? onChanged : null,
                  onChangeEnd: hasDuration ? onChangeEnd : null,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            hasDuration ? _fmtDuration(value.duration) : '--:--',
            textAlign: TextAlign.center,
            style: timeStyle,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Play/Pause/Skip ─────────────────────────────

class _PlayPauseSkipRow extends StatelessWidget {
  const _PlayPauseSkipRow({
    required this.value,
    required this.onPlay,
    required this.onPause,
    required this.onSeek,
  });

  final NiumaPlayerValue value;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Show pause icon while the user *intends* to play (covers buffering),
    // play icon otherwise. This is what `effectivelyPlaying` was added for.
    final showingPause = value.effectivelyPlaying;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        IconButton(
          tooltip: '后退 10 秒',
          iconSize: 32,
          onPressed: !value.initialized
              ? null
              : () {
                  final next = value.position - const Duration(seconds: 10);
                  onSeek(next.isNegative ? Duration.zero : next);
                },
          icon: const Icon(Icons.replay_10),
        ),
        IconButton(
          tooltip: showingPause ? '暂停' : '播放',
          iconSize: 56,
          color: theme.colorScheme.primary,
          onPressed: !value.initialized
              ? null
              : () => showingPause ? onPause() : onPlay(),
          icon: Icon(
            showingPause
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
          ),
        ),
        IconButton(
          tooltip: '前进 10 秒',
          iconSize: 32,
          onPressed: !value.initialized
              ? null
              : () {
                  final next = value.position + const Duration(seconds: 10);
                  onSeek(next > value.duration ? value.duration : next);
                },
          icon: const Icon(Icons.forward_10),
        ),
      ],
    );
  }
}

// ────────────────── Runtime controls (loop / speed / volume) ─────────────

class _RuntimeControls extends StatelessWidget {
  const _RuntimeControls({
    required this.looping,
    required this.speed,
    required this.volume,
    required this.onLoopingChanged,
    required this.onSpeedChanged,
    required this.onVolumeChanged,
  });

  final bool looping;
  final double speed;
  final double volume;
  final ValueChanged<bool> onLoopingChanged;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onVolumeChanged;

  static const List<double> _speeds = <double>[0.5, 1.0, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.repeat, size: 18),
            const SizedBox(width: 8),
            const Text('循环', style: TextStyle(fontSize: 13)),
            const Spacer(),
            Switch(value: looping, onChanged: onLoopingChanged),
          ],
        ),
        Row(
          children: <Widget>[
            const Icon(Icons.speed, size: 18),
            const SizedBox(width: 8),
            const Text('速度', style: TextStyle(fontSize: 13)),
            const Spacer(),
            DropdownButton<double>(
              value: speed,
              underline: const SizedBox.shrink(),
              items: _speeds
                  .map((s) => DropdownMenuItem<double>(
                        value: s,
                        child: Text('${s}x'),
                      ))
                  .toList(),
              onChanged: (s) {
                if (s != null) onSpeedChanged(s);
              },
            ),
          ],
        ),
        Row(
          children: <Widget>[
            const Icon(Icons.volume_up, size: 18),
            const SizedBox(width: 8),
            const Text('音量', style: TextStyle(fontSize: 13)),
            Expanded(
              child: Slider(
                value: volume,
                onChanged: onVolumeChanged,
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '${(volume * 100).toInt()}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────── Event log ───────────────────────────────────

class _EventLog extends StatelessWidget {
  const _EventLog({required this.events});

  final List<String> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '事件日志 (newest first, 最近 30 条)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 4),
        if (events.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '(空)',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          )
        else
          for (final line in events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                line,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
      ],
    );
  }
}

String _fmtDuration(Duration d) {
  final totalSeconds = d.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }
  return '${two(minutes)}:${two(seconds)}';
}
