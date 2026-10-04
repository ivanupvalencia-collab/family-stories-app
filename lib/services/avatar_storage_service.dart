import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_image_picker.dart';

abstract class AvatarStorageService {
  Future<String> uploadAvatar({
    required String userId,
    required PickedProfileImage image,
  });
}

class SupabaseAvatarStorageService implements AvatarStorageService {
  SupabaseAvatarStorageService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const bucketName = 'avatars';

  final SupabaseClient _client;

  @override
  Future<String> uploadAvatar({
    required String userId,
    required PickedProfileImage image,
  }) async {
    final objectPath = '$userId/profile';
    final bucket = _client.storage.from(bucketName);

    await bucket.uploadBinary(
      objectPath,
      image.bytes,
      fileOptions: FileOptions(
        upsert: true,
        contentType: image.contentType,
        cacheControl: '3600',
      ),
    );

    final publicUrl = bucket.getPublicUrl(objectPath);
    final revision = DateTime.now().millisecondsSinceEpoch;
    return '$publicUrl?v=$revision';
  }
}
