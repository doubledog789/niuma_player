import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'cast_pip_demo.dart';
import 'custom_controls_demo.dart';
import 'custom_feedback_ui_demo.dart';
import 'danmaku_demo.dart';
import 'gesture_lock_demo.dart';
import 'long_video_demo_page.dart';
import 'niuma_splash_screen.dart';
import 'rollback_failover_demo.dart';
import 'short_video_demo_page.dart';

/// Niuma 品牌色——design-tokens.json 中的 primary。
const _niumaOrange = Color(0xFFEF9F27);
const _niumaDark = Color(0xFF1A1410);
const _niumaLight = Color(0xFFFAC775);

void main() {
  // 投屏 DLNA + AirPlay 已由 SDK 内置自动 register（见
  // [NiumaCastRegistry.all]），无需 host app 手动调
  // `NiumaCastRegistry.register(...)`。如果业务自家有 Chromecast 等其它
  // 协议实现，仍可在此处显式 register 自家 service。
  runApp(const NiumaPlayerExampleApp());
}

class NiumaPlayerExampleApp extends StatelessWidget {
  const NiumaPlayerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'niuma_player example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _niumaDark,
        colorScheme: const ColorScheme.dark(
          primary: _niumaOrange,
          secondary: _niumaLight,
          surface: Color(0xFF252526),
          onPrimary: _niumaDark,
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _niumaDark,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: _niumaOrange,
          textColor: Colors.white,
        ),
      ),
      home: NiumaSplashScreen(next: (_) => const _Home()),
    );
  }
}

class _DemoEntry {
  const _DemoEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function(BuildContext) builder;
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final entries = <_DemoEntry>[
      _DemoEntry(
        title: '长视频 demo',
        subtitle: 'M16 mockup 全屏 / 线路切换 / Cast / PiP / 弹幕 hook',
        icon: Icons.movie_outlined,
        builder: (_) => const LongVideoDemoPage(),
      ),
      _DemoEntry(
        title: '短视频 demo',
        subtitle: '竖屏沉浸 / 自动播放 / 抖音风进度条',
        icon: Icons.short_text,
        builder: (_) => const ShortVideoDemoPage(),
      ),
      _DemoEntry(
        title: '失败回滚 + 自动 failover',
        subtitle: '坏线路自动跳到下一条 + 全失败 errorBuilder + 用户切坏线路 rollback',
        icon: Icons.swap_horiz,
        builder: (_) => const RollbackFailoverDemoPage(),
      ),
      _DemoEntry(
        title: '自定义反馈 UI',
        subtitle: 'loadingBuilder / errorBuilder / endedBuilder slot 演示',
        icon: Icons.brush_outlined,
        builder: (_) => const CustomFeedbackUiDemoPage(),
      ),
      _DemoEntry(
        title: '自定义控件层',
        subtitle: 'config / buttonOverrides / bottomActions / moreMenu slot 演示',
        icon: Icons.tune,
        builder: (_) => const CustomControlsDemoPage(),
      ),
      _DemoEntry(
        title: '弹幕集成',
        subtitle: 'NiumaDanmakuController / onDanmakuInputTap / 设置面板',
        icon: Icons.chat_bubble_outline,
        builder: (_) => const DanmakuDemoPage(),
      ),
      _DemoEntry(
        title: '投屏 + 画中画',
        subtitle: 'Cast / PiP setup + events 监听 + 平台差异',
        icon: Icons.cast,
        builder: (_) => const CastPipDemoPage(),
      ),
      _DemoEntry(
        title: '手势 + 锁屏',
        subtitle: 'disabledGestures / gestureHudBuilder / LockButton',
        icon: Icons.touch_app_outlined,
        builder: (_) => const GestureLockDemoPage(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('niuma_player')),
      body: ListView.separated(
        itemCount: entries.length + 1,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Colors.white12),
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  SvgPicture.asset(
                    'assets/tab_icons/tab_video_filled.svg',
                    width: 22,
                    height: 22,
                    colorFilter: const ColorFilter.mode(
                        _niumaLight, BlendMode.srcIn),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Demo 目录',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            );
          }
          final entry = entries[i - 1];
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _niumaOrange.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(entry.icon, color: _niumaOrange, size: 22),
            ),
            title: Text(entry.title),
            subtitle: Text(
              entry.subtitle,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white30),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: entry.builder),
            ),
          );
        },
      ),
    );
  }
}
