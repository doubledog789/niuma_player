import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 资源包 splash.svg 渲染的 Flutter 启动页。
///
/// native splash（iOS LaunchScreen + Android launch_background）只能用
/// 位图，所以放 splash_logo PNG 兜底；这个 widget 走在 native splash
/// 之后、Home 路由之前——给 SVG 那张完整的"终端 + 牛马头 + 进度条 +
/// slogan + 版本号"内容一个亮相的位置。
class NiumaSplashScreen extends StatefulWidget {
  const NiumaSplashScreen({
    super.key,
    required this.next,
    this.duration = const Duration(milliseconds: 1200),
  });

  /// splash 结束后跳的目标 widget builder（一般传 Home 页）。
  final WidgetBuilder next;

  /// splash 停留时长，默认 1.2s。
  final Duration duration;

  @override
  State<NiumaSplashScreen> createState() => _NiumaSplashScreenState();
}

class _NiumaSplashScreenState extends State<NiumaSplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: widget.next),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A08),
      body: SafeArea(
        child: SvgPicture.asset(
          'assets/splash/splash.svg',
          fit: BoxFit.contain,
          alignment: Alignment.center,
        ),
      ),
    );
  }
}
