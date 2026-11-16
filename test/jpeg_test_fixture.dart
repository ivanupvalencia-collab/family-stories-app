import 'dart:typed_data';

import 'package:family_stories_app/services/photo_jpeg_encoder.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';

Future<PickedProfileImage> jpegTestPhoto() async => PickedProfileImage(
  bytes: await const DartPhotoJpegEncoder().encodeRgba(
    Uint8List.fromList(List.generate(16, (i) => [60, 100, 70, 255][i % 4])),
    width: 2,
    height: 2,
  ),
  contentType: 'image/jpeg',
);
