import 'package:shared_preferences/shared_preferences.dart';

/// Pluggable persistence contract for per-video resume positions.
///
/// Concrete implementations can wrap SharedPreferences, Hive, SQLite, or a
/// remote cloud store. The player core depends only on this interface so that
/// the host app can supply whichever backend suits its needs.
abstract class ResumeStorage {
  const ResumeStorage();

  /// Returns the saved playback position for [key], or `null` if none exists.
  Future<Duration?> read(String key);

  /// Persists [position] under [key], overwriting any previously saved value.
  Future<void> write(String key, Duration position);

  /// Removes the saved position for [key].
  ///
  /// Called by the player when playback reaches `phase = ended` so stale
  /// resume points are not offered on a future play of the same video.
  Future<void> clear(String key);
}

/// Default [ResumeStorage] implementation backed by [SharedPreferences].
///
/// Positions are stored as integer milliseconds under the key
/// `<prefix><key>`. This keeps storage compact and avoids floating-point
/// precision issues. The host app may override [prefix] to namespace entries
/// under an app-scoped key and avoid collisions with other libraries.
class SharedPreferencesResumeStorage extends ResumeStorage {
  /// Creates a [SharedPreferencesResumeStorage].
  ///
  /// [prefix] is prepended to every storage key to avoid collisions with
  /// other keys in SharedPreferences; defaults to `'niuma_player.resume.'`.
  const SharedPreferencesResumeStorage({this.prefix = 'niuma_player.resume.'});

  /// The string prepended to every storage key for collision avoidance.
  ///
  /// Defaults to `'niuma_player.resume.'`. Override this if the host app
  /// uses SharedPreferences for other data and wants a dedicated namespace.
  final String prefix;

  String _k(String key) => '$prefix$key';

  @override
  Future<Duration?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_k(key));
    if (ms == null) return null;
    return Duration(milliseconds: ms);
  }

  @override
  Future<void> write(String key, Duration position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_k(key), position.inMilliseconds);
  }

  @override
  Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_k(key));
  }
}
