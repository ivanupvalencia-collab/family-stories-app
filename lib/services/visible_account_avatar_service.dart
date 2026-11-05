import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import 'profile_avatar_image_cache.dart';

/// Display-only account metadata, separate from owned FamilyMember photos.
abstract class VisibleAccountAvatarService extends ChangeNotifier {
  UserProfile? cached(String accountId);
  Future<UserProfile?> load(String accountId);
  Future<void> warmCached(List<String> accountIds) async {}
}

class SupabaseVisibleAccountAvatarService extends VisibleAccountAvatarService
    implements ProfileAvatarImageSource {
  SupabaseVisibleAccountAvatarService({
    SupabaseClient? client,
    ProfileAvatarImageCache? avatarCache,
  }) : _client = client ?? Supabase.instance.client {
    _owner = _client.auth.currentUser?.id;
    avatarImages = avatarCache ?? ProfileAvatarImageCache.forClient(_client);
    avatarImages.addListener(_imagesChanged);
    _subscription = _client.auth.onAuthStateChange.listen((event) {
      final changed = _syncAccount();
      if (!changed && event.event == AuthChangeEvent.signedOut) _clear();
      // A getter may already have synchronized the account before this event.
      // Every mounted view still needs to hide/reload its former avatar.
      notifyListeners();
    });
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
      final rows = await _client.rpc(
        'get_visible_account_avatars',
        params: {
          'p_account_ids': [accountId],
        },
      );
      _syncAccount();
      if (_owner != owner || generation != _generation) return null;
      UserProfile? profile;
      for (final row in rows as List) {
        if (row['id'] == accountId) {
          profile = UserProfile.fromJson(Map<String, dynamic>.from(row));
          break;
        }
      }
      _cache[accountId] = profile;
      _validatedAt[accountId] = DateTime.now();
      _retryAfter.remove(accountId);
      if (profile == null) {
        await avatarImages.forgetProfile(accountId);
      } else {
        await avatarImages.remember(profile);
      }
      return profile;
    } on PostgrestException catch (error) {
      if ((error.code == '42501' || error.code == 'PGRST301') &&
          _owner == owner &&
          generation == _generation) {
        _cache[accountId] = null;
        _validatedAt[accountId] = DateTime.now();
        await avatarImages.forgetProfile(accountId);
        return null;
      }
      _retryAfter[accountId] = DateTime.now().add(const Duration(seconds: 15));
      rethrow;
    } catch (_) {
      if (generation == _generation) {
        _retryAfter[accountId] = DateTime.now().add(
          const Duration(seconds: 15),
        );
      }
      rethrow;
    } finally {
      if (generation == _generation) _refreshes.remove(accountId);
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
