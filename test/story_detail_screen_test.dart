import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/screens/story_screen.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/services/story_photo_service.dart';
import 'package:family_stories_app/widgets/question_text.dart';
import 'package:family_stories_app/widgets/story_photo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

class _Photos extends StoryPhotoService {
  @override
  Future<bool> canEdit(FamilyStory story) async => true;
  @override
  Uint8List? cachedPhoto(FamilyStory story) => fixtures.testPickedImage.bytes;
  @override
  Future<Uint8List> load(FamilyStory story) async =>
      fixtures.testPickedImage.bytes;
  @override
  Future<FamilyStory> save(
    FamilyStory story,
    PickedProfileImage? image,
  ) async => story;
}

class _Audio extends fixtures.FakeAudioAnswerService {
  bool failSeek = false;
  Completer<void>? gate;
  @override
  Future<void> seek(String path, double fraction) async {
    await super.seek(path, fraction);
    await gate?.future;
    if (failSeek) throw StateError('seek failed');
  }
}

FamilyStory _story(bool photo) => FamilyStory(
  id: 'story',
  familyMemberId: 'member',
  question: '¿Cómo era tu casa cuando eras pequeño/a?',
  audioPath: '/local/answer.m4a',
  duration: const Duration(seconds: 20),
  createdAt: DateTime(2026, 10, 17),
  photoPath: photo ? 'private/photo.png' : null,
);

Widget _app(
  _Audio audio, {
  bool photo = false,
  fixtures.FakeFamilyStoryService? remote,
  double scale = 1,
}) => MaterialApp(
  builder: (_, child) => MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: StoryScreen(
    story: _story(photo),
    authorName: 'Claudia',
    recipientName: 'Iván',
    audioService: audio,
    waveformService: fixtures.UnavailableStoryWaveforms(),
    photoService: _Photos(),
    remoteStoryService: remote,
  ),
);

Slider _slider(WidgetTester tester) =>
    tester.widget<Slider>(find.byKey(const ValueKey('story-seek')));

void main() {
  testWidgets('story visual previews with bundled fonts', (tester) async {
    if (!const bool.fromEnvironment('ARITORIA_PREVIEW')) return;
    for (final (family, path) in [
      ('Fraunces', 'assets/fonts/Fraunces.ttf'),
      ('Nunito Sans', 'assets/fonts/NunitoSans.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final photo in [false, true]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: _app(_Audio(), photo: photo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File('.dart_tool/story-detail-photo-$photo.png')
            .writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'completion during seek preserves replay and prevents duplicate seeks',
    (tester) async {
      final audio = _Audio();
      await tester.pumpWidget(_app(audio));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reproducir historia'));
      await tester.pumpAndSettle();
      audio.gate = Completer<void>();
      final seek = _slider(tester).onChangeEnd!;
      seek(.7);
      seek(.2);
      await tester.pump();
      expect(audio.seeks, hasLength(1));
      expect(_slider(tester).onChanged, isNull);
      audio.finishPlayback();
      await tester.pump();
      audio.gate!.complete();
      await tester.pumpAndSettle();
      expect(_slider(tester).value, 1);
      await tester.tap(find.byTooltip('Reproducir historia'));
      await tester.pumpAndSettle();
      expect(audio.playedPaths, hasLength(2));
      expect(audio.resumeCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final photo in [false, true]) {
    for (final size in [
      const Size(390, 844),
      const Size(320, 640),
      const Size(640, 360),
    ]) {
      testWidgets(
        'story editorial layout photo=$photo size=$size supports large text',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final audio = _Audio();
          await tester.pumpWidget(_app(audio, photo: photo, scale: 1.6));
          await tester.pumpAndSettle();
          expect(find.text('Historia de Claudia'), findsOneWidget);
          expect(
            tester
                .widget<QuestionText>(find.byType(QuestionText))
                .style
                ?.fontFamily,
            'Fraunces',
          );
          await tester.scrollUntilVisible(
            find.text('17 de octubre de 2026 · Para Iván'),
            150,
          );
          expect(
            find.text('17 de octubre de 2026 · Para Iván'),
            findsOneWidget,
          );
          if (photo) {
            await tester.scrollUntilVisible(find.byType(StoryPhotoView), 200);
            expect(find.byType(StoryPhotoView), findsOneWidget);
          } else {
            expect(find.byType(StoryPhotoView), findsNothing);
          }
          await tester.scrollUntilVisible(find.text('Transcripción'), 200);
          expect(find.text('PRÓXIMAMENTE'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'native progress, pause, seek and replay drive the actual player',
    (tester) async {
      final audio = _Audio();
      await tester.pumpWidget(_app(audio));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reproducir historia'));
      await tester.pumpAndSettle();
      audio.updatePlayback(
        const Duration(seconds: 5),
        const Duration(seconds: 20),
      );
      await tester.pumpAndSettle();
      expect(_slider(tester).value, .25);
      expect(find.text('00:05'), findsOneWidget);
      _slider(tester).onChanged!(.75);
      await tester.pump();
      expect(_slider(tester).value, .75);
      _slider(tester).onChangeEnd!(.75);
      await tester.pumpAndSettle();
      expect(audio.seeks.single, (path: '/local/answer.m4a', fraction: .75));
      expect(audio.pauseCalls, 0);
      await tester.tap(find.byTooltip('Pausar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reproducir historia'));
      await tester.pumpAndSettle();
      expect(audio.resumeCalls, 1);
      audio.finishPlayback();
      await tester.pumpAndSettle();
      expect(_slider(tester).value, 1);
      await tester.tap(find.byTooltip('Reproducir historia'));
      await tester.pumpAndSettle();
      expect(_slider(tester).value, 0);
      expect(audio.playedPaths, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'remote seek before playback downloads privately, never autoplays and can retry',
    (tester) async {
      final audio = _Audio()..failSeek = true;
      final remote = fixtures.FakeFamilyStoryService();
      await tester.pumpWidget(_app(audio, remote: remote));
      await tester.pumpAndSettle();
      _slider(tester).onChanged!(.5);
      _slider(tester).onChangeEnd!(.5);
      await tester.pumpAndSettle();
      expect(_slider(tester).value, 0);
      expect(
        find.text(
          'No se pudo cambiar la posición del audio. Inténtalo de nuevo.',
        ),
        findsOneWidget,
      );
      audio.failSeek = false;
      _slider(tester).onChanged!(.5);
      _slider(tester).onChangeEnd!(.5);
      await tester.pumpAndSettle();
      expect(audio.playedPaths, isEmpty);
      expect(audio.seeks.last.path, remote.resolvedAudioPath);
      expect(_slider(tester).value, .5);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reproducir historia'));
      await tester.pumpAndSettle();
      expect(audio.resumeCalls, 1);
      expect(audio.playedPaths, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
