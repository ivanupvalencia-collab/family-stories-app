import 'dart:async';

import 'package:family_stories_app/screens/question_request_screen.dart';
import 'package:family_stories_app/design/aritoria_design.dart';
import 'package:family_stories_app/widgets/question_answer_view.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

class _SeekingAudio extends fixtures.FakeAudioAnswerService {
  Completer<void>? gate;
  Object? error;
  int active = 0;
  int maxActive = 0;
  @override
  Future<void> seek(String path, double fraction) async {
    await super.seek(path, fraction);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await gate?.future;
      if (error != null) throw error!;
    } finally {
      active--;
    }
  }
}

class _StartAudio extends fixtures.FakeAudioAnswerService {
  bool allowed = true;
  bool failStart = false;
  int permissionCalls = 0;
  int startCalls = 0;
  Completer<bool>? permission;

  @override
  Future<bool> requestPermission() async {
    permissionCalls++;
    return permission == null ? allowed : await permission!.future;
  }

  @override
  Future<void> startRecording() async {
    startCalls++;
    if (failStart) throw StateError('recorder unavailable');
  }
}

Widget _app({
  String? senderName,
  required fixtures.FakeAudioAnswerService audio,
  ProfileImagePicker? picker,
  fixtures.FakeQuestionRequestService? requests,
}) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: FilledButton(
        onPressed: () => Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => QuestionRequestScreen(
              questionRequest: fixtures.testQuestionRequest(
                id: 'request-1',
                recipientId: 'recipient',
                questionText: 'Un recuerdo para compartir',
              ),
              senderName: senderName,
              questionRequestService:
                  requests ?? fixtures.FakeQuestionRequestService(),
              audioService: audio,
              imagePicker: picker,
            ),
          ),
        ),
        child: const Text('Abrir pregunta recibida'),
      ),
    ),
  ),
);

Finder get _wave => find.byKey(const ValueKey('answer-waveform'));

class _BarCanvas extends Fake implements Canvas {
  final colors = <Color>[];
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => colors.add(paint.color);
}

double _progress(WidgetTester tester) => tester
    .widget<QuestionAnswerView>(find.byType(QuestionAnswerView).last)
    .playbackProgress;

void main() {
  testWidgets('one tap handles denied permission and permits retry', (
    tester,
  ) async {
    final audio = _StartAudio()..allowed = false;
    await tester.pumpWidget(_app(audio: audio));
    await tester.tap(find.text('Abrir pregunta recibida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grabar respuesta'));
    await tester.pumpAndSettle();
    expect(audio.permissionCalls, 1);
    expect(audio.startCalls, 0);
    expect(
      find.text('Se necesita acceso al micrófono para grabar respuestas.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    audio.allowed = true;
    await tester.tap(find.text('Grabar respuesta'));
    await tester.pumpAndSettle();
    expect(audio.startCalls, 1);
    expect(find.byTooltip('Detener grabación'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('recorder startup error allows retry without navigating again', (
    tester,
  ) async {
    final audio = _StartAudio()..failStart = true;
    await tester.pumpWidget(_app(audio: audio));
    await tester.tap(find.text('Abrir pregunta recibida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grabar respuesta'));
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo iniciar la grabación. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    audio.failStart = false;
    await tester.tap(find.text('Grabar respuesta'));
    await tester.pumpAndSettle();
    expect(audio.startCalls, 2);
    expect(find.byTooltip('Detener grabación'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'double tap opens once; permission arriving after back cannot record',
    (tester) async {
      final audio = _StartAudio()..permission = Completer<bool>();
      await tester.pumpWidget(_app(audio: audio));
      await tester.tap(find.text('Abrir pregunta recibida'));
      await tester.pumpAndSettle();
      final start = tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Grabar respuesta'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed!;
      start();
      start();
      await tester.pumpAndSettle();
      expect(audio.permissionCalls, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      audio.permission!.complete(true);
      await tester.pumpAndSettle();
      expect(audio.startCalls, 0);
      expect(find.text('Grabar respuesta'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'wave follows native playback, seek, completion and rerecording',
    (tester) async {
      final audio = _SeekingAudio();
      await tester.pumpWidget(_app(audio: audio));
      await fixtures.openAndRecordQuestionRequest(tester);
      expect(_progress(tester), 0);
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.pumpAndSettle();
      audio.updatePlayback(
        const Duration(seconds: 5),
        const Duration(seconds: 20),
      );
      await tester.pumpAndSettle();
      expect(_progress(tester), .25);
      audio.updatePlayback(
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      );
      await tester.pumpAndSettle();
      expect(_progress(tester), .5);
      final painter = tester
          .widget<CustomPaint>(
            find.descendant(of: _wave, matching: find.byType(CustomPaint)),
          )
          .painter!;
      final canvas = _BarCanvas();
      painter.paint(canvas, const Size(240, 44));
      expect(
        canvas.colors.take(12).map((color) => color.toARGB32()),
        everyElement(AritoriaColors.olive.toARGB32()),
      );
      expect(
        canvas.colors.skip(12).map((color) => color.toARGB32()),
        everyElement(AritoriaColors.muted.withValues(alpha: .65).toARGB32()),
      );
      await tester.tap(find.byTooltip('Pausar'));
      await tester.pumpAndSettle();
      expect(_progress(tester), .5);
      final bounds = tester.getRect(_wave);
      await tester.tapAt(
        Offset(bounds.left + bounds.width * .75, bounds.center.dy),
      );
      await tester.pumpAndSettle();
      expect(_progress(tester), closeTo(.75, .01));
      expect(audio.resumeCalls, 0);
      audio.finishPlayback();
      await tester.pumpAndSettle();
      expect(_progress(tester), 1);
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.pumpAndSettle();
      expect(_progress(tester), 0);
      await tester.tap(find.text('Grabar de nuevo'));
      await tester.pumpAndSettle();
      expect(_progress(tester), 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'playback completion during seek still allows replay from the start',
    (tester) async {
      final audio = _SeekingAudio();
      await tester.pumpWidget(_app(audio: audio));
      await fixtures.openAndRecordQuestionRequest(tester);
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.pumpAndSettle();
      audio.gate = Completer<void>();
      await tester.tap(_wave);
      await tester.pump();
      audio.finishPlayback();
      await tester.pump();
      audio.gate!.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.pumpAndSettle();
      expect(audio.playedPaths, hasLength(2));
      expect(audio.resumeCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'existing sender name is shown on question, recording and review',
    (tester) async {
      final audio = _SeekingAudio();
      await tester.pumpWidget(
        _app(senderName: '  Iván Fernández  ', audio: audio),
      );
      await tester.tap(find.text('Abrir pregunta recibida'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enviada por Iván Fernández · Pendiente'),
        findsOneWidget,
      );
      await tester.tap(find.text('Grabar respuesta'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enviada por Iván Fernández · Pendiente'),
        findsOneWidget,
      );
      expect(
        find.text('Enviada por Iván Fernández · Pendiente'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Detener grabación'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enviada por Iván Fernández · Pendiente'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('missing or blank sender name preserves the existing fallback', (
    tester,
  ) async {
    for (final name in [null, '  ']) {
      await tester.pumpWidget(_app(senderName: name, audio: _SeekingAudio()));
      await tester.tap(find.text('Abrir pregunta recibida'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enviada por otro familiar · Pendiente'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'wave tap before playback seeks without autoplay; play resumes from selected position',
    (tester) async {
      final audio = _SeekingAudio();
      await tester.pumpWidget(_app(audio: audio));
      await fixtures.openAndRecordQuestionRequest(tester);
      final bounds = tester.getRect(_wave);
      await tester.tapAt(
        Offset(bounds.left + bounds.width * .25, bounds.center.dy),
      );
      await tester.pumpAndSettle();
      expect(audio.seeks.single.path, '/temporary/answer.m4a');
      expect(audio.seeks.single.fraction, closeTo(.25, .01));
      expect(audio.playedPaths, isEmpty);
      expect(audio.resumeCalls, 0);
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.pumpAndSettle();
      expect(audio.resumeCalls, 1);
      expect(audio.playedPaths, isEmpty);
      // Seeking while playing never pauses or restarts the audio.
      await tester.tapAt(
        Offset(bounds.left + bounds.width * .75, bounds.center.dy),
      );
      await tester.pumpAndSettle();
      expect(audio.seeks.last.fraction, closeTo(.75, .01));
      expect(audio.pauseCalls, 0);
      expect(find.byTooltip('Pausar'), findsOneWidget);
      await tester.tap(find.byTooltip('Pausar'));
      await tester.pumpAndSettle();
      await tester.tapAt(bounds.center);
      await tester.pumpAndSettle();
      expect(audio.resumeCalls, 1);
      expect(find.byTooltip('Reproducir'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'drag seeks are serialized, clamped and retain the final position',
    (tester) async {
      final audio = _SeekingAudio()..gate = Completer<void>();
      await tester.pumpWidget(_app(audio: audio));
      await fixtures.openAndRecordQuestionRequest(tester);
      final bounds = tester.getRect(_wave);
      final drag = await tester.startGesture(
        Offset(bounds.left + 4, bounds.center.dy),
      );
      await drag.moveBy(Offset(bounds.width * .4, 0));
      await tester.pump();
      await drag.moveTo(Offset(bounds.right + 30, bounds.center.dy));
      await tester.pump();
      await drag.up();
      expect(audio.seeks, hasLength(1));
      audio.gate!.complete();
      await tester.pumpAndSettle();
      expect(audio.maxActive, 1);
      expect(audio.seeks.last.fraction, 1);
      expect(audio.playedPaths, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed seek keeps recording available for retry and sending', (
    tester,
  ) async {
    final audio = _SeekingAudio()..error = StateError('native seek failed');
    final requests = fixtures.FakeQuestionRequestService();
    await tester.pumpWidget(_app(audio: audio, requests: requests));
    await fixtures.openAndRecordQuestionRequest(tester);
    await tester.tap(_wave);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No se pudo cambiar la posición del audio. Inténtalo de nuevo.',
      ),
      findsOneWidget,
    );
    expect(audio.discardedPaths, isEmpty);
    audio.error = null;
    await tester.tap(_wave);
    await tester.pumpAndSettle();
    expect(audio.seeks, hasLength(2));
    await tester.tap(find.text('Enviar respuesta'));
    await tester.pumpAndSettle();
    expect(requests.completedQuestionRequestIds, ['request-1']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'selected photo is previewed from bytes, can be changed and removed',
    (tester) async {
      final picker = fixtures.FakeProfileImagePicker(
        result: fixtures.testPickedImage,
      );
      final audio = _SeekingAudio();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(audio: audio, picker: picker));
      await fixtures.openAndRecordQuestionRequest(tester);
      expect(find.byKey(const ValueKey('answer-photo-preview')), findsNothing);
      await tester.ensureVisible(find.text('Añadir una foto (opcional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir una foto (opcional)'));
      await tester.pumpAndSettle();
      final preview = find.byKey(const ValueKey('answer-photo-preview'));
      expect(preview, findsOneWidget);
      final clip = tester.widget<ClipRRect>(preview);
      expect(clip.borderRadius, BorderRadius.circular(18));
      final image = tester.widget<Image>(
        find.descendant(of: preview, matching: find.byType(Image)),
      );
      final provider =
          (image.image as ResizeImage).imageProvider as MemoryImage;
      expect(provider.bytes, same(fixtures.testPickedImage.bytes));
      expect(image.fit, BoxFit.cover);
      await tester.ensureVisible(find.text('Cambiar foto seleccionada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cambiar foto seleccionada'));
      await tester.pumpAndSettle();
      expect(picker.pickCalls, 2);
      await tester.ensureVisible(find.text('Quitar foto seleccionada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar foto seleccionada'));
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
      expect(find.text('Añadir una foto (opcional)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
