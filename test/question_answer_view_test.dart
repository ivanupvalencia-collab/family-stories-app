import 'dart:io';
import 'dart:ui' as ui;

import 'package:family_stories_app/data/predefined_questions.dart';
import 'package:family_stories_app/data/question_answer_hints.dart';
import 'package:family_stories_app/screens/question_request_screen.dart';
import 'package:family_stories_app/widgets/question_answer_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

Widget _view(
  QuestionAnswerStage stage, {
  double scale = 1,
  VoidCallback? onStop,
  VoidCallback? onSend,
  bool busy = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: QuestionAnswerView(
      question: predefinedQuestionCategories.first.questions.first,
      stage: stage,
      onStart: () {},
      onStop: onStop ?? () {},
      onPlay: () {},
      onSend: onSend ?? () {},
      onCancel: () {},
      onRecordAgain: () {},
      onReturn: () {},
      duration: const Duration(seconds: 42),
      busy: busy,
      sentAt: DateTime(2026, 10, 4),
    ),
  ),
);

void main() {
  testWidgets(
    'sent confirmation returns true on system back without resubmitting or storing hints',
    (tester) async {
      final requests = fixtures.FakeQuestionRequestService();
      final audio = fixtures.FakeAudioAnswerService();
      final results = <bool?>[];
      final question = predefinedQuestionCategories.first.questions.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  results.add(
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => QuestionRequestScreen(
                          questionRequest: fixtures.testQuestionRequest(
                            id: 'request-1',
                            recipientId: 'recipient',
                            questionText: question.text,
                          ),
                          questionRequestService: requests,
                          audioService: audio,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Abrir pregunta recibida'),
              ),
            ),
          ),
        ),
      );
      await fixtures.openAndRecordQuestionRequest(tester, seconds: 2);
      expect(find.text(answerHintFor(question)), findsOneWidget);
      await tester.tap(find.text('Enviar respuesta'));
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(find.text('¡Gracias por compartir tu historia!'), findsOneWidget);
      expect(find.text(answerHintFor(question)), findsNothing);
      expect(requests.completedQuestionRequestIds, ['request-1']);
      expect(requests.completedDurations, [2]);
      expect(requests.completedAudioPaths.single, endsWith('.m4a'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(results, [true]);
      expect(requests.completedQuestionRequestIds, ['request-1']);
    },
  );

  for (final stage in QuestionAnswerStage.values) {
    for (final size in [
      const Size(390, 844),
      const Size(320, 640),
      const Size(640, 320),
    ]) {
      testWidgets('$stage remains scrollable at $size with large text', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_view(stage, scale: 2));
        await tester.pumpAndSettle();
        final footer = find.text(switch (stage) {
          QuestionAnswerStage.initial => 'Grabar respuesta',
          QuestionAnswerStage.recording => 'Cancelar',
          QuestionAnswerStage.review => 'Grabar de nuevo',
          QuestionAnswerStage.sent => 'Volver',
        });
        await tester.ensureVisible(footer);
        await tester.pumpAndSettle();
        expect(footer.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'review playback, retry, stop and send delegate to existing callbacks',
    (tester) async {
      var stops = 0;
      var sends = 0;
      await tester.pumpWidget(
        _view(QuestionAnswerStage.recording, onStop: () => stops++),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Detener grabación'));
      expect(stops, 1);
      await tester.pumpWidget(
        _view(QuestionAnswerStage.review, onSend: () => sends++),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reproducir'), findsOneWidget);
      await tester.tap(find.text('Enviar respuesta'));
      expect(sends, 1);
      await tester.pumpWidget(
        _view(QuestionAnswerStage.review, onSend: () => sends++, busy: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar respuesta'));
      expect(sends, 1);
    },
  );

  testWidgets(
    'remote recorder keeps playback/pause/resume and record-again behavior',
    (tester) async {
      final audio = fixtures.FakeAudioAnswerService();
      await tester.pumpWidget(
        fixtures.questionRequestAnswerApp(
          questionRequestService: fixtures.FakeQuestionRequestService(),
          audioService: audio,
        ),
      );
      await fixtures.openAndRecordQuestionRequest(tester, seconds: 2);
      expect(find.text(customQuestionAnswerHint), findsOneWidget);
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.pump();
      expect(audio.playedPaths, ['/temporary/answer.m4a']);
      await tester.tap(find.byTooltip('Pausar'));
      await tester.pump();
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.pump();
      await tester.tap(find.text('Grabar de nuevo'));
      await tester.pumpAndSettle();
      expect(audio.discardedPaths, ['/temporary/answer.m4a']);
      expect(find.text('Grabar respuesta'), findsOneWidget);
      expect(find.text(customQuestionAnswerHint), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cancel recording returns to the same request without sending', (
    tester,
  ) async {
    final audio = fixtures.FakeAudioAnswerService();
    final requests = fixtures.FakeQuestionRequestService();
    await tester.pumpWidget(
      fixtures.questionRequestAnswerApp(
        questionRequestService: requests,
        audioService: audio,
      ),
    );
    await tester.tap(find.text('Abrir pregunta recibida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grabar respuesta'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.pump();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Grabar respuesta'), findsOneWidget);
    expect(requests.uploadedObjectPaths, isEmpty);
    expect(requests.completedQuestionRequestIds, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('four visual previews with bundled fonts', (tester) async {
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
    for (final stage in QuestionAnswerStage.values) {
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: _view(stage)));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File('.dart_tool/question-answer-${stage.name}.png')
            .writeAsBytes(data.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }
  });
}
