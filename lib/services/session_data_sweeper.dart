import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'remote_family_member_cache.dart';
import 'remote_family_photo_disk_cache.dart';

/// S-6: the single place that removes every session-scoped remnant when a
/// session ends (logout, expired refresh token, remote revocation).
///
/// The services already drop their in-memory state on `signedOut`; what
/// survives them lives in the app-private directory and in SharedPreferences:
///
///   * `remote_family_photos_v1/<backend>/<owner>/`  family portraits
///   * `remote_story_photos_v1/<backend>/<owner>/`   story/answer photos
///   * `remote_family_members_v1:<backend>:<owner>`  names + relationships
///   * `tmp/remote_story_audio/`                     downloaded audio
///
/// Avatars (`syncSession`) and waveforms (`_RemoteBinding`) already purge
/// themselves and are not touched here. Guest/offline data (`family_members`,
/// `family_stories`, `support/story_photos/…`) never belongs to a session and
/// is never touched either.
///
/// It shares the very same disk instances as the services
/// (`RemoteFamilyPhotoDiskCache.forClient`), so the purge queues behind any
/// write still committing instead of racing it, and everything is best effort:
/// a failing purge must never break the sign-out itself.
class SessionDataSweeper {
  SessionDataSweeper({
    required SupabaseClient client,
    RemoteFamilyMemberCache? memberCache,
    RemoteFamilyPhotoDiskCache? photosCache,
    RemoteFamilyPhotoDiskCache? storyPhotosCache,
    Future<Directory> Function()? temporaryDirectoryProvider,
  }) : _client = client,
       _memberCache = memberCache ?? RemoteFamilyMemberCache.forClient(client),
       _photos =
           photosCache ??
           RemoteFamilyPhotoDiskCache.forClient(client),
       _storyPhotos =
           storyPhotosCache ??
           RemoteFamilyPhotoDiskCache.forClient(
             client,
             directoryName: 'remote_story_photos_v1',
             allowForeignUploader: true,
           ),
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory,
       _owner = client.auth.currentUser?.id {
    _subscription = client.auth.onAuthStateChange.listen((state) {
      final next = state.session?.user.id;
      final previous = _owner;
      _owner = next;
      // Purge only the session that ended. An account switch (signedIn with a
      // different id) keeps the previous owner's own files for its next
      // sign-in, exactly as before.
      if (state.event == AuthChangeEvent.signedOut && previous != null) {
        unawaited(purge(previous));
      }
    });
  }

  final SupabaseClient _client;
  final RemoteFamilyMemberCache _memberCache;
  final RemoteFamilyPhotoDiskCache _photos;
  final RemoteFamilyPhotoDiskCache _storyPhotos;
  final Future<Directory> Function() _temporaryDirectoryProvider;
  StreamSubscription<AuthState>? _subscription;
  String? _owner;

  /// Removes every session-scoped remnant of [owner]. Idempotent, best effort
  /// and ordered behind pending writes of the shared queues.
  Future<void> purge(String owner) async {
    final backend = _client.storage.url;
    try {
      await _photos.clearOwner(backend, owner);
    } catch (_) {
      // Cleanup is best effort and must not affect authentication.
    }
    try {
      await _storyPhotos.clearOwner(backend, owner);
    } catch (_) {
      // Cleanup is best effort and must not affect authentication.
    }
    try {
      await _memberCache.purge(backend, owner);
    } catch (_) {
      // Cleanup is best effort and must not affect authentication.
    }
    try {
      await _purgeDownloadedAudio();
    } catch (_) {
      // Cleanup is best effort and must not affect authentication.
    }
  }

  // The whole directory: it also holds audio downloaded by sessions that are
  // no longer in `_audioCache` (the app was killed between downloads).
  Future<void> _purgeDownloadedAudio() async {
    final temporary = await _temporaryDirectoryProvider();
    final directory = Directory(
      '${temporary.path}${Platform.pathSeparator}remote_story_audio',
    );
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
