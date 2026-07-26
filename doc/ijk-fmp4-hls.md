# IJK 支持 fMP4 分片的 HLS —— 根因与修复

> 2026-07-26。测试机 PHK110 / Android 16 / arm64。
> 测试源：`api.remnthdf.com` 的 HEVC fMP4 HLS（854×480 731 片、720×1280 351 片各一条）。

## 症状

`forceIjkOnAndroid: true` 播 fMP4 分片的 HLS（playlist 带 `#EXT-X-MAP`）时：

- 进度条不动
- 拖动进度条后一直转圈，看着像卡死

**但画面其实一直在正常播放**（截图逐帧对比 md5 全不同）。

## 根因

`ijkmedia/ijkplayer/ff_ffplay.c` 的 `ffp_get_current_position_l()`：

```c
int64_t start_time = is->ic->start_time;
if (start_time > 0 && start_time != AV_NOPTS_VALUE)
    start_diff = fftime_to_milliseconds(start_time);
...
pos = pos_clock * 1000;              // master clock
if (pos < 0 || pos < start_diff)
    return 0;                        // ← 位置恒 0 出在这
int64_t adjust_pos = pos - start_diff;
```

fMP4 的 `ic->start_time` 取自分片的 `baseMediaDecodeTime`，是个很大的值；
而 master clock 并不含这个偏移，于是 `pos < start_diff` 恒成立，位置**永远返回 0**。

位置恒 0 又连锁引发第二个问题：`PlayerSession` 的 buffering 出口
（`notifyBufferingEnd`）依赖 IJK 发 `MEDIA_INFO_BUFFERING_END`，而 fMP4 上
seek 后这个事件不发；`notifyVideoRenderingStart` 的兜底只在**首帧**触发一次，
救不了后续 → phase 永久停在 buffering → spinner 不灭。

TS 封装不受影响（`start_time` 正常，位置是绝对值）。

## 修复（两处）

### 1. native：`ff_ffplay.c` 位置计算

```c
if (pos < 0)
    return 0;
// fMP4：start_diff 不适用，直接用时钟值
if (pos < start_diff)
    return (long) pos;
int64_t adjust_pos = pos - start_diff;
```

### 2. Kotlin：`PlayerSession` 心跳里给 buffering 加出口兜底

位置在推进 = 帧在流，这是比任何事件都硬的证据：

```kotlin
if (phase == PHASE_BUFFERING && userWantsPlay && positionMs > prev) {
    phase = PHASE_PLAYING
}
```

真卡顿时位置不动，仍正确停在 buffering。

## 验证结果

| | 修复前 | 修复后 |
|---|---|---|
| fMP4 播放 | 画面正常，位置恒 0 | 位置正确推进 |
| fMP4 seek | 永久卡 buffering | 落点准，约 1 秒出 buffering，位置续上 |
| 连续 seek | 卡死 | 正常 |
| PlatformView / Texture | — | 两条路都正常 |
| TS 流 | 正常 | 正常（无回归） |

## 产物

自编 `ijkplayer-0.8.8-ff8.1-pos-20260726.aar`（**目前仅 arm64-v8a**）：

- ShikinChen/ijkplayer-android `ijk0.8.8--ff7.1` + 上述 native 补丁
- FFmpeg **8.1**（上游 `n8.1` + ijk 补丁移植，libavformat 62.12.100）
- OpenSSL 3.2 静态链接

## 编译链踩坑（README 之外的新增）

1. **NDK 21.4.7075529 可能是空壳**（只有 `source.properties`）——
   `sdkmanager --install "ndk;21.4.7075529"` 重装，约 3.6G
2. **NDK 23+ 编不了**：砍掉了 GNU binutils，`make_standalone_toolchain.py`
   缺 `as` 直接失败。必须 NDK 21
3. binutils libc++abi crash：按 README 把 `ar/ranlib/nm/strip` 软链到 `llvm-*`
4. `compile-openssl.sh` / `compile-ffmpeg.sh` **必须在 `android/contrib/` 下跑**
   （脚本内部用相对路径 `tools/...`）
5. `ANDROID_NDK` 必须给**绝对路径**（`~` 不展开 → 读不到 source.properties →
   报 "You need the NDKr10e or later"）
6. `init-android.sh` 只拉 `extra/ffmpeg`，per-arch 的
   `android/contrib/ffmpeg-<abi>` 要手工 `pull-repo-ref.sh` + `git fetch` 分支

### JNI 补丁必须打

`patches/0001-fix-jni-onload-j4a-loadall-sdl-jvm.patch` **一定要应用**。
旧的 `0.8.8-ff7.1.1-20260602` aar 漏了它，表现为
`No Java virtual machine has been registered` → 事件回不到 Java →
fMP4 完全不出帧。这是个静默的坑，重编时务必确认
`SDL_JNI_SetJvm` 在 `libijksdl.so` 里被导出。

## FFmpeg 7.1 → 8.1 移植清单

ijk 相对上游只有 **455 行 / 7 个文件**（`ijkutils.c`、`application.c/h`、
`async.c` 的一处 `const` 去除、3 个 Makefile）。移植到 8.1 需要额外处理：

| 问题 | 处理 |
|---|---|
| `--disable-postproc` 被删 | 从 module.sh 移除 |
| `libavcodec/avfft.h` 被删 | 加 `ijk_avfft_shim.h`（RDFT 仅用于音频波形可视化，播放路径不走） |
| `FF_PROFILE_*` → `AV_PROFILE_*` | 全库 sed |
| `AVFrame.pkt_pos` 被删 | 置 `-1`（仅用于 byte-seek 记账） |
| `av_stream_get_side_data` 被删 | 改 `av_packet_side_data_get(codecpar->coded_side_data, ...)` |
| `av_format_inject_global_side_data` 被删 | 删除调用（8.x 恒注入） |
| `tls_openssl.c` 新增 DTLS 引用 `ff_udp_*` | module.sh 加 `--enable-protocol=udp` |
| `libavutil/thread.h` 未安装 | ijk 补丁本来就要把它加进 libavutil HEADERS，别漏 |

## 待办

- [ ] 编 `armeabi-v7a`（目前只有 arm64-v8a）
- [ ] `VERSIONS.lock` 更新到 ff8.1 + 新 commit SHA
- [ ] 编译链脚本（`android/scripts/compile/`）随 aar 一起回归本仓
- [ ] 更多真机机型 / 弱网场景验证
- [ ] 评估是否值得自维护 vs 回 GSY 官方产物（后者 fMP4 seek 仍坏）

## 方法论教训

**不要用 `position` 判断「有没有在播」。** 本次排查前期把
`getCurrentPosition()` 恒 0 误判成「解码不出帧」，方向偏了好几轮。
判断渲染是否正常应当用**截图逐帧对比**，那是唯一不受状态上报影响的证据。

## 追加：起播黑屏 2.4~5.7 秒（2026-07-27）

### 症状
IJK 起播时黑屏很久才出画面，体验很差。

### 根因
ShikinChen fork 在 `ffp_check_buffering_l()` 里加了这段：

```c
if (ffp->show_first_frame && buf_percent > 0) {
    ffp_seek_to_l(ffp, 0);          // 意图：逼出首帧
}
```

而 `show_first_frame` **只有首帧真正显示出来才会清零**
（`ff_ffplay.c:954`，在 `SDL_VoutDisplayYUVOverlay` 成功之后）。
缓冲期间输出是暂停的、首帧显示不出来 → 标志一直为 1 →
**每轮缓冲检查都 seek 回 0 → 分片反复重拉 → 缓冲永远填不满**。自锁。

实测起播要拉 23~26 个分片（约 140 秒内容）才结束缓冲。

> niuma 0.4.0 的 CHANGELOG 早就点过这个「fork 私货」，当时靠换 GSY 产物绕开；
> 自编回来后它又出现了。

### 修复
移除 `ffp_check_buffering_l()` 里那次 `ffp_seek_to_l(ffp, 0)`。
niuma 走 `start-on-prepared=0` + Dart 侧立即 `play()`，不需要这个 hack。

### 效果

| 指标 | 修复前 | 修复后 |
|---|---|---|
| start → 首次位置推进 | 数秒 | 0.40 / 1.03 / 1.22s |
| 起播期间拉分片 | 23~26 片 | 1~2 片 |
| prepare → 开始播 | 7~9s | 2.0 / 3.0 / 3.0s |

### 顺带排除的两条
- `analyzeduration` / `probesize`：`find_stream_info` 实测只花 85ms，不是瓶颈
- 缓冲水位（`first/next/last-high-water-mark-ms`）：压低后无可测量改善，方差比效果大，已撤回

### 剩下的固定成本
prepare 里约 1.2s 是**下载 playlist**——那个 m3u8 有 351 行签名 URL、177KB、
走明文 http，服务端首字节就 0.55s。这段跟播放器无关，ExoPlayer 同样要付
（实测 Exo 的 ready 反而更慢：3.2s vs IJK 2.1s）。要再快只能从服务端下手。

### 产物
`ijkplayer-0.8.8-ff8.1-fastopen-20260727.aar`（arm64-v8a）
