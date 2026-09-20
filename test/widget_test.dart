import 'dart:async';

import 'package:family_stories_app/main.dart';
import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/models/question.dart';
import 'package:family_stories_app/screens/question_screen.dart';
import 'package:family_stories_app/services/audio_answer_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home muestra el contenido inicial', (tester) async {
    await tester.pumpWidget(const FamilyStoriesApp());

    expect(find.text('Family Stories'), findsOneWidget);
    expect(
      find.text('Conserva las historias de las personas que quieres.'),
      findsOneWidget,
    );
    expect(find.text('Añadir familiar'), findsOneWidget);
    expect(find.text('Tus familiares'), findsOneWidget);
    expect(
      find.text('Todavía no has añadido ningún familiar.'),
      findsOneWidget,
    );
  });

  testWidgets('permite añadir un familiar', (tester) async {
    await tester.pumpWidget(const FamilyStoriesApp());

    await tester.tap(find.text('Añadir familiar'));
    await tester.pumpAndSettle();

    expect(find.text('Nombre'), findsOneWidget);
    expect(find.text('Relación contigo'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'Ana');
    await tester.tap(find.text('Relación contigo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abuelo/a').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Abuelo/a'), findsOneWidget);
    expect(find.text('Todavía no has añadido ningún familiar.'), findsNothing);
  });

  testWidgets('valida los campos obligatorios', (tester) async {
    await tester.pumpWidget(const FamilyStoriesApp());

    await tester.tap(find.text('Añadir familiar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pump();

    expect(find.text('Introduce un nombre'), findsOneWidget);
    expect(find.text('Selecciona una relación'), findsOneWidget);
  });

  testWidgets('navega desde un familiar hasta el aviso de grabación', (
    tester,
  ) async {
    await tester.pumpWidget(const FamilyStoriesApp());

    await tester.tap(find.text('Añadir familiar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Ana');
    await tester.tap(find.text('Relación contigo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abuelo/a').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    expect(find.text('Conoce su historia'), findsOneWidget);
    expect(find.text('Responder una pregunta'), findsOneWidget);
    expect(find.text('Sus historias'), findsOneWidget);
    expect(
      find.text('Aquí aparecerán sus historias cuando guarde sus respuestas.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Responder una pregunta'));
    await tester.pumpAndSettle();

    expect(find.text('Escribir mi propia pregunta'), findsOneWidget);
    expect(find.text('O elige una categoría'), findsOneWidget);
    expect(find.text('Infancia'), findsOneWidget);
    expect(find.text('¿Cómo era tu casa cuando eras pequeño/a?'), findsNothing);

    await tester.tap(find.text('Infancia'));
    await tester.pumpAndSettle();

    expect(
      find.text('¿Cómo era tu casa cuando eras pequeño/a?'),
      findsOneWidget,
    );

    await tester.tap(find.text('¿Cómo era tu casa cuando eras pequeño/a?'));
    await tester.pumpAndSettle();

    expect(find.text('Para Ana'), findsOneWidget);
    expect(find.text('Grabar respuesta'), findsOneWidget);

    expect(find.text('Preparado para grabar'), findsOneWidget);
  });

  testWidgets('permite escribir y continuar con una pregunta personalizada', (
    tester,
  ) async {
    await tester.pumpWidget(const FamilyStoriesApp());

    await tester.tap(find.text('Añadir familiar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Ana');
    await tester.tap(find.text('Relación contigo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abuelo/a').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Responder una pregunta'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Escribir mi propia pregunta'));
    await tester.pumpAndSettle();

    expect(find.text('¿Qué quieres preguntarle a Ana?'), findsOneWidget);

    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.text('Escribe una pregunta'), findsOneWidget);

    await tester.enterText(
      find.byType(EditableText),
      '¿Cuál es tu receta favorita?',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('¿Cuál es tu receta favorita?'), findsOneWidget);
    expect(find.text('Para Ana'), findsOneWidget);
    expect(find.text('Grabar respuesta'), findsOneWidget);
  });

  testWidgets('recorre los estados de grabación y reproducción', (
    tester,
  ) async {
    final audioService = FakeAudioAnswerService();
    await tester.pumpWidget(
      MaterialApp(
        home: QuestionScreen(
          familyMember: const FamilyMember(
            name: 'Ana',
            relationship: 'Abuelo/a',
          ),
          question: const Question('¿Cuál es tu primer recuerdo?'),
          audioService: audioService,
        ),
      ),
    );

    await tester.tap(find.text('Grabar respuesta'));
    await tester.pump();

    expect(find.text('Grabando'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:01'), findsOneWidget);

    await tester.tap(find.text('Detener grabación'));
    await tester.pump();

    expect(find.text('Grabación terminada'), findsOneWidget);
    expect(find.text('Duración: 00:01'), findsOneWidget);
    expect(find.text('Reproducir'), findsOneWidget);

    await tester.tap(find.text('Reproducir'));
    await tester.pump();
    expect(find.text('Reproduciendo'), findsOneWidget);
    expect(find.text('Pausar'), findsOneWidget);

    await tester.tap(find.text('Pausar'));
    await tester.pump();
    expect(find.text('Reproducir'), findsOneWidget);

    await tester.tap(find.text('Volver a grabar'));
    await tester.pump();
    expect(find.text('Preparado para grabar'), findsOneWidget);
    expect(audioService.discardedPaths, ['/temporary/answer.m4a']);
  });

  testWidgets('informa cuando se rechaza el permiso del micrófono', (
    tester,
  ) async {
    final audioService = FakeAudioAnswerService(hasPermission: false);
    await tester.pumpWidget(
      MaterialApp(
        home: QuestionScreen(
          familyMember: const FamilyMember(
            name: 'Ana',
            relationship: 'Abuelo/a',
          ),
          question: const Question('¿Cuál es tu primer recuerdo?'),
          audioService: audioService,
        ),
      ),
    );

    await tester.tap(find.text('Grabar respuesta'));
    await tester.pump();

    expect(
      find.text('Se necesita acceso al micrófono para grabar respuestas.'),
      findsOneWidget,
    );
    expect(find.text('Preparado para grabar'), findsOneWidget);
  });
}

class FakeAudioAnswerService implements AudioAnswerService {
  FakeAudioAnswerService({this.hasPermission = true});

  final bool hasPermission;
  final List<String> discardedPaths = [];
  final StreamController<void> _playbackCompleteController =
      StreamController<void>.broadcast();

  @override
  Stream<void> get onPlaybackComplete => _playbackCompleteController.stream;

  @override
  Future<bool> requestPermission() async => hasPermission;

  @override
  Future<void> startRecording() async {}

  @override
  Future<String?> stopRecording() async => '/temporary/answer.m4a';

  @override
  Future<void> play(String path) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> discard(String path) async {
    discardedPaths.add(path);
  }

  @override
  Future<void> dispose() async {
    await _playbackCompleteController.close();
  }
}
