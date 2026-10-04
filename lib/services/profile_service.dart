import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

abstract class ProfileService {
  Future<UserProfile> loadForUser(String userId);

  Future<UserProfile> updateProfile({
    required String userId,
    required String name,
    required String? avatarKey,
  });
}

class SupabaseProfileService implements ProfileService {
  SupabaseProfileService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<UserProfile> loadForUser(String userId) async {
    final data = await _client
        .from('profiles')
        .select('id, name, avatar_key, avatar_url, created_at')
        .eq('id', userId)
        .single();

    return UserProfile.fromJson(data);
  }

  @override
  Future<UserProfile> updateProfile({
    required String userId,
    required String name,
    required String? avatarKey,
  }) async {
    final data = await _client
        .from('profiles')
        .update({'name': name, 'avatar_key': avatarKey})
        .eq('id', userId)
        .select('id, name, avatar_key, avatar_url, created_at')
        .single();

    return UserProfile.fromJson(data);
  }
}
