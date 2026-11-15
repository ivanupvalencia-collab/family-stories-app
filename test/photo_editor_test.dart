import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:family_stories_app/screens/photo_editor_screen.dart';
import 'package:family_stories_app/services/photo_crop_service.dart';
import 'package:family_stories_app/services/photo_selection_service.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/design/aritoria_design.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'photo_editor_test_support.dart';
import 'widget_test.dart' as fixtures;

Future<PickedProfileImage> _landscape() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 200, 200),
    Paint()..color = const Color(0xFFFF0000),
  );
  canvas.drawRect(
    const Rect.fromLTWH(200, 0, 200, 200),
    Paint()..color = const Color(0xFF0000FF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 200);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return PickedProfileImage(
      bytes: png!.buffer.asUint8List(),
      contentType: 'image/png',
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class _ControlledCrop extends PhotoCropService {
  final gate = Completer<PickedProfileImage>();
  int calls = 0;
  @override
  Future<PickedProfileImage> crop(ui.Image image, Rect source) {
    calls++;
    return gate.future;
  }
}

class _DecodeFailure extends PhotoCropService {
  @override
  Future<ui.Image> decode(PickedProfileImage input) async =>
      throw StateError('decode');
}

void main() {
  testWidgets('transparent input is flattened on neutral cream before JPEG', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.transparent, BlendMode.src);
      final picture = recorder.endRecording();
      final transparent = await picture.toImage(16, 16);
      try {
        const service = PhotoCropService();
        final result = await service.crop(
          transparent,
          const Rect.fromLTWH(0, 0, 16, 16),
        );
        final output = await service.decode(result);
        try {
          final rgba = (await output.toByteData())!.buffer.asUint8List();
          final background = AritoriaColors.cream.toARGB32();
          expect(rgba[0], closeTo((background >> 16) & 255, 3));
          expect(rgba[1], closeTo((background >> 8) & 255, 3));
          expect(rgba[2], closeTo(background & 255, 3));
          expect(rgba[3], 255);
        } finally {
          output.dispose();
        }
      } finally {
        transparent.dispose();
        picture.dispose();
      }
    });
  });

  testWidgets('existing PNG and WebP and newly encoded JPEG remain readable', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const service = PhotoCropService();
      final legacyPng = await _landscape();
      final legacyWebp = PickedProfileImage(
        bytes: img.encodeWebP(img.Image(width: 8, height: 8)),
        contentType: 'image/webp',
      );
      for (final input in [legacyPng, legacyWebp]) {
        final decoded = await service.decode(input);
        try {
          final side = decoded.width < decoded.height
              ? decoded.width
              : decoded.height;
          final jpeg = await service.crop(
            decoded,
            Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
          );
          final output = await service.decode(jpeg);
          expect(output.width, side);
          expect(output.height, side);
          output.dispose();
        } finally {
          decoded.dispose();
        }
      }
    });
  });

  for (final size in [
    const Size(1200, 600),
    const Size(600, 1200),
    const Size(600, 600),
  ]) {
    test(
      'square crop always covers its viewport for $size, zoom and extreme pans',
      () {
        final crop = SquarePhotoCrop(size);
        for (final zoom in <double>[.1, 1, 1.5, 4, 12]) {
          for (final center in [
            Offset.zero,
            size.center(Offset.zero),
            const Offset(10000, -10000),
          ]) {
            crop.update(zoom, nextCenter: center);
            final source = crop.source;
            expect(source.width, closeTo(source.height, .001));
            expect(source.left, greaterThanOrEqualTo(0));
            expect(source.top, greaterThanOrEqualTo(0));
            expect(source.right, lessThanOrEqualTo(size.width));
            expect(source.bottom, lessThanOrEqualTo(size.height));
          }
        }
      },
    );
  }

  test('pinch retains its focal image point; moving the focal point pans', () {
    final crop = SquarePhotoCrop(const Size(800, 600));
    final anchor = crop.imagePoint(const Offset(100, 100), 200);
    crop.gesture(2, anchor, const Offset(100, 100), 200);
    expect(crop.imagePoint(const Offset(100, 100), 200), anchor);
    crop.gesture(2, anchor, const Offset(130, 90), 200);
    expect(crop.imagePoint(const Offset(130, 90), 200), anchor);
  });

  testWidgets(
    'export contains the selected real pixels, square and without a circular mask',
    (tester) async {
      await tester.runAsync(() async {
        const service = PhotoCropService();
        final input = await _landscape();
        final decoded = await service.decode(input);
        try {
          final crop = SquarePhotoCrop(const Size(400, 200))
            ..update(2, nextCenter: const Offset(300, 100));
          final result = await service.crop(decoded, crop.source);
          expect(result.contentType, 'image/jpeg');
          expect(result.bytes.take(3), [0xff, 0xd8, 0xff]);
          final output = await service.decode(result);
          try {
            expect(output.width, 100);
            expect(output.height, 100);
            final rgba = (await output.toByteData())!.buffer.asUint8List();
            for (final offset in [0, rgba.length - 4]) {
              expect(rgba[offset], closeTo(0, 3));
              expect(rgba[offset + 1], closeTo(0, 3));
              expect(rgba[offset + 2], closeTo(255, 3));
              expect(rgba[offset + 3], 255);
            }
          } finally {
            output.dispose();
          }
        } finally {
          decoded.dispose();
        }
      });
    },
  );

  testWidgets(
    'real export is bounded for large images without upscaling small ones',
    (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFF336633), BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(2000, 2000);
        try {
          const service = PhotoCropService();
          final result = await service.crop(
            image,
            const Rect.fromLTWH(0, 0, 2000, 2000),
          );
          expect(result.bytes.length, lessThan(10 * 1024 * 1024));
          final output = await service.decode(result);
          expect(output.width, PhotoCropService.maxOutputDimension);
          expect(output.height, output.width);
          output.dispose();
        } finally {
          image.dispose();
          picture.dispose();
        }
      });
    },
  );

  for (final size in [
    const Size(390, 844),
    const Size(320, 640),
    const Size(640, 320),
  ]) {
    testWidgets(
      'editor remains square and accessible at $size; zoom, pan and save',
      (tester) async {
        final input = (await tester.runAsync(_landscape))!;
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        PickedProfileImage? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    saved = await Navigator.of(context)
                        .push<PickedProfileImage>(
                          MaterialPageRoute(
                            builder: (_) => PhotoEditorScreen(image: input),
                          ),
                        );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await waitForPhotoEditor(tester);
        final area = find.byKey(const ValueKey('photo-crop-area'));
        final dimensions = tester.getSize(area);
        expect(dimensions.width, dimensions.height);
        expect(find.text('Aritoria'), findsNothing);
        await tester.ensureVisible(area);
        await tester.pumpAndSettle();
        final center = tester.getCenter(area);
        final a = await tester.startGesture(
          center - const Offset(25, 0),
          pointer: 1,
        );
        final b = await tester.startGesture(
          center + const Offset(25, 0),
          pointer: 2,
        );
        await tester.pump();
        await a.moveTo(center - const Offset(65, 0));
        await b.moveTo(center + const Offset(65, 0));
        await tester.pump();
        await a.up();
        await b.up();
        await tester.pump();
        expect(
          tester.widget<Slider>(find.byType(Slider)).value,
          greaterThan(1),
        );
        await tester.drag(area, const Offset(-30, 20));
        await tester.pump();
        tester.widget<Slider>(find.byType(Slider)).onChanged!(2);
        await tester.pump();
        expect(tester.widget<Slider>(find.byType(Slider)).value, 2);
        await confirmPhotoCrop(tester);
        expect(saved?.contentType, 'image/jpeg');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final back in [false, true]) {
    testWidgets(
      'selection cancellation leaves original untouched, back=$back',
      (tester) async {
        final picker = fixtures.FakeProfileImagePicker(
          result: fixtures.testPickedImage,
        );
        PickedProfileImage? result;
        var returned = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await PhotoSelectionService.pick(
                      context,
                      picker: picker,
                    );
                    returned = true;
                  },
                  child: const Text('Choose'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Choose'));
        await waitForPhotoEditor(tester);
        if (back) {
          await tester.pageBack();
        } else {
          await tester.ensureVisible(find.text('Cancelar'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cancelar'));
        }
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(returned, isTrue);
        expect(picker.pickCalls, 1);
      },
    );
  }

  testWidgets('invalid image disables saving and permits cancel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoEditorScreen(
          image: PickedProfileImage(
            bytes: Uint8List(0),
            contentType: 'image/jpeg',
          ),
          service: _DecodeFailure(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo abrir esta imagen'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('photo-crop-save')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'save failure permits retry; concurrent saves are deduplicated and back is blocked',
    (tester) async {
      final service = _ControlledCrop();
      await tester.pumpWidget(
        MaterialApp(
          home: PhotoEditorScreen(
            image: fixtures.testPickedImage,
            service: service,
          ),
        ),
      );
      await waitForPhotoEditor(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('photo-crop-save')));
      await tester.pumpAndSettle();
      final save = tester
          .widget<FilledButton>(find.byKey(const ValueKey('photo-crop-save')))
          .onPressed!;
      save();
      save();
      await tester.pump();
      expect(service.calls, 1);
      expect(
        tester.widget<PopScope>(find.byType(PopScope).first).canPop,
        isFalse,
      );
      service.gate.completeError(StateError('export'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudo ajustar la foto'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('photo-crop-save')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
