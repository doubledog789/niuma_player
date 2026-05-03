import 'dart:async';
import 'package:flutter/material.dart';
import '../../cast/cast_device.dart';
import '../../cast/cast_registry.dart';
import '../../cast/cast_session.dart';
import '../../cast/cast_state.dart';
import '../niuma_player_controller.dart';

/// 投屏设备选择 / 投屏中切换断开 bottom sheet。
class NiumaCastPicker {
  NiumaCastPicker._();

  /// inline 状态——展示完整设备发现 picker。
  static void show(BuildContext ctx, NiumaPlayerController controller) {
    // 在弹 sheet 之前就开始发现，discovery state 传入 sheet 共享。
    final state = _DiscoveryState();
    state.startDiscovery();
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DiscoverySheet(controller: controller, state: state),
    ).then((_) => state.dispose());
  }

  /// 投屏中——展示简化 picker（切换 / 断开）。
  static void showConnected(
    BuildContext ctx,
    NiumaPlayerController controller,
    CastSession session,
  ) {
    showModalBottomSheet<void>(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ConnectedSheet(controller: controller, session: session),
    );
  }
}

/// 发现状态：在 sheet 打开前就启动，确保 sheet 第一帧就能看到最新数据。
class _DiscoveryState extends ChangeNotifier {
  final List<CastDevice> devices = [];
  bool scanning = true;

  final List<StreamSubscription<List<CastDevice>>> _subs = [];
  Timer? _timeout;
  int _pendingSubs = 0;

  void startDiscovery() {
    final services = NiumaCastRegistry.all();
    _pendingSubs = services.length;
    if (_pendingSubs == 0) {
      scanning = false;
      // notifyListeners not needed yet—sheet hasn't been built
      return;
    }
    for (final svc in services) {
      _subs.add(svc.discover().listen(
        (batch) {
          for (final d in batch) {
            if (!devices.any((e) => e.id == d.id)) devices.add(d);
          }
          notifyListeners();
        },
        onDone: () {
          _pendingSubs--;
          if (_pendingSubs <= 0) {
            scanning = false;
            _timeout?.cancel();
            _timeout = null;
            notifyListeners();
          }
        },
        onError: (_) {
          _pendingSubs--;
          if (_pendingSubs <= 0) {
            scanning = false;
            _timeout?.cancel();
            _timeout = null;
            notifyListeners();
          }
        },
      ));
    }
    // Hard timeout: 8s fallback for infinite-running streams.
    _timeout = Timer(const Duration(seconds: 8), () {
      if (scanning) {
        scanning = false;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _timeout?.cancel();
    super.dispose();
  }
}

class _DiscoverySheet extends StatelessWidget {
  const _DiscoverySheet({required this.controller, required this.state});
  final NiumaPlayerController controller;
  final _DiscoveryState state;

  Future<void> _onPickDevice(BuildContext context, CastDevice d) async {
    final svc = NiumaCastRegistry.byProtocolId(d.protocolId);
    if (svc == null) return;
    Navigator.of(context).pop();
    try {
      final session = await svc.connect(d, controller);
      await controller.connectCast(session);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (ctx, _) {
        final devices = state.devices;
        final scanning = state.scanning;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      '选择投屏设备',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('发现', style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 8),
                    if (scanning)
                      const Row(children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 6),
                        Text('扫描中...',
                            style: TextStyle(color: Colors.grey)),
                      ])
                    else
                      Text(
                        '找到 ${devices.length} 台',
                        style: const TextStyle(color: Colors.grey),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (devices.isEmpty && !scanning)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        '未发现设备\n请确保手机和电视在同一 WiFi',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...devices.map((d) => ListTile(
                        leading: Icon(d.icon),
                        title: Text(d.name),
                        onTap: () => _onPickDevice(ctx, d),
                      )),
                if (scanning && devices.isEmpty) const SizedBox(height: 80),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectedSheet extends StatelessWidget {
  const _ConnectedSheet({required this.controller, required this.session});
  final NiumaPlayerController controller;
  final CastSession session;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(session.device.icon, color: Colors.lightBlueAccent),
              title: Text(session.device.name),
              subtitle: const Text('投屏中'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('切换设备'),
              onTap: () {
                Navigator.of(context).pop();
                NiumaCastPicker.show(context, controller);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.red),
              title:
                  const Text('断开投屏', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.of(context).pop();
                controller.disconnectCast(reason: CastEndReason.userCancelled);
              },
            ),
          ],
        ),
      ),
    );
  }
}
