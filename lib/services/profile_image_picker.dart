import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class PickedProfileImage {
  const PickedProfileImage({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

abstract class ProfileImagePicker {
  Future<PickedProfileImage?> pickFromGallery();
}

class DeviceProfileImagePicker implements ProfileImagePicker {
  DeviceProfileImagePicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<PickedProfileImage?> pickFromGallery() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (image == null) {
      return null;
    }

    return PickedProfileImage(
      bytes: await image.readAsBytes(),
      contentType: image.mimeType ?? _contentTypeForName(image.name),
    );
  }

  String _contentTypeForName(String name) {
    final normalizedName = name.toLowerCase();
    if (normalizedName.endsWith('.png')) {
      return 'image/png';
    }
    if (normalizedName.endsWith('.webp')) {
      return 'image/webp';
    }
    if (normalizedName.endsWith('.heic') || normalizedName.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }
}
