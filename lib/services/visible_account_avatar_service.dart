import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

/// Display-only account metadata, separate from owned FamilyMember photos.
abstract class VisibleAccountAvatarService extends ChangeNotifier {
  UserProfile? cached(String accountId);
  Future<UserProfile?> load(String accountId);
}

class SupabaseVisibleAccountAvatarService extends VisibleAccountAvatarService {
  SupabaseVisibleAccountAvatarService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client {
    _owner = _client.auth.currentUser?.id;
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
      return _shared ??= SupabaseVisibleAccountAvatarService(
        client: Supabase.instance.client,
      );
    } catch (_) {
      return null;
    }
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _subscription;
  String? _owner;
  int _generation = 0;
  final _cache = <String, UserProfile?>{};
  final _pending = <String, Future<UserProfile?>>{};

  void _clear() {
    _generation++;
    _cache.clear();
    _pending.clear();
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
    return _owner == null ? null : _cache[accountId];
  }

  @override
  Future<UserProfile?> load(String accountId) {
    _syncAccount();
    if (_owner == null || accountId.isEmpty) return Future.value(null);
    if (_cache.containsKey(accountId)) return Future.value(_cache[accountId]);
    return _pending[accountId] ??= _fetch(accountId, _owner!, _generation);
  }

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
      return profile;
    } finally {
      if (generation == _generation) _pending.remove(accountId);
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _clear();
    super.dispose();
  }
}
