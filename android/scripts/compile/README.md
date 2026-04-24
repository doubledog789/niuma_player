# niuma_player · IJK 编译脚本

本目录负责把 ijkplayer `.aar` 落到 `android/localmaven/` 下（一个 vendored 的 maven repo 布局），Gradle build 通过坐标 `tv.danmaku.ijk:ijkplayer:<version>@aar` 解析。

> 为什么不用 `android/libs/*.aar`：AGP 8+ 禁止 library module 直接依赖本地 `.aar` 文件（`hasLocalAarDeps` 校验），所以改走 maven repo。

两条路径：

## 日常开发（v0.1）

直接拉 debugly 官方 Release 的 prebuilt：

```bash
./download-prebuilt.sh
```

产物落在 `../localmaven/tv/danmaku/ijk/ijkplayer/<VERSION>/ijkplayer-<VERSION>.aar`，sha256 必须匹配 `VERSIONS.lock` 里的 `PREBUILT_SHA256`。脚本同时写出配套的 `.pom`，保证 maven 布局合法。

## 升级 IJK / FFmpeg（v0.2）

从源码自编，默认要 NDK r26b（`26.1.10909125`）：

```bash
export NDK_HOME=/Users/you/Library/Android/sdk/ndk/26.1.10909125  # 可选，脚本有默认
./build.sh
```

步骤：clone ijkplayer @ `k0.8.9-beta-260402150035` → 覆盖 `module-lite-hevc.sh` → `init-android.sh` → `compile-ijk.sh` → 产物改成 maven 布局拷到 `../localmaven/`。

## 版本事实源

所有版本号统一写在 `VERSIONS.lock`。任何升级都先改那里。

> 第一次 clone 仓库后若提示 `permission denied`，给脚本加执行位：
> `chmod +x download-prebuilt.sh build.sh`。或直接 `bash download-prebuilt.sh`。
