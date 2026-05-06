import 'package:flutter/material.dart';

import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_theme.dart';

/// mockup 顶栏的「线路切换」pill——多 line 时显示当前 line label。
///
/// 单 line 场景返回 [SizedBox.shrink]，不占用顶栏空间。
/// 点击展示 line 选择 popup menu。
///
/// 监听 [controller]（ValueNotifier）：[switchLine] 成功后 controller value
/// 推送会触发 listener 重建，pill label 实时反映新 line。
class LineSwitchPill extends StatelessWidget {
  const LineSwitchPill({super.key, required this.controller});

  final NiumaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final lines = controller.source.lines;
    if (lines.length <= 1) return const SizedBox.shrink();

    final theme = NiumaPlayerTheme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (ctx, _) {
        final activeId = controller.activeLineId;
        final current = lines.firstWhere(
          (l) => l.id == activeId,
          orElse: () => controller.source.currentLine,
        );
        return InkWell(
          onTap: () => _showMenu(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0x80FFFFFF), width: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              current.label,
              style: TextStyle(
                color: theme.actionIconColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final lines = controller.source.lines;
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    final RelativeRect position;
    if (renderBox != null && overlay != null) {
      final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
      final size = renderBox.size;
      position = RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        overlay.size.width - offset.dx - size.width,
        overlay.size.height - offset.dy - size.height,
      );
    } else {
      position = const RelativeRect.fromLTRB(0, 80, 0, 0);
    }

    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: [
        for (final line in lines)
          PopupMenuItem<String>(value: line.id, child: Text(line.label)),
      ],
    );
    if (selected != null) {
      await controller.switchLine(selected);
    }
  }
}
