import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Keeps the codec dependency out of the editor and its crop geometry.
abstract class PhotoJpegEncoder {
  const PhotoJpegEncoder();

  Future<Uint8List> encodeRgba(
    Uint8List rgba, {
    required int width,
    required int height,
  });
}

class DartPhotoJpegEncoder extends PhotoJpegEncoder {
  const DartPhotoJpegEncoder();
  static const quality = 90;

  @override
  Future<Uint8List> encodeRgba(
    Uint8List rgba, {
    required int width,
    required int height,
  }) {
    if (width < 1 || height < 1 || rgba.length != width * height * 4) {
      throw const FormatException('Invalid photo pixel buffer.');
    }
    return compute(_encode, (
      rgba: rgba,
      width: width,
      height: height,
    ), debugLabel: 'Aritoria photo JPEG');
  }
}

Uint8List _encode(({Uint8List rgba, int width, int height}) input) {
  final image = img.Image.fromBytes(
    width: input.width,
    height: input.height,
    bytes: input.rgba.buffer,
    bytesOffset: input.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: DartPhotoJpegEncoder.quality);
}
