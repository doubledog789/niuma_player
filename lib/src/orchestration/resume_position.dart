import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/data_source.dart';

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

/// Controls what the player does automatically when a saved resume position is
/// found during [NiumaPlayerController.initialize].
enum ResumeBehaviour {
  /// Silently seek to the saved position on init without any user interaction.
  auto,

  /// Fire the `onResumePrompt` callback so the host app can show a dialog
  /// before deciding whether to seek.
  askUser,

  /// Load storage and make the saved position available, but do not auto-seek.
  /// The caller is responsible for deciding what to do with the position.
  disabled,
}

/// Function type that derives a stable storage key from a [NiumaDataSource].
///
/// The returned string is used as the key passed to [ResumeStorage.read],
/// [ResumeStorage.write], and [ResumeStorage.clear].
typedef ResumeKeyOf = String Function(NiumaDataSource source);

/// Default key derivation: `video:<uri>`.
///
/// Stable across launches as long as the URL is identical. Suitable for the
/// majority of on-demand streaming use cases where the URI does not change
/// between sessions.
String defaultResumeKey(NiumaDataSource source) => 'video:${source.uri}';

/// Configuration bag passed to the resume orchestrator.
///
/// Encapsulates every tunable aspect of resume-position behaviour: which
/// storage backend to use, how to derive storage keys, when to suppress
/// saving, and what to do when a saved position is found.
@immutable
class ResumePolicy {
  /// Creates a [ResumePolicy] with sensible production defaults.
  const ResumePolicy({
    this.storage = const SharedPreferencesResumeStorage(),
    this.keyOf = defaultResumeKey,
    this.behaviour = ResumeBehaviour.auto,
    this.minSavedPosition = const Duration(seconds: 30),
    this.discardIfNearEnd = const Duration(seconds: 30),
    this.savePeriod = const Duration(seconds: 5),
  });

  /// Pluggable storage layer used to read and write resume positions.
  ///
  /// Defaults to [SharedPreferencesResumeStorage]. Swap this out to use Hive,
  /// SQLite, a remote cloud store, or a [FakeResumeStorage] in tests.
  final ResumeStorage storage;

  /// Key derivation function applied to the current [NiumaDataSource].
  ///
  /// Defaults to [defaultResumeKey] which produces `video:<uri>`.
  final ResumeKeyOf keyOf;

  /// What to do when a saved resume position is found on initialize.
  ///
  /// Defaults to [ResumeBehaviour.auto].
  final ResumeBehaviour behaviour;

  /// Minimum playback position before saving is considered worthwhile.
  ///
  /// Prevents the "skip-to-5s on every fresh play" surprise: if the user
  /// abandons playback before reaching this threshold, no position is saved.
  /// Defaults to 30 seconds.
  final Duration minSavedPosition;

  /// Distance from the end of the video below which the saved position is
  /// discarded rather than offered on the next play.
  ///
  /// Avoids resuming at 2 s before the credits every time. Defaults to
  /// 30 seconds.
  final Duration discardIfNearEnd;

  /// How frequently the player writes the current position to [storage]
  /// during active playback.
  ///
  /// Lower values reduce data loss on crash but increase I/O. Defaults to
  /// every 5 seconds.
  final Duration savePeriod;
}

/// Sits between controller lifecycle events and [ResumeStorage].
///
/// Reads the saved position on init and seeks if [ResumeBehaviour.auto] is
/// configured. Writes the current position periodically during playback.
/// Clears the entry when playback reaches `phase = ended` so a finished
/// video doesn't offer a stale resume on the next play.
class ResumeOrchestrator {
  /// Creates a [ResumeOrchestrator].
  ///
  /// All four parameters are required; pass a [FakeResumeStorage] and stub
  /// lambdas in tests.
  ResumeOrchestrator({
    required this.policy,
    required this.source,
    required this.seekTo,
    required this.currentPosition,
  });

  /// Configuration bundle controlling storage backend, key derivation,
  /// behaviour on init, and save cadence.
  final ResumePolicy policy;

  /// The data source whose URI (via [ResumePolicy.keyOf]) drives storage
  /// lookups.
  final NiumaDataSource source;

  /// Callback that bridges to the controller; called with the position to
  /// seek to when a saved position is found and behaviour is
  /// [ResumeBehaviour.auto].
  final Future<void> Function(Duration) seekTo;

  /// Synchronous function that returns the current playback position.
  ///
  /// Called on every periodic tick and at [dispose] time.
  final Duration Function() currentPosition;

  Timer? _saveTimer;
  String get _key => policy.keyOf(source);

  /// Call after the controller's `initialize()` resolves.
  ///
  /// Reads the saved position from storage; if one exists and
  /// [ResumePolicy.behaviour] is [ResumeBehaviour.auto], seeks to it
  /// immediately. For [ResumeBehaviour.askUser] the caller is responsible for
  /// invoking its own prompt callback.
  Future<void> onInitialized() async {
    if (policy.behaviour == ResumeBehaviour.disabled) return;
    final saved = await policy.storage.read(_key);
    if (saved == null) return;
    if (policy.behaviour == ResumeBehaviour.auto) {
      await seekTo(saved);
    }
    // askUser: caller is responsible for invoking onResumePrompt.
  }

  /// Starts the periodic save timer.
  ///
  /// Typically called on the first `play` event. Cancels any existing timer
  /// first so the method is idempotent.
  void startPeriodicSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(policy.savePeriod, (_) => _saveIfApplicable());
  }

  Future<void> _saveIfApplicable() async {
    final pos = currentPosition();
    if (pos < policy.minSavedPosition) return;
    await policy.storage.write(_key, pos);
  }

  /// Call when `phase = ended` to clear the resume entry unconditionally.
  ///
  /// The user has finished the video, so there is no meaningful position to
  /// offer on the next play.
  Future<void> onEnded() async {
    await policy.storage.clear(_key);
  }

  /// Cancels the periodic save timer and performs a final save if the current
  /// position is at or beyond [ResumePolicy.minSavedPosition].
  Future<void> dispose() async {
    _saveTimer?.cancel();
    final pos = currentPosition();
    if (pos >= policy.minSavedPosition) {
      await policy.storage.write(_key, pos);
    }
  }
}
