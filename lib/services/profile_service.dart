import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

abstract class ProfileService {
  Future<UserProfile> loadForUser(String userId);

  Future<UserProfile> updateName({
    required String userId,
    required String name,
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
  Future<UserProfile> updateName({
    required String userId,
    required String name,
  }) async {
    final data = await _client
        .from('profiles')
        .update({'name': name})
        .eq('id', userId)
        .select('id, name, avatar_key, avatar_url, created_at')
        .single();

    return UserProfile.fromJson(data);
  }
}
