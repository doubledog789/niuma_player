# niuma_player · IJK 编译脚本

编译后的 ijkplayer `.aar` 落在 `android/localmaven/` 下（一个 vendored 的 maven repo 布局），Gradle build 通过坐标 `tv.danmaku.ijk:ijkplayer:<version>@aar` 解析。

> 为什么不用 `android/libs/*.aar`：AGP 8+ 禁止 library module 直接依赖本地 `.aar` 文件（`hasLocalAarDeps` 校验），所以改走 maven repo。

**这个 aar 已经提交进 git + 随 pub 包发布**（它是自定义编译的，公网无下载源）。消费方拉包即可构建，**无需运行本目录任何脚本**。下面的步骤只在你要升级/重编 IJK 时才需要。

## 升级 IJK / FFmpeg（从源码自编）

从源码自编，默认要 NDK r26b（`26.1.10909125`）：

```bash
export NDK_HOME=/Users/you/Library/Android/sdk/ndk/26.1.10909125  # 可选，脚本有默认
./build.sh
```

步骤：clone ijkplayer @ `k0.8.9-beta-260402150035` → 覆盖 `module-lite-hevc.sh` → `init-android.sh` → `compile-ijk.sh` → 产物改成 maven 布局拷到 `../localmaven/`。

## 版本事实源

所有版本号统一写在 `VERSIONS.lock`。任何升级都先改那里。

> 若提示 `permission denied`，给脚本加执行位：`chmod +x build.sh`。或直接 `bash build.sh`。
