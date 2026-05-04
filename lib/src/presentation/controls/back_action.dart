import 'package:flutter/material.dart';

/// 顶栏返回按钮——全屏态点击退出全屏 (pop fullscreen route)。
class BackAction extends StatelessWidget {
  const BackAction({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
      onPressed: onBack,
      tooltip: '返回',
    );
  }
}
