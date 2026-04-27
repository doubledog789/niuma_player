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
