import 'package:flutter/material.dart';

/// mockup 弹幕输入入口 pill——点击交给业务侧弹自己的 input UI。
///
/// SDK 不实现弹幕输入逻辑。
class DanmakuInputPill extends StatelessWidget {
  const DanmakuInputPill({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x26FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '发个友善的弹幕见证当下',
          style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 10),
        ),
      ),
    );
  }
}
