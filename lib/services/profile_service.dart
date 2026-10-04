import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

abstract class ProfileService {
  UserProfile? cachedForUser(String userId);

  Future<UserProfile> loadForUser(String userId, {bool forceRefresh = false});

  Future<UserProfile> updateProfile({
    required String userId,
    required String name,
    required String? avatarKey,
    required String? avatarUrl,
  });

  void clearCache();
}

class SupabaseProfileService implements ProfileService {
  SupabaseProfileService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final Map<String, UserProfile> _cache = {};
  final Map<String, Future<UserProfile>> _pendingLoads = {};
  final Map<String, int> _pendingLoadTokens = {};
  int _cacheGeneration = 0;
  int _nextLoadToken = 0;

  @override
  UserProfile? cachedForUser(String userId) => _cache[userId];

  @override
  Future<UserProfile> loadForUser(String userId, {bool forceRefresh = false}) {
    final cachedProfile = _cache[userId];
    if (!forceRefresh && cachedProfile != null) {
      return Future.value(cachedProfile);
    }

    final pendingLoad = _pendingLoads[userId];
    if (pendingLoad != null) {
      return pendingLoad;
    }

    final token = ++_nextLoadToken;
    _pendingLoadTokens[userId] = token;
    final load = _fetchAndReleaseProfile(userId, token);
    _pendingLoads[userId] = load;
    return load;
  }

  Future<UserProfile> _fetchAndReleaseProfile(String userId, int token) async {
    try {
      final generation = _cacheGeneration;
      final data = await _client
          .from('profiles')
          .select('id, name, avatar_key, avatar_url, created_at')
          .eq('id', userId)
          .single();

      final profile = UserProfile.fromJson(data);
      if (generation == _cacheGeneration) {
        _cache[userId] = profile;
      }
      return profile;
    } finally {
      if (_pendingLoadTokens[userId] == token) {
        _pendingLoadTokens.remove(userId);
        _pendingLoads.remove(userId);
      }
    }
  }

  @override
  Future<UserProfile> updateProfile({
    required String userId,
    required String name,
    required String? avatarKey,
    required String? avatarUrl,
  }) async {
    final generation = _cacheGeneration;
    final data = await _client
        .from('profiles')
        .update({
          'name': name,
          'avatar_key': avatarKey,
          'avatar_url': avatarUrl,
        })
        .eq('id', userId)
        .select('id, name, avatar_key, avatar_url, created_at')
        .single();

    final profile = UserProfile.fromJson(data);
    if (generation == _cacheGeneration) {
      _cache[userId] = profile;
    }
    return profile;
  }

  @override
  void clearCache() {
    _cacheGeneration++;
    _cache.clear();
    _pendingLoads.clear();
    _pendingLoadTokens.clear();
  }
}
