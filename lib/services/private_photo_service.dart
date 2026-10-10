import 'package:flutter/foundation.dart';

import 'profile_image_picker.dart';

abstract class PrivatePhotoService<T> {
  Uint8List? cachedPhoto(T item);
  Listenable? get cacheChanges => null;
  Future<Uint8List> load(T item);
  Future<T> save(T item, PickedProfileImage? image);
}

String privatePhotoExtension(PickedProfileImage image) {
  if (image.bytes.isEmpty || image.bytes.length > 10 * 1024 * 1024) {
    throw const FormatException(
      'Photo must contain bytes and be at most 10 MB.',
    );
  }
  return switch (image.contentType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    'image/heif' => 'heif',
    _ => throw const FormatException('Unsupported image type.'),
  };
}
