import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:niuma_player/niuma_player.dart';

/// Inspector for the native [DeviceMemory] store.
///
/// Lets you:
///   - read the device fingerprint as Kotlin computes it (sha1 of
///     manufacturer|model|sdk-int)
///   - mark / unmark / clear the IJK-needed flag
///   - inspect the raw stored value (expiresAt) under any fingerprint
///
/// Together this validates the M3.1 native DeviceMemoryStore end to end:
/// the round-trip Dart → MethodChannel → SharedPreferences → MethodChannel
/// → Dart should be visible here.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  static const MethodChannel _channel = MethodChannel('cn.niuma/player');

  String? _fingerprint;

  /// Last lookup result keyed by the fingerprint we asked about.
  String? _lastLookupTarget;
  String _lastLookupResult = '(尚未查询)';

  /// Inputs.
  final TextEditingController _fpInput = TextEditingController();
  Duration _markTtl = Duration.zero; // 0 = forever

  bool _busy = false;

  static const List<MapEntry<String, Duration>> _ttlOptions =
      <MapEntry<String, Duration>>[
    MapEntry('永久', Duration.zero),
    MapEntry('30 秒', Duration(seconds: 30)),
    MapEntry('5 分钟', Duration(minutes: 5)),
    MapEntry('1 小时', Duration(hours: 1)),
    MapEntry('1 天', Duration(days: 1)),
  ];

  @override
  void initState() {
    super.initState();
    _loadFingerprint();
  }

  @override
  void dispose() {
    _fpInput.dispose();
    super.dispose();
  }

  Future<void> _loadFingerprint() async {
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('deviceFingerprint');
      if (!mounted) return;
      setState(() {
        _fingerprint = result?['fingerprint'] as String?;
        _fpInput.text = _fingerprint ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _fingerprint = '(error: $e)');
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _toast('错误: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String get _targetFp => _fpInput.text.trim();

  Future<void> _markIjkNeeded() async {
    final fp = _targetFp;
    if (fp.isEmpty) {
      _toast('请输入或加载指纹');
      return;
    }
    await _runBusy(() async {
      final mem = DeviceMemory();
      await mem.markIjkNeeded(
        fp,
        ttl: _markTtl == Duration.zero ? null : _markTtl,
      );
      _toast('已标记 $fp (TTL=${_ttlLabel(_markTtl)})');
    });
  }

  Future<void> _checkShouldUseIjk() async {
    final fp = _targetFp;
    if (fp.isEmpty) {
      _toast('请输入或加载指纹');
      return;
    }
    await _runBusy(() async {
      final mem = DeviceMemory();
      final hit = await mem.shouldUseIjk(fp);
      // Also peek raw expiresAt so the UI shows what's actually stored.
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'deviceMemory.get',
        <String, dynamic>{'fingerprint': fp},
      );
      setState(() {
        _lastLookupTarget = fp;
        if (raw == null) {
          _lastLookupResult = 'shouldUseIjk = $hit\nstored = (none)';
        } else {
          final expiresAt = (raw['expiresAt'] as num?)?.toInt();
          final readable = expiresAt == null
              ? '(forever)'
              : DateTime.fromMillisecondsSinceEpoch(expiresAt)
                  .toIso8601String();
          _lastLookupResult =
              'shouldUseIjk = $hit\nexpiresAt = $expiresAt\nreadable = $readable';
        }
      });
    });
  }

  Future<void> _unsetCurrent() async {
    final fp = _targetFp;
    if (fp.isEmpty) {
      _toast('请输入或加载指纹');
      return;
    }
    await _runBusy(() async {
      await _channel.invokeMethod<void>(
        'deviceMemory.unset',
        <String, dynamic>{'fingerprint': fp},
      );
      _toast('已清除 $fp');
      setState(() {
        _lastLookupTarget = fp;
        _lastLookupResult = 'shouldUseIjk = false (just unset)';
      });
    });
  }

  Future<void> _clearAll() async {
    await _runBusy(() async {
      await NiumaPlayerController.clearDeviceMemory();
      _toast('已清空全部 DeviceMemory');
      setState(() {
        _lastLookupTarget = null;
        _lastLookupResult = '(尚未查询)';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('诊断 / DeviceMemory')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            // Fingerprint
            const Text(
              '设备指纹（native 端实时计算）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SelectableText(
                      _fingerprint ?? '加载中…',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: '重新读取',
                    onPressed: _busy ? null : _loadFingerprint,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Text(
              '操作目标 fingerprint（默认是当前设备）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _fpInput,
              style:
                  const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),
            const Text(
              'TTL（仅 markIjkNeeded 用）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final opt in _ttlOptions)
                  ChoiceChip(
                    label: Text(opt.key),
                    selected: _markTtl == opt.value,
                    onSelected: (sel) {
                      if (sel) setState(() => _markTtl = opt.value);
                    },
                  ),
              ],
            ),

            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ElevatedButton.icon(
                  onPressed: _busy ? null : _markIjkNeeded,
                  icon: const Icon(Icons.add),
                  label: const Text('标记 IJK needed'),
                ),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _checkShouldUseIjk,
                  icon: const Icon(Icons.search),
                  label: const Text('查询 shouldUseIjk'),
                ),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _unsetCurrent,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清除该指纹'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _clearAll,
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('清空全部'),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Text(
              '最近一次查询结果',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_lastLookupTarget != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'target: ${_lastLookupTarget!}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  Text(
                    _lastLookupResult,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ttlLabel(Duration d) {
    if (d == Duration.zero) return 'forever';
    if (d.inDays > 0) return '${d.inDays}d';
    if (d.inHours > 0) return '${d.inHours}h';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }
}
