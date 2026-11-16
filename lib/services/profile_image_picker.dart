import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

// S-12: the content type must come from the bytes themselves. Guessing it
// from the file name (or trusting a platform-provided mime without checking)
// lets a file declare one type and be stored as another. These are the five
// types the storage buckets accept (allowed_mime_types, migration 0007), so
// no legitimate photo can be rejected by this check.
String sniffImageContentType(Uint8List bytes) {
  if (bytes.length < 12) {
    throw const FormatException('Unsupported image type.');
  }

  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }

  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }

  // WebP: "RIFF" .... "WEBP"
  if (_ascii(bytes, 0, 4) == 'RIFF' && _ascii(bytes, 8, 4) == 'WEBP') {
    return 'image/webp';
  }

  // HEIC/HEIF: size + "ftyp" + brand.
  if (_ascii(bytes, 4, 4) == 'ftyp') {
    const heicBrands = {
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'mif1',
      'msf1',
      'heif',
    };
    if (heicBrands.contains(_ascii(bytes, 8, 4))) {
      return _ascii(bytes, 8, 4) == 'heif' ? 'image/heif' : 'image/heic';
    }
  }

  throw const FormatException('Unsupported image type.');
}

String _ascii(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes, offset, offset + length);

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

    // S-12: sniff the bytes; the name and the platform mime are only hints.
    final bytes = await image.readAsBytes();
    return PickedProfileImage(
      bytes: bytes,
      contentType: sniffImageContentType(bytes),
    );
  }
}
