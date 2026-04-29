import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

import 'samples.dart';

/// Multi-line demo page exercising the M7 orchestration layer:
///   - [NiumaMediaSource.lines] for multi-quality sources
///   - [NiumaPlayerController.switchLine] to swap lines mid-playback
///     without losing position or play/pause state
///   - [SourceMiddleware] pipeline (toggleable mock signer that appends a
///     `?t=<timestamp>` query parameter — verify it runs on init AND on
///     each switchLine)
class MultiLinePlayerPage extends StatefulWidget {
  const MultiLinePlayerPage({super.key, required this.sample});

  final MultiLineSample sample;

  @override
  State<MultiLinePlayerPage> createState() => _MultiLinePlayerPageState();
}

class _MultiLinePlayerPageState extends State<MultiLinePlayerPage> {
  late NiumaPlayerController _controller;
  StreamSubscription<NiumaPlayerEvent>? _eventsSub;

  final List<String> _eventLog = <String>[];
  static const int _eventLogCap = 30;

  /// Mirrors the controller's active line. Updated optimistically when the
  /// user taps a chip; corrected by [LineSwitched] / [LineSwitchFailed].
  late String _activeLineId;

  /// When true, the controller is built with a [SignedUrlMiddleware] that
  /// appends `?t=<unix-millis>` to every URL. Useful to verify middleware
  /// runs on init AND each subsequent switchLine.
  bool _middlewareEnabled = false;

  /// Last URL produced by the mock signer; lets the user visually confirm
  /// that the middleware actually fired (and re-fired on switch).
  String? _lastSignedUrl;

  @override
  void initState() {
    super.initState();
    _activeLineId = widget.sample.defaultLineId;
    _buildController();
  }

  /// Builds the controller from current toggle state and kicks off init.
  /// Called from [initState] and again whenever the middleware switch
  /// flips (which requires fully recreating the controller).
  void _buildController() {
    final source = NiumaMediaSource.lines(
      lines: widget.sample.lines
          .map((l) => MediaLine(
                id: l.id,
                label: l.label,
                source: NiumaDataSource.network(l.url),
                quality: const MediaQuality(),
                priority: l.priority,
              ))
          .toList(),
      defaultLineId: widget.sample.defaultLineId,
    );

    final middlewares = <SourceMiddleware>[
      if (_middlewareEnabled)
        SignedUrlMiddleware((rawUrl) async {
          final signed =
              '$rawUrl${rawUrl.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}';
          if (mounted) setState(() => _lastSignedUrl = signed);
          return signed;
        }),
    ];

    _controller = NiumaPlayerController(source, middlewares: middlewares);

    _eventsSub = _controller.events.listen((event) {
      if (!mounted) return;
      setState(() {
        _eventLog.insert(0, event.toString());
        if (_eventLog.length > _eventLogCap) {
          _eventLog.removeRange(_eventLogCap, _eventLog.length);
        }
        if (event is LineSwitched) {
          _activeLineId = event.toId;
        }
        if (event is LineSwitchFailed) {
          _activeLineId = widget.sample.lines
              .firstWhere(
                (l) => l.id != event.toId,
                orElse: () => widget.sample.lines.first,
              )
              .id;
        }
      });
    });

    _controller.addListener(_onValueChanged);

    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      await _controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() => _eventLog.insert(0, 'initialize() threw: $e'));
    }
  }

  void _onValueChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _switchTo(String lineId) async {
    if (lineId == _activeLineId) return;
    setState(() => _activeLineId = lineId); // optimistic
    try {
      await _controller.switchLine(lineId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _eventLog.insert(0, 'switchLine() threw: $e'));
    }
  }

  Future<void> _toggleMiddleware(bool value) async {
    setState(() => _middlewareEnabled = value);
    // Tearing down + rebuilding is the simplest way to swap the middleware
    // pipeline since the field is final. Demo-grade code; real apps would
    // pick a stable middleware list at controller-construction time.
    await _disposeController();
    setState(() {
      _eventLog.clear();
      _lastSignedUrl = null;
      _activeLineId = widget.sample.defaultLineId;
    });
    _buildController();
  }

  Future<void> _disposeController() async {
    _controller.removeListener(_onValueChanged);
    await _eventsSub?.cancel();
    _eventsSub = null;
    await _controller.dispose();
  }

  @override
  void dispose() {
    unawaited(_disposeController());
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
          _statusRow(v),
          const SizedBox(height: 12),
          _lineSwitcher(),
          const SizedBox(height: 8),
          _middlewareToggle(),
          const SizedBox(height: 16),
          _positionRow(v),
          const SizedBox(height: 16),
          _eventLogPanel(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _videoArea(NiumaPlayerValue v) {
    final aspect = (v.size.width <= 0 || v.size.height <= 0)
        ? 16 / 9
        : v.size.width / v.size.height;
    return AspectRatio(
      aspectRatio: aspect,
      child: ColoredBox(
        color: Colors.black,
        child: v.hasError
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error: ${v.error?.message ?? "unknown"}',
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : (!v.initialized
                ? const Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                  )
                : NiumaPlayerView(_controller)),
      ),
    );
  }

  Widget _statusRow(NiumaPlayerValue v) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        _chip('phase', v.phase.name, _phaseColor(v.phase)),
        _chip('active', _activeLineId, Colors.indigo),
        if (v.openingStage != null)
          _chip('stage', v.openingStage!, Colors.blueGrey),
      ],
    );
  }

  Widget _lineSwitcher() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '线路（点击切换）',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.sample.lines.map((l) {
            final selected = l.id == _activeLineId;
            return ChoiceChip(
              label: Text(l.label),
              selected: selected,
              onSelected: (_) => _switchTo(l.id),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _middlewareToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.security, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Mock SignedUrl middleware',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: _middlewareEnabled,
                onChanged: _toggleMiddleware,
              ),
            ],
          ),
          const Text(
            '开启后每个 URL 末尾会被附加 ?t=<timestamp>，'
            '在 init / switchLine / 重试时各跑一次。',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (_lastSignedUrl != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '最近签名：$_lastSignedUrl',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _positionRow(NiumaPlayerValue v) {
    return Row(
      children: <Widget>[
        Text(
          'pos: ${_fmt(v.position)} / ${_fmt(v.duration)}',
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
        const Spacer(),
        IconButton(
          icon: Icon(v.effectivelyPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: !v.initialized
              ? null
              : () => v.effectivelyPlaying
                  ? _controller.pause()
                  : _controller.play(),
        ),
      ],
    );
  }

  Widget _eventLogPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '事件日志（最近 30 条）',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 4),
        if (_eventLog.isEmpty)
          const Text('(空)', style: TextStyle(color: Colors.grey, fontSize: 12))
        else
          for (final line in _eventLog)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                line,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
      ],
    );
  }

  Widget _chip(String label, String value, Color color) {
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
              style: TextStyle(fontSize: 11, color: color),
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

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }
}
