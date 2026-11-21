import 'dart:typed_data';

import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:flutter_test/flutter_test.dart';

// S-12: the content type must be derived from the bytes, never from the file
// name or the platform mime hint. These are the five types the storage
// buckets accept; anything else must be rejected before uploading.
void main() {
  Uint8List bytes(List<int> prefix, [int length = 64]) {
    final data = Uint8List(length);
    for (var i = 0; i < prefix.length && i < length; i++) {
      data[i] = prefix[i];
    }
    return data;
  }

  test('sniffs the five bucket-supported image types from magic bytes', () {
    expect(
      sniffImageContentType(bytes([0xFF, 0xD8, 0xFF, 0xE0])),
      'image/jpeg',
    );
    expect(
      sniffImageContentType(bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
      'image/png',
    );
    expect(
      sniffImageContentType(bytes([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x10, 0x00, 0x00, 0x00,
        0x57, 0x45, 0x42, 0x50, // WEBP
      ])),
      'image/webp',
    );

    for (final brand in ['heic', 'heix', 'mif1', 'msf1', 'heif']) {
      final data = bytes([
        0x00, 0x00, 0x00, 0x18,
        0x66, 0x74, 0x79, 0x70, // ftyp
      ], 32);
      for (var i = 0; i < brand.length; i++) {
        data[8 + i] = brand.codeUnitAt(i);
      }
      expect(
        sniffImageContentType(data),
        brand == 'heif' ? 'image/heif' : 'image/heic',
        reason: 'brand $brand',
      );
    }
  });

  test('rejects bytes that do not match any supported image type', () {
    // A .jpg name or an image/jpeg mime must not rescue arbitrary content.
    expect(
      () => sniffImageContentType(bytes([0x25, 0x50, 0x44, 0x46])),
      throwsFormatException,
    );
    expect(
      () => sniffImageContentType(bytes([0x00, 0x00, 0x00, 0x00])),
      throwsFormatException,
    );
    expect(
      () => sniffImageContentType(Uint8List(4)),
      throwsFormatException,
      reason: 'too short to hold any signature',
    );
  });
}
