# niuma_player · IJK 编译脚本

编译后的 ijkplayer `.aar` 落在 `android/localmaven/` 下（一个 vendored 的 maven repo 布局），Gradle build 通过坐标 `tv.danmaku.ijk:ijkplayer:<version>@aar` 解析。

> 为什么不用 `android/libs/*.aar`：AGP 8+ 禁止 library module 直接依赖本地 `.aar` 文件（`hasLocalAarDeps` 校验），所以改走 maven repo。

**这个 aar 已经提交进 git + 随 pub 包发布**（它是自定义编译的，公网无下载源）。消费方拉包即可构建，**无需运行本目录任何脚本**。下面的步骤只在你要升级/重编 IJK 时才需要。

## 当前产物：FFmpeg 7.1.1 slim（2026-06-01 起）

现网 aar `ijkplayer-0.8.8-ff7.1.1-20260601` 基于 **ShikinChen/ijkplayer-android（`ijk0.8.8--ff7.1`）+ ShikinChen/FFmpeg（`ff7.1--ijk0.8.8`）**，最小化 VOD mp4/HLS 配置，仅 `arm64-v8a + armeabi-v7a`。FFmpeg 模块见 `modules/module-niuma-ff7-slim.sh`，全部版本/commit SHA 见 `VERSIONS.lock`。

> ⚠️ **`build.sh` / `Dockerfile` 里旧的 debugly + bilibili FFmpeg 4.0 流程已废弃**——debugly 的 ijk JNI 硬锁 FFmpeg 4.0，切不到 ff7。重编 ff7 走下面手工流程（暂未脚本化进 build.sh）。

### 重编 ff7.1 slim aar（手工流程）

双 NDK：21 用 autotools 编 FFmpeg + OpenSSL，27 用 cmake 编 JNI `.so`。先 `brew install nasm cmake`。

1. clone `ShikinChen/ijkplayer-android` 到 `.build/`，把 `init-android.sh` 的 `IJK_FFMPEG_COMMIT` 改成 `ff7.1--ijk0.8.8`。
2. 清掉指向父仓库的 stale `ijkmedia/ijkyuv`、`ijkmedia/ijksoundtouch`，跑 `./init-android.sh` 拉 FFmpeg/libyuv/soundtouch，再 `./init-android-openssl.sh` 拉 openssl-3.2。
3. 把 `modules/module-niuma-ff7-slim.sh` 拷成 `config/module.sh`。
4. 新 macOS 上 NDK21 standalone toolchain 的 x86_64 binutils（ar/ranlib）会 libc++abi crash：把每个 `build/toolchain-<abi>/bin` 下的 `ar/ranlib/nm/strip`（裸名 + 带前缀）软链到 `llvm-*`，`ld` 软链到 `<prefix>-ld.gold`（lld 当 `ld` 用会进 Darwin 模式）。
5. armv7a 的 OpenSSL：把 `android/contrib/tools/do-compile-openssl.sh` 里 armv7a 的 `FF_PLATFORM_CFG_FLAGS="android-arm"` 改成 `linux-armv4`（`android-arm` 会触发对 `arm-linux-androideabi-gcc` 的 NDK prebuilt 探测，standalone toolchain 下必失败）。
6. `ANDROID_NDK=<ndk21> ./android/contrib/compile-ffmpeg.sh arm64`（先编 openssl 后编 ffmpeg），同样跑 armv7a。
7. cmake（NDK27）出 `.so`：`cmake <ijk_root> -DCMAKE_TOOLCHAIN_FILE=<ndk27>/build/cmake/android.toolchain.cmake -DANDROID_ABI=<abi> -DANDROID_PLATFORM=android-21 -DANDROID_STL=c++_shared -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_SHARED_LINKER_FLAGS=-Wl,-Bsymbolic`，再 `cmake --build`。
8. `llvm-strip --strip-unneeded` 所有 `libijk*.so`，连同 NDK27 的 `libc++_shared.so` 一起打进 aar 的 `jni/<abi>/`（**5 个 ijk .so 必须齐**：player/sdl/soundtouch/yuv/j4a，否则 dlopen 缺依赖；libc++_shared 因 `c++_shared` STL 必带），复用旧 aar 的 `classes.jar`/`AndroidManifest.xml`/metadata。

### 旧流程（debugly ff4.0，已废弃，仅留档）

```bash
export NDK_HOME=/Users/you/Library/Android/sdk/ndk/26.1.10909125
./build.sh
```

clone ijkplayer @ `k0.8.9-beta-260402150035` → 覆盖 `module-lite-hevc.sh` → `init-android.sh` → `compile-ijk.sh` → 产物改成 maven 布局拷到 `../localmaven/`。

## 版本事实源

所有版本号统一写在 `VERSIONS.lock`。任何升级都先改那里。

> 若提示 `permission denied`，给脚本加执行位：`chmod +x build.sh`。或直接 `bash build.sh`。
