import 'package:flutter/material.dart';

import '../../cast/cast_device.dart';
import '../niuma_player_controller.dart';
import '../niuma_player_theme.dart';

/// mockup「分屏 panel」设备选择器：左 42% 视频暗化 + 右 58% 设备列表。
///
/// 取代 M15 BottomSheet 版 NiumaCastPicker。NiumaPlayer 内部用 Stack 叠
/// 在视频上方；panel 弹出时业务负责暂停视频。
///
/// [CastDevice] 字段：id / name / protocolId / icon（无 connected 字段）。
/// 右侧面板以 protocolId 展示协议类型；已连接状态由调用方通过外部逻辑区分
/// （T11 阶段 panel 无连接状态高亮，保留扩展入口 [connectedDeviceId]）。
class NiumaCastPickerPanel extends StatelessWidget {
  const NiumaCastPickerPanel({
    super.key,
    required this.controller,
    required this.onClose,
    required this.devices,
    required this.isScanning,
    required this.onSelectDevice,
    required this.onRefresh,
    this.connectedDeviceId,
  });

  final NiumaPlayerController controller;
  final VoidCallback onClose;
  final List<CastDevice> devices;
  final bool isScanning;
  final Future<void> Function(CastDevice) onSelectDevice;
  final VoidCallback onRefresh;

  /// 当前已连接的设备 id（可选），用于高亮已连接设备行。
  final String? connectedDeviceId;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return Row(
      children: [
        // 左 42%：视频区域暗化 + 居中「视频暂停中」文字
        Expanded(
          flex: 42,
          child: GestureDetector(
            onTap: onClose,
            child: const ColoredBox(
              color: Color(0xA6000000),
              child: Center(
                child: Text(
                  '视频暂停中',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ),
        ),
        // 右 58%：黑色面板——标题 + 设备列表 + 重新搜索
        Expanded(
          flex: 58,
          child: Container(
            color: const Color(0xF50F0F12),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 标题行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '选择投屏设备',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    IconButton(
                      key: const Key('cast-panel-close'),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 14,
                      ),
                      onPressed: onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 设备数量提示
                Text(
                  isScanning ? '搜索中...' : '已搜索到 ${devices.length} 台设备',
                  style: const TextStyle(
                    color: Color(0x73FFFFFF),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 8),
                // 设备列表
                Expanded(
                  child: ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (ctx, i) {
                      final device = devices[i];
                      final isConnected = device.id == connectedDeviceId;
                      return _DeviceTile(
                        device: device,
                        isConnected: isConnected,
                        onTap: () => onSelectDevice(device),
                        accent: theme.primaryAccent,
                      );
                    },
                  ),
                ),
                // 重新搜索
                InkWell(
                  onTap: onRefresh,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '↻ 重新搜索',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0x80FFFFFF),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _formatProtocol(String id) {
  switch (id.toLowerCase()) {
    case 'dlna':
      return 'DLNA';
    case 'airplay':
      return 'AirPlay';
    default:
      return id.toUpperCase();
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isConnected,
    required this.onTap,
    required this.accent,
  });

  final CastDevice device;
  final bool isConnected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isConnected
              ? accent.withValues(alpha: 0.12)
              : const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: isConnected
              ? Border.all(
                  color: accent.withValues(alpha: 0.5),
                  width: 0.5,
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              device.icon,
              size: 16,
              color: isConnected ? accent : Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    isConnected
                        ? '已连接 · ${_formatProtocol(device.protocolId)}'
                        : _formatProtocol(device.protocolId),
                    style: TextStyle(
                      color: isConnected ? accent : const Color(0x66FFFFFF),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            if (isConnected)
              SizedBox(
                width: 6,
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
