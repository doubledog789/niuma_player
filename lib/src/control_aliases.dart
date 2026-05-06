// 10 个原子控件 `Niuma*` 前缀 typedef alias——避免业务方裸名冲突。
//
// 主 barrel `lib/niuma_player.dart` 用 `export ... show *` 形式 reexport 这
// 些 typedef，业务方 import 主包就能直接用 `NiumaPlayPauseButton` 等推荐名。
// 原裸名（PlayPauseButton 等）仍保留导出向后兼容，1.0 之前不删除。
//
// 这些 typedef 不能直接写在 niuma_player.dart 内——barrel 只 export 不
// 创建本地 binding，typedef 在同文件里看不到 export 出去的 class 名。
// 所以独立成文件 + 显式 import + 再 export。
library;

import 'presentation/controls/danmaku_button.dart';
import 'presentation/controls/fullscreen_button.dart';
import 'presentation/controls/pip_button.dart';
import 'presentation/controls/play_pause_button.dart';
import 'presentation/controls/quality_selector.dart';
import 'presentation/controls/scrub_bar.dart';
import 'presentation/controls/speed_selector.dart';
import 'presentation/controls/subtitle_button.dart';
import 'presentation/controls/time_display.dart';
import 'presentation/controls/volume_button.dart';

typedef NiumaPlayPauseButton = PlayPauseButton;
typedef NiumaScrubBar = ScrubBar;
typedef NiumaTimeDisplay = TimeDisplay;
typedef NiumaVolumeButton = VolumeButton;
typedef NiumaSpeedSelector = SpeedSelector;
typedef NiumaQualitySelector = QualitySelector;
typedef NiumaSubtitleButton = SubtitleButton;
typedef NiumaDanmakuButton = DanmakuButton;
typedef NiumaFullscreenButton = FullscreenButton;
typedef NiumaPipButton = PipButton;
