# Consumer ProGuard rules for niuma_player.
# Automatically applied to any app that depends on this plugin — callers don't
# need to copy-paste these.
#
# Why every rule matters: IJKPlayer is JNI-heavy. The native `libijkplayer.so`
# resolves Java classes/methods by *exact name* via FindClass / GetMethodID at
# runtime. R8 will happily rename or strip those classes because nothing in
# Java bytecode references them — the reference only exists in native code,
# which R8 can't see. Result: SIGSEGV inside libijkplayer.so on the first
# prepare/play, with no Dart-visible error.

# Keep every IJK class, member, and native method signature intact.
-keep class tv.danmaku.ijk.media.player.** { *; }
-keep interface tv.danmaku.ijk.media.player.** { *; }
-dontwarn tv.danmaku.ijk.media.player.**

# Listener callback classes — IjkMediaPlayer registers them by reflection name.
-keepclassmembers class * implements tv.danmaku.ijk.media.player.IMediaPlayer$* {
    *;
}

# Native method bodies — R8 cannot see these are called from C.
-keepclasseswithmembernames class * {
    native <methods>;
}
