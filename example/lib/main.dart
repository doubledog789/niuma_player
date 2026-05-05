import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player_airplay/niuma_player_airplay.dart';
import 'package:niuma_player_dlna/niuma_player_dlna.dart';

import 'long_video_demo_page.dart';
import 'niuma_splash_screen.dart';
import 'short_video_demo_page.dart';

/// Niuma 品牌色——design-tokens.json 中的 primary。
const _niumaOrange = Color(0xFFEF9F27);
const _niumaDark = Color(0xFF1A1410);
const _niumaLight = Color(0xFFFAC775);

void main() {
  // M15: 注册投屏 services
  NiumaCastRegistry.register(DlnaCastService());
  NiumaCastRegistry.register(AirPlayCastService());
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

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('niuma_player')),
      body: ListView(
        children: [
          ListTile(
            leading: SvgPicture.asset(
              'assets/tab_icons/tab_video_filled.svg',
              width: 28,
              height: 28,
              colorFilter:
                  const ColorFilter.mode(_niumaOrange, BlendMode.srcIn),
            ),
            title: const Text('长视频 demo'),
            subtitle: const Text('M16 mockup 全屏 / 线路切换 / Cast / PiP / 弹幕 hook'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LongVideoDemoPage()),
            ),
          ),
          ListTile(
            leading: SvgPicture.asset(
              'assets/tab_icons/tab_star_filled.svg',
              width: 28,
              height: 28,
              colorFilter:
                  const ColorFilter.mode(_niumaOrange, BlendMode.srcIn),
            ),
            title: const Text('短视频 demo'),
            subtitle: const Text('竖屏沉浸 / 自动播放'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ShortVideoDemoPage()),
            ),
          ),
        ],
      ),
    );
  }
}
