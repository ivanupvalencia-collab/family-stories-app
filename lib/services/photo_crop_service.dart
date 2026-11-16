import 'dart:math' as math;
import 'dart:ui' as ui;

import '../design/aritoria_design.dart';
import 'photo_jpeg_encoder.dart';
import 'profile_image_picker.dart';

/// Square source coordinates shared by preview, gestures and exported pixels.
class SquarePhotoCrop {
  SquarePhotoCrop(this.imageSize) : center = imageSize.center(ui.Offset.zero);

  final ui.Size imageSize;
  ui.Offset center;
  double zoom = 1;
  static const maxZoom = 4.0;

  double get side => math.min(imageSize.width, imageSize.height) / zoom;
  ui.Rect get source =>
      ui.Rect.fromCenter(center: center, width: side, height: side);

  void update(double nextZoom, {ui.Offset? nextCenter}) {
    zoom = nextZoom.clamp(1, maxZoom);
    final requested = nextCenter ?? center;
    final half = side / 2;
    center = ui.Offset(
      requested.dx.clamp(half, imageSize.width - half),
      requested.dy.clamp(half, imageSize.height - half),
    );
  }

  ui.Offset imagePoint(ui.Offset localPoint, double viewportSide) =>
      source.topLeft + localPoint * (side / viewportSide);

  void gesture(
    double nextZoom,
    ui.Offset anchor,
    ui.Offset focalPoint,
    double viewportSide,
  ) {
    final nextSide =
        math.min(imageSize.width, imageSize.height) /
        nextZoom.clamp(1, maxZoom);
    update(
      nextZoom,
      nextCenter:
          anchor -
          (focalPoint / viewportSide - const ui.Offset(.5, .5)) * nextSide,
    );
  }
}

/// All pixel decoding/export lives here; no picker, storage or backend access.
class PhotoCropService {
  const PhotoCropService({this.encoder = const DartPhotoJpegEncoder()});
  final PhotoJpegEncoder encoder;
  static const maxDecodedDimension = 4096;
  static const maxOutputDimension = 1536;

  Future<ui.Image> decode(PickedProfileImage input) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(input.bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) => width >= height
          ? ui.TargetImageSize(width: math.min(width, maxDecodedDimension))
          : ui.TargetImageSize(height: math.min(height, maxDecodedDimension)),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<PickedProfileImage> crop(ui.Image image, ui.Rect source) async {
    final dimension = math
        .min(source.width.floor(), maxOutputDimension)
        .clamp(1, maxOutputDimension);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // Match the neutral canvas already visible behind transparent input pixels.
    canvas.drawColor(AritoriaColors.cream, ui.BlendMode.src);
    canvas.drawImageRect(
      image,
      source,
      ui.Rect.fromLTWH(0, 0, dimension.toDouble(), dimension.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    ui.Image? output;
    try {
      output = await picture.toImage(dimension, dimension);
      final data = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('Could not encode cropped photo.');
      return PickedProfileImage(
        bytes: await encoder.encodeRgba(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          width: dimension,
          height: dimension,
        ),
        contentType: 'image/jpeg',
      );
    } finally {
      output?.dispose();
      picture.dispose();
    }
  }
}
