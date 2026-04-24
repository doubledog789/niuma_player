import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

void main() {
  runApp(const NiumaPlayerDemoApp());
}

class NiumaPlayerDemoApp extends StatelessWidget {
  const NiumaPlayerDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'niuma_player demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const DemoHomePage(),
    );
  }
}

/// A fixed demo case exposed as a row button.
class _Sample {
  const _Sample({
    required this.label,
    required this.url,
    this.forceIjkOnAndroid = false,
  });

  final String label;
  final String url;
  final bool forceIjkOnAndroid;
}

const List<_Sample> _samples = <_Sample>[
  _Sample(
    label: '播放 h264 mp4',
    url:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  ),
  _Sample(
    label: '播放 h265 mp4',
    url:
        'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h265/1080/Big_Buck_Bunny_1080_10s_1MB.mp4',
  ),
  _Sample(
    label: '播放 HLS m3u8',
    url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
  _Sample(
    label: '强制 IJK 播放 m3u8',
    url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    forceIjkOnAndroid: true,
  ),
];

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  NiumaPlayerController? _controller;
  StreamSubscription<NiumaPlayerEvent>? _eventsSub;
  VoidCallback? _valueListener;

  /// The last 20 events formatted as strings.
  final List<String> _eventLog = <String>[];

  /// Mirrors `_controller.value` so we can rebuild on state changes.
  NiumaPlayerValue? _value;

  /// True while we are waiting for `initialize()` to resolve.
  bool _loading = false;

  /// The label of the most recent sample we tried to load.
  String? _currentSampleLabel;

  /// The last `BackendSelected` event observed; used to show the fromMemory flag.
  BackendSelected? _lastBackendSelected;

  @override
  void dispose() {
    _teardownController();
    super.dispose();
  }

  Future<void> _teardownController() async {
    await _eventsSub?.cancel();
    _eventsSub = null;
    final listener = _valueListener;
    final controller = _controller;
    if (listener != null && controller != null) {
      controller.removeListener(listener);
    }
    _valueListener = null;
    await controller?.dispose();
    _controller = null;
  }

  Future<void> _loadSample(_Sample sample) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _currentSampleLabel = sample.label;
      _value = null;
      _eventLog.clear();
      _lastBackendSelected = null;
    });

    await _teardownController();

    final controller = NiumaPlayerController(
      NiumaDataSource.network(sample.url),
      options: NiumaPlayerOptions(
        forceIjkOnAndroid: sample.forceIjkOnAndroid,
      ),
    );

    _controller = controller;

    _eventsSub = controller.events.listen((event) {
      if (!mounted) return;
      setState(() {
        _eventLog.insert(0, event.toString());
        if (_eventLog.length > 20) {
          _eventLog.removeRange(20, _eventLog.length);
        }
        if (event is BackendSelected) {
          _lastBackendSelected = event;
        }
      });
    });

    void onValueChanged() {
      if (!mounted) return;
      setState(() {
        _value = controller.value;
      });
    }

    _valueListener = onValueChanged;
    controller.addListener(onValueChanged);
    // seed
    _value = controller.value;

    try {
      await controller.initialize();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _eventLog.insert(0, 'initialize() threw: $e');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _clearMemory() async {
    try {
      await NiumaPlayerController.clearDeviceMemory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DeviceMemory cleared')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('clear failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final value = _value;

    return Scaffold(
      appBar: AppBar(title: const Text('niuma_player demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // 1. Four sample buttons
          for (final sample in _samples) ...<Widget>[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : () => _loadSample(sample),
                child: Text(sample.label),
              ),
            ),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 8),

          // 2. Active backend
          if (_currentSampleLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '当前样本: $_currentSampleLabel',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          _BackendStatus(
            controller: controller,
            lastSelected: _lastBackendSelected,
          ),

          const SizedBox(height: 12),

          // 3. Video + controls
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: _buildVideoArea(controller, value),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              ElevatedButton(
                onPressed: (controller != null && value?.initialized == true)
                    ? () => controller.play()
                    : null,
                child: const Text('Play'),
              ),
              ElevatedButton(
                onPressed: (controller != null && value?.initialized == true)
                    ? () => controller.pause()
                    : null,
                child: const Text('Pause'),
              ),
              ElevatedButton(
                onPressed: (controller != null && value?.initialized == true)
                    ? () => controller.seekTo(
                          (value!.position) + const Duration(seconds: 10),
                        )
                    : null,
                child: const Text('Seek +10s'),
              ),
            ],
          ),

          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _clearMemory,
            child: const Text('清除记忆'),
          ),

          const SizedBox(height: 16),
          const Text(
            '事件日志 (最新 20 条)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          if (_eventLog.isEmpty)
            const Text('(空)')
          else
            for (final line in _eventLog)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  line,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildVideoArea(
    NiumaPlayerController? controller,
    NiumaPlayerValue? value,
  ) {
    if (controller == null) {
      return const Text(
        '请选择一个视频源',
        style: TextStyle(color: Colors.white70),
      );
    }
    if (_loading || value == null || !value.initialized) {
      if (value?.hasError == true) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Error: ${value!.errorMessage}',
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        );
      }
      return const CircularProgressIndicator();
    }
    if (value.hasError) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Error: ${value.errorMessage}',
          style: const TextStyle(color: Colors.redAccent),
          textAlign: TextAlign.center,
        ),
      );
    }
    return NiumaPlayerView(controller);
  }
}

class _BackendStatus extends StatelessWidget {
  const _BackendStatus({
    required this.controller,
    required this.lastSelected,
  });

  final NiumaPlayerController? controller;
  final BackendSelected? lastSelected;

  @override
  Widget build(BuildContext context) {
    if (controller == null) {
      return const Text('activeBackend: (none)');
    }
    final kind = controller!.activeBackend;
    final fromMemory = lastSelected?.fromMemory ?? false;
    return Text(
      'activeBackend: $kind  (fromMemory: $fromMemory)',
      style: const TextStyle(fontWeight: FontWeight.w500),
    );
  }
}
