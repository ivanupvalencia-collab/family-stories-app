import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

abstract class ProfileService {
  Future<UserProfile> loadForUser(String userId);
}

class SupabaseProfileService implements ProfileService {
  SupabaseProfileService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<UserProfile> loadForUser(String userId) async {
    if (kDebugMode) {
      debugPrint('[FamilyStoriesProfile][load] userId=$userId');
    }

    try {
      final data = await _client
          .from('profiles')
          .select('id, name, avatar_key, avatar_url, created_at')
          .eq('id', userId)
          .single();

      return UserProfile.fromJson(data);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        final prefix = '[FamilyStoriesProfile][load]';
        debugPrint('$prefix exceptionType=${error.runtimeType}');
        for (final line in error.toString().split('\n')) {
          debugPrint('$prefix message=$line');
        }
        for (final line in stackTrace.toString().trimRight().split('\n')) {
          debugPrint('$prefix stackTrace=$line');
        }
      }
      rethrow;
    }
  }
}
