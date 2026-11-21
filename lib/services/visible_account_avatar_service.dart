import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import 'auth_stream.dart';
import 'profile_avatar_image_cache.dart';

/// Display-only account metadata, separate from owned FamilyMember photos.
abstract class VisibleAccountAvatarService extends ChangeNotifier {
  UserProfile? cached(String accountId);
  Future<UserProfile?> load(String accountId);

  /// Loads every requested account in one go (C-5). The default
  /// implementation forwards to [load] per id so simple implementations and
  /// test fakes keep working; the Supabase implementation batches the ids
  /// into a bounded number of RPCs.
  Future<void> loadMany(List<String> accountIds) async {
    await Future.wait(accountIds.toSet().map((accountId) async {
      try {
        await load(accountId);
      } catch (_) {
        // Optional metadata: keep selecting from the available own photos.
      }
    }));
  }

  Future<void> warmCached(List<String> accountIds) async {}
}

class SupabaseVisibleAccountAvatarService extends VisibleAccountAvatarService
    implements ProfileAvatarImageSource {
  SupabaseVisibleAccountAvatarService({
    SupabaseClient? client,
    ProfileAvatarImageCache? avatarCache,
  }) : _client = client ?? Supabase.instance.client {
    _owner = _client.auth.currentUser?.id;
    _announcedOwner = _owner;
    avatarImages = avatarCache ?? ProfileAvatarImageCache.forClient(_client);
    avatarImages.addListener(_imagesChanged);
    // S-10: errors (e.g. refresh failures) must not become unhandled.
    // C-13: the handler only notifies when the visible account moved.
    _subscription = listenAuthSafely(
      _client.auth.onAuthStateChange,
      handleAuthState,
    );
  }

  static SupabaseVisibleAccountAvatarService? _shared;

  // Lazy initialization also lets local-only installations keep working.
  static VisibleAccountAvatarService? get shared {
    try {
      final client = Supabase.instance.client;
      if (_shared?._client != client) {
        _shared?.dispose();
        _shared = SupabaseVisibleAccountAvatarService(client: client);
      }
      return _shared;
    } catch (_) {
      return null;
    }
  }

  final SupabaseClient _client;
  @override
  late final ProfileAvatarImageCache avatarImages;
  void _imagesChanged() => notifyListeners();
  late final StreamSubscription<AuthState> _subscription;
  String? _owner;
  String? _announcedOwner;
  int _generation = 0;
  final _cache = <String, UserProfile?>{};
  final _pending = <String, Future<UserProfile?>>{};
  final _refreshes = <String, Future<UserProfile?>>{};
  final _validatedAt = <String, DateTime>{};
  final _retryAfter = <String, DateTime>{};

  @override
  Future<void> warmCached(List<String> accountIds) async {
    _syncAccount();
    if (_owner == null) return;
    await Future.wait(accountIds.toSet().map(avatarImages.readProfile));
  }

  void _clear() {
    _generation++;
    _cache.clear();
    _pending.clear();
    _refreshes.clear();
    _validatedAt.clear();
    _retryAfter.clear();
  }

  bool _syncAccount() {
    final owner = _client.auth.currentUser?.id;
    if (owner == _owner) return false;
    _owner = owner;
    _clear();
    return true;
  }

  /// C-13: every mounted avatar view reloads on each notifyListeners, so an
  /// auth event only notifies when the visible account actually moved (a
  /// getter may have synchronized it before the event arrived, hence the
  /// announced-owner guard) or when the session was signed out and cleared.
  @visibleForTesting
  void handleAuthState(AuthState event) {
    final changed = _syncAccount();
    final signedOut = event.event == AuthChangeEvent.signedOut;
    if (!changed && signedOut) _clear();
    final owner = _owner;
    if (!signedOut && owner == _announcedOwner) return;
    _announcedOwner = owner;
    notifyListeners();
  }

  @override
  UserProfile? cached(String accountId) {
    _syncAccount();
    return _owner == null
        ? null
        : avatarImages.cachedProfile(accountId) ?? _cache[accountId];
  }

  @override
  Future<UserProfile?> load(String accountId) {
    _syncAccount();
    if (_owner == null || accountId.isEmpty) return Future.value(null);
    if (_cache.containsKey(accountId)) {
      final now = DateTime.now();
      final validated = _validatedAt[accountId];
      if ((validated == null ||
              now.difference(validated) > const Duration(minutes: 5)) &&
          !now.isBefore(_retryAfter[accountId] ?? now)) {
        unawaited(
          _refresh(
            accountId,
            _owner!,
            _generation,
          ).catchError((Object _) => cached(accountId)),
        );
      }
      return Future.value(cached(accountId));
    }
    return _pending[accountId] ??= _load(accountId, _owner!, _generation);
  }

  // C-5: get_visible_account_avatars rejects more than 100 ids per call
  // (its cardinality guard silently returns no rows), so every batch stays
  // within that bound.
  static const _batchSize = 100;

  @override
  Future<void> loadMany(List<String> accountIds) async {
    _syncAccount();
    if (_owner == null) return;
    final owner = _owner!;
    final generation = _generation;
    final now = DateTime.now();
    final wanted = <String>[];
    final stale = <String>[];
    final inflight = <Future<void>>[];
    for (final id in accountIds.toSet()) {
      if (id.isEmpty) continue;
      // Join whatever is already running for this id instead of duplicating
      // it: a concurrent load() or a previous batch covers it.
      final busy = _pending[id] ?? _refreshes[id];
      if (busy != null) {
        inflight.add(busy.then<void>((_) {}, onError: (Object _) {}));
        continue;
      }
      if (_cache.containsKey(id)) {
        final validated = _validatedAt[id];
        if ((validated == null ||
                now.difference(validated) > const Duration(minutes: 5)) &&
            !now.isBefore(_retryAfter[id] ?? now)) {
          stale.add(id);
        }
      } else {
        wanted.add(id);
      }
    }
    try {
      final ids = [...wanted, ...stale];
      if (ids.isNotEmpty) {
        final batch = _batch(ids, wanted, owner, generation);
        // Publish this run so duplicate batches and single loads join it
        // instead of firing a second RPC for the same accounts.
        for (final id in ids) {
          _refreshes[id] = batch.then<UserProfile?>(
            (_) => _cache[id],
            onError: (Object _) => _cache[id],
          );
        }
        try {
          await batch;
        } finally {
          if (generation == _generation) {
            for (final id in ids) {
              _refreshes.remove(id);
            }
          }
        }
      }
    } finally {
      if (inflight.isNotEmpty) await Future.wait(inflight);
    }
  }

  /// One local pass and one bounded RPC per [_batchSize] ids: the local pass
  /// lets Home paint the portraits it already has while the RPC is on the
  /// wire, and the RPC fills the rest in a single round trip per chunk.
  Future<void> _batch(
    List<String> ids,
    List<String> cold,
    String owner,
    int generation,
  ) async {
    if (cold.isNotEmpty) {
      var disk = const <UserProfile?>[];
      try {
        disk = await Future.wait(cold.map(avatarImages.readProfile));
      } catch (_) {
        // Disk is only an accelerator; the RPC below still fills the cache.
      }
      _syncAccount();
      if (_owner != owner || generation != _generation) return;
      var warmed = false;
      for (var i = 0; i < cold.length && i < disk.length; i++) {
        final profile = disk[i];
        if (profile != null) {
          _cache[cold[i]] = profile;
          warmed = true;
        }
      }
      if (warmed) notifyListeners();
    }
    final chunks = <List<String>>[
      for (var start = 0; start < ids.length; start += _batchSize)
        ids.sublist(
          start,
          start + _batchSize < ids.length ? start + _batchSize : ids.length,
        ),
    ];
    // Future.wait (eagerError: false) attempts every chunk and rethrows the
    // first failure once they have all settled.
    await Future.wait(
      chunks.map((chunk) => _fetchMany(chunk, owner, generation)),
    );
  }

  Future<UserProfile?> _load(
    String accountId,
    String owner,
    int generation,
  ) async {
    try {
      final disk = await avatarImages.readProfile(accountId);
      _syncAccount();
      if (_owner != owner || generation != _generation) return null;
      if (disk != null) {
        _cache[accountId] = disk;
        unawaited(
          _refresh(accountId, owner, generation).catchError((Object _) => disk),
        );
        return disk;
      }
      return await _refresh(accountId, owner, generation);
    } finally {
      if (generation == _generation) _pending.remove(accountId);
    }
  }

  Future<UserProfile?> _refresh(
    String accountId,
    String owner,
    int generation,
  ) => _refreshes[accountId] ??= _fetch(accountId, owner, generation);

  Future<UserProfile?> _fetch(
    String accountId,
    String owner,
    int generation,
  ) async {
    try {
      await _fetchMany([accountId], owner, generation);
      if (_owner != owner || generation != _generation) return null;
      return _cache[accountId];
    } finally {
      if (generation == _generation) _refreshes.remove(accountId);
    }
  }

  /// One RPC for [accountIds] (at most [_batchSize] ids). Every id asked for
  /// ends up in the cache: an id the RPC does not return is not visible and is
  /// cached as null, exactly like the single-id [_fetch] did before C-5.
  Future<void> _fetchMany(
    List<String> accountIds,
    String owner,
    int generation,
  ) async {
    try {
      final rows = await _client.rpc(
        'get_visible_account_avatars',
        params: {
          'p_account_ids': accountIds,
        },
      );
      _syncAccount();
      if (_owner != owner || generation != _generation) return;
      final profiles = <String, UserProfile?>{
        for (final id in accountIds) id: null,
      };
      for (final row in rows as List) {
        final id = row['id'];
        if (id is String && profiles.containsKey(id)) {
          profiles[id] = UserProfile.fromJson(Map<String, dynamic>.from(row));
        }
      }
      final now = DateTime.now();
      for (final entry in profiles.entries) {
        final profile = entry.value;
        _cache[entry.key] = profile;
        _validatedAt[entry.key] = now;
        _retryAfter.remove(entry.key);
        if (profile == null) {
          await avatarImages.forgetProfile(entry.key);
        } else {
          await avatarImages.remember(profile);
        }
      }
    } on PostgrestException catch (error) {
      if ((error.code == '42501' || error.code == 'PGRST301') &&
          _owner == owner &&
          generation == _generation) {
        final now = DateTime.now();
        for (final id in accountIds) {
          _cache[id] = null;
          _validatedAt[id] = now;
          await avatarImages.forgetProfile(id);
        }
        return;
      }
      _setRetryAfter(accountIds);
      rethrow;
    } catch (_) {
      if (generation == _generation) _setRetryAfter(accountIds);
      rethrow;
    }
  }

  void _setRetryAfter(List<String> accountIds) {
    final at = DateTime.now().add(const Duration(seconds: 15));
    for (final id in accountIds) {
      _retryAfter[id] = at;
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    avatarImages.removeListener(_imagesChanged);
    _clear();
    super.dispose();
  }
}
