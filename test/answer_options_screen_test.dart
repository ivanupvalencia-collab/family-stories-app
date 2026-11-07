import 'dart:typed_data';

import 'package:family_stories_app/design/aritoria_design.dart';
import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/models/question.dart';
import 'package:family_stories_app/screens/answer_options_screen.dart';
import 'package:family_stories_app/screens/question_screen.dart';
import 'package:family_stories_app/screens/story_screen.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/services/story_photo_service.dart';
import 'package:family_stories_app/services/story_waveform_service.dart';
import 'package:family_stories_app/widgets/question_answer_view.dart';
import 'package:family_stories_app/widgets/story_waveform_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

const _member = FamilyMember(
  id: 'mavi',
  name: 'Mavi',
  relationship: 'Abuelo/a',
);
const _question = Question(
  '¿A qué jugabas cuando eras niño/a?',
  id: 'childhood-games',
);

class _Audio extends fixtures.FakeAudioAnswerService {
  bool allowed = true;
  int permissions = 0, starts = 0;
  @override
  Future<bool> requestPermission() async {
    permissions++;
    return allowed;
  }

  @override
  Future<void> startRecording() async {
    starts++;
  }
}

class _Storage extends fixtures.MemoryFamilyStoryStorage {
  bool fail = false;
  @override
  Future<FamilyStory> saveRecording({
    required String familyMemberId,
    required String question,
    required String temporaryAudioPath,
    required Duration duration,
  }) {
    if (fail) throw StateError('save failed');
    return super.saveRecording(
      familyMemberId: familyMemberId,
      question: question,
      temporaryAudioPath: temporaryAudioPath,
      duration: duration,
    );
  }
}

class _Photos extends StoryPhotoService {
  _Photos(this.storage);
  final _Storage storage;
  @override
  Future<bool> canEdit(FamilyStory story) async => true;
  @override
  Future<Uint8List> load(FamilyStory story) async =>
      fixtures.testPickedImage.bytes;
  @override
  Future<FamilyStory> save(FamilyStory story, PickedProfileImage? image) async {
    final updated = story.withPhotoPath(
      image == null ? null : 'story_photos/${story.id}/photo.png',
    );
    storage.stories[storage.stories.indexWhere((s) => s.id == story.id)] =
        updated;
    return updated;
  }
}

class _Waveforms extends StoryWaveformService {
  @override
  Future<List<double>> extract(String localAudioPath) async => [
    .2,
    .8,
    .4,
    1,
    .3,
  ];
  @override
  Future<void> dispose() async {}
}

Future<void> _open(
  WidgetTester tester, {
  required _Audio audio,
  required _Storage storage,
  fixtures.FakeQuestionRequestService? requests,
  Size size = const Size(390, 844),
  double scale = 1,
  ValueChanged<bool?>? onReturn,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => AnswerOptionsScreen(
                    familyMember: _member,
                    question: _question,
                    familyStoryStorage: storage,
                    authService: fixtures.FakeAuthService(),
                    invitationService: fixtures.FakeInvitationService(),
                    invitationShareService:
                        fixtures.FakeInvitationShareService(),
                    familyMemberService: fixtures.FakeFamilyMemberService(),
                    questionRequestService:
                        requests ?? fixtures.FakeQuestionRequestService(),
                    isRemoteFamilyMember: false,
                    audioService: audio,
                    photoService: _Photos(storage),
                    imagePicker: fixtures.FakeProfileImagePicker(
                      result: fixtures.testPickedImage,
                    ),
                  ),
                ),
              );
              onReturn?.call(result);
            },
            child: const Text('Abrir opciones'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir opciones'));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(320, 640),
    const Size(640, 320),
  ]) {
    testWidgets(
      'opciones y pregunta siguen accesibles con texto ampliado en $size',
      (tester) async {
        await _open(
          tester,
          audio: _Audio(),
          storage: _Storage(),
          size: size,
          scale: 1.6,
        );
        expect(find.text('Elige cómo responder'), findsOneWidget);
        final title = tester.widget<Text>(find.text('Elige cómo responder'));
        expect(title.textAlign, TextAlign.start);
        expect(title.style!.fontFamily, 'Lora');
        expect(title.style!.fontWeight, AritoriaType.brand.fontWeight);
        await tester.scrollUntilVisible(
          find.text('Graba la respuesta en este dispositivo'),
          160,
        );
        expect(
          find.text('Graba la respuesta en este dispositivo'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(find.text('Enviar a Mavi'), 160);
        expect(
          find.text('Para que responda desde su dispositivo'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Enviar a Mavi'));
        await tester.tap(find.text('Enviar a Mavi'));
        await tester.pumpAndSettle();
        expect(find.text('Necesitas iniciar sesión'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'una pulsación abre el grabador compartido y guarda audio, foto y navegación locales sin enviar',
    (tester) async {
      final audio = _Audio();
      final storage = _Storage();
      final requests = fixtures.FakeQuestionRequestService();
      bool? returned;
      await _open(
        tester,
        audio: audio,
        storage: storage,
        requests: requests,
        onReturn: (value) => returned = value,
      );
      final option = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('Responder ahora'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      option.onTap!();
      option.onTap!();
      await tester.pumpAndSettle();
      expect(audio.permissions, 0);
      expect(audio.starts, 0);
      expect(find.byType(QuestionScreen), findsOneWidget);
      expect(find.byType(QuestionAnswerView), findsOneWidget);
      expect(find.text('Para Mavi'), findsOneWidget);
      expect(find.textContaining('Pendiente'), findsNothing);
      await tester.tap(find.text('Grabar respuesta'));
      await tester.pumpAndSettle();
      expect(audio.permissions, 1);
      expect(audio.starts, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byTooltip('Detener grabación'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.pumpAndSettle();
      expect(audio.playedPaths, ['/temporary/answer.m4a']);
      audio.updatePlayback(
        const Duration(seconds: 1),
        const Duration(seconds: 4),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<QuestionAnswerView>(find.byType(QuestionAnswerView))
            .playbackProgress,
        .25,
      );
      final wave = tester.getRect(
        find.byKey(const ValueKey('answer-waveform')),
      );
      await tester.tapAt(Offset(wave.left + wave.width * .75, wave.center.dy));
      await tester.pumpAndSettle();
      expect(audio.seeks.single.fraction, closeTo(.75, .02));
      await tester.ensureVisible(find.text('Añadir una foto (opcional)'));
      await tester.tap(find.text('Añadir una foto (opcional)'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('answer-photo-preview')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Guardar historia'));
      await tester.tap(find.text('Guardar historia'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      final story = storage.stories.single;
      expect(story.familyMemberId, _member.id);
      expect(story.question, _question.text);
      expect(story.duration, const Duration(seconds: 2));
      expect(story.photoPath, isNotNull);
      expect(story.questionRequestId, isNull);
      expect(requests.uploadedObjectPaths, isEmpty);
      expect(requests.completedQuestionRequestIds, isEmpty);
      expect(requests.familyMemberIds, isEmpty);
      final playback = fixtures.FakeAudioAnswerService();
      await tester.pumpWidget(
        MaterialApp(
          home: StoryScreen(
            story: story,
            audioService: playback,
            photoService: _Photos(storage),
            waveformService: _Waveforms(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StoryWaveformView), findsOneWidget);
      await tester.tap(find.byTooltip('Reproducir historia'));
      await tester.pumpAndSettle();
      expect(playback.playedPaths, [story.audioPath]);
    },
  );

  testWidgets('un error de guardado conserva la grabación para reintentar', (
    tester,
  ) async {
    final storage = _Storage()..fail = true;
    await _open(tester, audio: _Audio(), storage: storage);
    await tester.tap(find.text('Responder ahora'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grabar respuesta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Detener grabación'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar historia'));
    await tester.tap(find.text('Guardar historia'));
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo guardar la historia. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('answer-waveform')), findsOneWidget);
    expect(storage.stories, isEmpty);
    storage.fail = false;
    await tester.tap(find.text('Guardar historia'));
    await tester.pumpAndSettle();
    expect(storage.stories, hasLength(1));
  });

  testWidgets('permiso denegado permite reintentar y cancelar no guarda nada', (
    tester,
  ) async {
    final audio = _Audio()..allowed = false;
    final storage = _Storage();
    await _open(tester, audio: audio, storage: storage);
    await tester.tap(find.text('Responder ahora'));
    await tester.pumpAndSettle();
    expect(audio.permissions, 0);
    await tester.tap(find.text('Grabar respuesta'));
    await tester.pumpAndSettle();
    expect(audio.permissions, 1);
    expect(audio.starts, 0);
    expect(find.text('Grabar respuesta'), findsOneWidget);
    audio.allowed = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grabar respuesta'));
    await tester.pumpAndSettle();
    expect(audio.starts, 1);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Elige cómo responder'), findsOneWidget);
    expect(storage.stories, isEmpty);
  });
}
