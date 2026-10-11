import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/models/question.dart';
import 'package:family_stories_app/screens/family_member_screen.dart';
import 'package:family_stories_app/screens/story_screen.dart';
import 'package:family_stories_app/screens/question_screen.dart';
import 'package:family_stories_app/screens/question_request_screen.dart';
import 'package:family_stories_app/services/family_member_photo_service.dart';
import 'package:family_stories_app/services/family_member_deletion_service.dart';
import 'package:family_stories_app/services/family_member_service.dart';
import 'package:family_stories_app/services/family_story_storage.dart';
import 'package:family_stories_app/services/story_photo_service.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/widgets/family_member_space_view.dart';
import 'package:family_stories_app/widgets/story_photo_view.dart';

import 'widget_test.dart' as fixtures;

class _MemberPhotos extends FamilyMemberPhotoService {
  final forgotten = <String>[];
  @override
  Future<void> forgetPhotos(String account, Iterable<String> paths) async {
    forgotten.addAll(paths);
  }

  @override
  Future<Uint8List> load(FamilyMember member) async =>
      fixtures.testPickedImage.bytes;
  @override
  Uint8List? cachedPhoto(FamilyMember member) =>
      member.photoPath == null ? null : fixtures.testPickedImage.bytes;
  @override
  Future<FamilyMember> save(
    FamilyMember member,
    PickedProfileImage? image,
  ) async => member;
}

class _Storage extends fixtures.MemoryFamilyStoryStorage
    implements EditableFamilyStoryStorage {
  @override
  Future<FamilyStory> updatePhoto(FamilyStory story, String? path) async {
    final updated = story.withPhotoPath(path);
    final index = stories.indexWhere((s) => s.id == story.id);
    stories[index] = updated;
    return updated;
  }
}

class _StoryPhotos extends StoryPhotoService {
  final forgotten = <String>[];
  @override
  Future<void> forgetPhotos(String account, Iterable<String> paths) async {
    forgotten.addAll(paths);
  }

  _StoryPhotos({this.storage, this.fail = false});
  final _Storage? storage;
  final bool fail;
  int saves = 0;
  @override
  Future<bool> canEdit(FamilyStory story) async => true;
  @override
  Uint8List? cachedPhoto(FamilyStory story) =>
      story.photoPath == null ? null : fixtures.testPickedImage.bytes;
  @override
  Future<Uint8List> load(FamilyStory story) async =>
      fixtures.testPickedImage.bytes;
  @override
  Future<FamilyStory> save(FamilyStory story, PickedProfileImage? image) async {
    saves++;
    if (fail) throw StateError('Photo failed');
    final path = image == null ? null : 'story_photos/${story.id}/photo.png';
    return storage == null
        ? story.withPhotoPath(path)
        : storage!.updatePhoto(story, path);
  }
}

class _Deletion implements FamilyMemberDeletionService {
  @override
  bool get enabled => true;
  int calls = 0;
  Completer<FamilyMemberDeletionPlan> pending = Completer();
  @override
  Future<FamilyMemberDeletionPlan> delete({
    required String ownerId,
    required String familyMemberId,
  }) {
    calls++;
    return pending.future;
  }
}

class _CachedMembers extends fixtures.FakeFamilyMemberService
    implements FamilyMemberCacheRemover {
  _CachedMembers({required super.members});
  final forgotten = <String>[];
  @override
  Future<void> forgetMember(String ownerId, String familyMemberId) async {
    forgotten.add(familyMemberId);
  }
}

FamilyStory _story(int index, {bool photo = false}) => FamilyStory(
  id: 'story-$index',
  familyMemberId: 'member',
  question: 'Recuerdo $index',
  audioPath: '/audio.m4a',
  duration: const Duration(seconds: 42),
  createdAt: DateTime(2026, 10, index + 1),
  photoPath: photo ? 'story_photos/story-$index/photo.png' : null,
);

Widget _space(
  FamilyMember member,
  List<FamilyStory> stories, {
  bool remote = false,
  fixtures.MemoryFamilyMemberStorage? members,
  FamilyMemberDeletionService? deletion,
  FamilyMemberService? memberService,
  _MemberPhotos? photos,
  _StoryPhotos? storyPhotos,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: FamilyMemberScreen(
    familyMember: member,
    authService: fixtures.FakeAuthService(
      remote ? fixtures.testAuthUser : null,
    ),
    familyMemberStorage:
        members ?? fixtures.MemoryFamilyMemberStorage(members: [member]),
    familyMemberService:
        memberService ?? fixtures.FakeFamilyMemberService(members: [member]),
    invitationService: fixtures.FakeInvitationService(),
    invitationShareService: fixtures.FakeInvitationShareService(),
    questionRequestService: fixtures.FakeQuestionRequestService(),
    isRemoteFamilyMember: remote,
    familyStoryStorage: fixtures.MemoryFamilyStoryStorage(stories: stories),
    familyStoryService: fixtures.FakeFamilyStoryService(stories: stories),
    photoService: photos ?? _MemberPhotos(),
    storyPhotoService: storyPhotos ?? _StoryPhotos(),
    deletionService: deletion,
  ),
);

void main() {
  testWidgets(
    'remote delete: cancel, loading, double tap, error, retry, cache cleanup and return',
    (tester) async {
      const member = FamilyMember(
        id: 'member',
        name: 'Pepe',
        relationship: 'Otro',
      );
      final deletion = _Deletion();
      final members = _CachedMembers(members: [member]);
      final photos = _MemberPhotos();
      final storyPhotos = _StoryPhotos();
      final page = (_space(
        member,
        [],
        remote: true,
        deletion: deletion,
        memberService: members,
        photos: photos,
        storyPhotos: storyPhotos,
      ) as MaterialApp).home!;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => page)),
              child: const Text('Lista'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Lista'));
      await tester.pumpAndSettle();
      Future<void> confirm() async {
        await tester.tap(find.byTooltip('Opciones del ser querido'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Eliminar ser querido'));
        await tester.pumpAndSettle();
      }

      await confirm();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(deletion.calls, 0);
      await confirm();
      await tester.tap(find.text('Eliminar'));
      // The dialog is already closing after the first tap; the second tap
      // intentionally targets its former button position.
      await tester.tap(find.text('Eliminar'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(deletion.calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final menu = tester.widget<PopupMenuButton<String>>(
        find.byType(PopupMenuButton<String>),
      );
      expect(menu.enabled, isFalse);
      deletion.pending.completeError(StateError('Storage failed'));
      await tester.pumpAndSettle();
      expect(find.byType(FamilyMemberScreen), findsOneWidget);
      expect(find.textContaining('Puedes volver a intentarlo'), findsOneWidget);
      expect(members.forgotten, isEmpty);
      expect(photos.forgotten, isEmpty);
      deletion.pending = Completer();
      await confirm();
      await tester.tap(find.text('Eliminar'));
      await tester.pump();
      deletion.pending.complete(
        FamilyMemberDeletionPlan.fromJson({
          'resources': [
            {
              'bucket': 'family-member-photos',
              'path': 'owner/member/photo.png',
            },
            {'bucket': 'story-photos', 'path': 'pepe/story/photo.png'},
            {'bucket': 'story-audio', 'path': 'request/audio.m4a'},
          ],
          'story_ids': ['story'],
        }),
      );
      await tester.pumpAndSettle();
      expect(deletion.calls, 2);
      expect(members.forgotten, ['member']);
      expect(photos.forgotten, ['owner/member/photo.png']);
      expect(storyPhotos.forgotten, ['pepe/story/photo.png']);
      expect(find.byType(FamilyMemberScreen), findsNothing);
      expect(find.text('Lista'), findsOneWidget);
    },
  );
  for (final count in [0, 1, 8]) {
    for (final linked in [false, true]) {
      testWidgets(
        'small member space handles $count stories, linked=$linked, long name and 200% text',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final member = FamilyMember(
            id: 'member',
            name: 'María de los Ángeles y sus recuerdos',
            relationship: 'Abuela',
            linkedAccountId: linked ? 'linked' : null,
            photoPath: linked ? 'owner/member/photo.png' : null,
          );
          await tester.pumpWidget(
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: _space(member, [
                for (var i = 0; i < count; i++) _story(i, photo: i.isEven),
              ]),
            ),
          );
          await tester.pumpAndSettle();
          final view = tester.widget<FamilyMemberSpaceView>(
            find.byType(FamilyMemberSpaceView),
          );
          expect(
            MediaQuery.textScalerOf(
              tester.element(find.byType(FamilyMemberSpaceView)),
            ).scale(10),
            20,
          );
          final selected = view.question.text;
          expect(view.stories.length, count);
          expect(find.byType(StoryMemoryRow), findsNWidgets(count.clamp(0, 3)));
          expect(
            find.text(linked ? 'Vinculada' : 'Invitar a ${member.name}'),
            findsOneWidget,
          );
          await tester.drag(
            find.byKey(const ValueKey('member-space-scroll')),
            const Offset(0, -700),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<FamilyMemberSpaceView>(
                  find.byType(FamilyMemberSpaceView),
                )
                .question
                .text,
            selected,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'three latest previews open full story list and existing StoryScreen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _space(
          const FamilyMember(
            id: 'member',
            name: 'Mavi',
            relationship: 'Abuela',
          ),
          [for (var i = 0; i < 8; i++) _story(i, photo: i.isEven)],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<StoryMemoryRow>(find.byType(StoryMemoryRow))
            .map((r) => r.story.id),
        ['story-7', 'story-6', 'story-5'],
      );
      await tester.ensureVisible(find.text('Ver todas sus historias'));
      await tester.tap(find.text('Ver todas sus historias'));
      await tester.pumpAndSettle();
      expect(find.byType(StoryMemoryRow), findsNWidgets(8));
      await tester.tap(find.text('Recuerdo 7'));
      await tester.pumpAndSettle();
      expect(find.byType(StoryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'editing local information preserves relationship/photo/link and persists',
    (tester) async {
      const member = FamilyMember(
        id: 'member',
        name: 'Mavi',
        relationship: 'Mi relación antigua',
        linkedAccountId: 'linked',
        photoPath: 'owner/member/photo.png',
      );
      final members = fixtures.MemoryFamilyMemberStorage(members: [member]);
      await tester.pumpWidget(_space(member, [], members: members));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Opciones del ser querido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar información'));
      await tester.pumpAndSettle();
      expect(find.text('Mi relación antigua'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'María');
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(members.members.single.name, 'María');
      expect(members.members.single.linkedAccountId, 'linked');
      expect(members.members.single.photoPath, member.photoPath);
    },
  );
  testWidgets(
    'local and remote deletion require explicit confirmation and allow cancellation',
    (tester) async {
      const member = FamilyMember(
        id: 'member',
        name: 'Pepe',
        relationship: 'Otro',
      );
      final members = fixtures.MemoryFamilyMemberStorage(members: [member]);
      await tester.pumpWidget(_space(member, [], members: members));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Opciones del ser querido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar ser querido'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(members.members, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _space(member, [], remote: true, members: members),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Opciones del ser querido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar ser querido'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(members.members, hasLength(1));
    },
  );
  testWidgets(
    'StoryScreen adds/changes/removes photo and preserves audio playback',
    (tester) async {
      final photos = _StoryPhotos();
      final audio = fixtures.FakeAudioAnswerService();
      await tester.pumpWidget(
        MaterialApp(
          home: StoryScreen(
            story: _story(1),
            photoService: photos,
            audioService: audio,
            imagePicker: fixtures.FakeProfileImagePicker(
              result: fixtures.testPickedImage,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StoryPhotoView), findsNothing);
      await tester.tap(find.byTooltip('Foto de la historia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir foto'));
      await tester.pumpAndSettle();
      expect(find.byType(StoryPhotoView), findsOneWidget);
      await tester.tap(find.text('Reproducir historia'));
      await tester.pumpAndSettle();
      expect(audio.playedPaths, ['/audio.m4a']);
      await tester.tap(find.byTooltip('Foto de la historia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cambiar foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Foto de la historia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar foto'));
      await tester.pumpAndSettle();
      expect(find.byType(StoryPhotoView), findsNothing);
      expect(photos.saves, 3);
      expect(tester.takeException(), isNull);
    },
  );
  for (final remote in [false, true]) {
    for (final failure in [false, true]) {
      testWidgets(
        'saving recording remote=$remote photoFailure=$failure never loses successful audio',
        (tester) async {
          final storage = _Storage();
          final photos = _StoryPhotos(
            storage: remote ? null : storage,
            fail: failure,
          );
          final seed = FamilyStory(
            id: 'story-from-question-request',
            familyMemberId: 'member',
            question: 'Un recuerdo',
            audioPath: 'request/audio.m4a',
            duration: const Duration(seconds: 1),
            createdAt: DateTime(2026, 10, 10),
          );
          final request = fixtures.testQuestionRequest(
            id: 'request',
            recipientId: fixtures.testAuthUser.id,
            questionText: 'Un recuerdo',
          );
          final requests = fixtures.FakeQuestionRequestService(
            answerStories: {request.id: seed},
          );
          final audio = fixtures.FakeAudioAnswerService();
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => remote
                            ? QuestionRequestScreen(
                                questionRequest: request,
                                questionRequestService: requests,
                                audioService: audio,
                                photoService: photos,
                                imagePicker: fixtures.FakeProfileImagePicker(
                                  result: fixtures.testPickedImage,
                                ),
                              )
                            : QuestionScreen(
                                familyMember: const FamilyMember(
                                  id: 'member',
                                  name: 'Pepe',
                                  relationship: 'Otro',
                                ),
                                question: const Question('Un recuerdo'),
                                audioService: audio,
                                familyStoryStorage: storage,
                                photoService: photos,
                                imagePicker: fixtures.FakeProfileImagePicker(
                                  result: fixtures.testPickedImage,
                                ),
                              ),
                      ),
                    ),
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Abrir'));
          await tester.pumpAndSettle();
          if (remote) {
            await tester.tap(find.text('Responder'));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('Grabar respuesta'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.tap(find.text('Detener grabación'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Añadir una foto (opcional)'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(remote ? 'Enviar respuesta' : 'Guardar historia'),
          );
          await tester.pumpAndSettle();
          expect(photos.saves, 1);
          if (remote) {
            expect(requests.completedQuestionRequestIds, [request.id]);
            expect(requests.deletedObjectPaths, isEmpty);
          } else {
            expect(storage.stories, hasLength(1));
            expect(
              storage.stories.single.photoPath,
              failure ? isNull : isNotNull,
            );
          }
          expect(find.text('Abrir'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('visual preview of the member space using bundled fonts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final font in ['Fraunces', 'NunitoSans']) {
      final loader = FontLoader(font == 'NunitoSans' ? 'Nunito Sans' : font)
        ..addFont(rootBundle.load('assets/fonts/$font.ttf'));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: _space(
          const FamilyMember(
            id: 'member',
            name: 'Mavi',
            relationship: 'Abuela',
            linkedAccountId: 'linked',
          ),
          [_story(0), _story(1), _story(2)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('ARITORIA_PREVIEW')) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      Future<void> capture(String name) => tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('.dart_tool/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await capture('member-space-preview');
      await tester.drag(
        find.byKey(const ValueKey('member-space-scroll')),
        const Offset(0, -440),
      );
      await tester.pumpAndSettle();
      await capture('member-space-stories-preview');
    }
  });
}
