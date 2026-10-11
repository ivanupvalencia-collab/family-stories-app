import 'dart:typed_data';

import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/screens/family_member_screen.dart';
import 'package:family_stories_app/services/family_member_photo_service.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/widgets/family_member_photo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

class _Photos extends FamilyMemberPhotoService {
  _Photos({this.storage, this.remote});
  final fixtures.MemoryFamilyMemberStorage? storage;
  final fixtures.FakeFamilyMemberService? remote;
  Object? loadError;
  Object? saveError;
  final List<String?> loadedPaths = [];
  final List<PickedProfileImage?> savedImages = [];

  @override
  Future<Uint8List> load(FamilyMember member) async {
    loadedPaths.add(member.photoPath);
    if (loadError != null) throw loadError!;
    return fixtures.testPickedImage.bytes;
  }

  @override
  Future<FamilyMember> save(
    FamilyMember member,
    PickedProfileImage? image,
  ) async {
    savedImages.add(image);
    if (saveError != null) throw saveError!;
    final updated = member.withPhotoPath(
      image == null ? null : 'own/${member.id}/${savedImages.length}.png',
    );
    if (storage != null) {
      final index = storage!.members.indexWhere((m) => m.id == member.id);
      storage!.members[index] = updated;
    }
    if (remote != null) {
      final index = remote!.members.indexWhere((m) => m.id == member.id);
      remote!.members[index] = updated;
    }
    return updated;
  }
}

class _CachedPhotos extends _Photos {
  Uint8List? bytes = fixtures.testPickedImage.bytes;
  final changes = ChangeNotifier();

  @override
  Uint8List? cachedPhoto(FamilyMember member) => bytes;

  @override
  Listenable get cacheChanges => changes;
}

const _member = FamilyMember(
  id: 'member',
  name: 'Pepe',
  relationship: 'Padre/Madre',
  linkedAccountId: 'linked-account',
);

Widget _profile({
  required FamilyMember member,
  required _Photos photos,
  required fixtures.FakeAuthService auth,
  ProfileImagePicker? picker,
  bool remote = false,
}) => MaterialApp(
  home: FamilyMemberScreen(
    familyMember: member,
    authService: auth,
    familyMemberService:
        photos.remote ?? fixtures.FakeFamilyMemberService(members: [member]),
    familyMemberStorage: photos.storage,
    invitationService: fixtures.FakeInvitationService(),
    invitationShareService: fixtures.FakeInvitationShareService(),
    questionRequestService: fixtures.FakeQuestionRequestService(),
    familyStoryService: fixtures.FakeFamilyStoryService(),
    familyStoryStorage: fixtures.MemoryFamilyStoryStorage(),
    isRemoteFamilyMember: remote,
    photoService: photos,
    imagePicker:
        picker ??
        fixtures.FakeProfileImagePicker(result: fixtures.testPickedImage),
  ),
);

Future<void> _choosePhoto(WidgetTester tester) async {
  if (find.byTooltip('Opciones del ser querido').evaluate().isNotEmpty) {
    await tester.tap(find.byTooltip('Opciones del ser querido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar información'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Cambiar foto'));
  await tester.pumpAndSettle();
}

Future<void> _fillCreateForm(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField), 'Pepe');
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Padre/Madre').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'two-item member menu moves photos into editor without losing name draft or link',
    (tester) async {
      final original = _member.withPhotoPath('own/member/original.png');
      final storage = fixtures.MemoryFamilyMemberStorage(members: [original]);
      final photos = _Photos(storage: storage);
      await tester.pumpWidget(
        _profile(
          member: original,
          photos: photos,
          auth: fixtures.FakeAuthService(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Opciones del ser querido'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
      expect(find.text('Cambiar foto'), findsNothing);
      expect(find.text('Eliminar foto'), findsNothing);
      expect(find.text('Actualizar familiar'), findsNothing);
      await tester.tap(find.text('Editar información'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Pepe actualizado');
      await tester.tap(find.text('Cambiar foto'));
      await tester.pumpAndSettle();
      expect(storage.members.single.photoPath, 'own/member/1.png');
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Pepe actualizado',
      );
      await tester.tap(find.text('Eliminar foto'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guardar cambios'));
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(storage.members.single.name, 'Pepe actualizado');
      expect(storage.members.single.photoPath, isNull);
      expect(storage.members.single.linkedAccountId, original.linkedAccountId);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('cached photo is shown on the first frame without loading', (
    tester,
  ) async {
    final photos = _CachedPhotos();
    await tester.pumpWidget(
      MaterialApp(
        home: FamilyMemberPhotoView(
          member: _member.withPhotoPath('own/member/photo.png'),
          photoService: photos,
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsNothing);
    expect(photos.loadedPaths, isEmpty);
    photos.bytes = null;
    photos.changes.notifyListeners();
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(photos.loadedPaths, isEmpty);
    await tester.pumpWidget(const SizedBox());
    photos.changes.dispose();
  });
  testWidgets(
    'creates local member with optional photo without uploading a profile avatar',
    (tester) async {
      final storage = fixtures.MemoryFamilyMemberStorage();
      final photos = _Photos(storage: storage);
      final avatar = fixtures.FakeAvatarStorageService();
      await tester.pumpWidget(
        fixtures.testApp(
          storage,
          familyMemberPhotoService: photos,
          avatarStorageService: avatar,
          profileImagePicker: fixtures.FakeProfileImagePicker(
            result: fixtures.testPickedImage,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Crear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir ser querido').last);
      await tester.pumpAndSettle();
      await _fillCreateForm(tester);
      await tester.tap(find.byKey(const ValueKey('pick_family_member_photo')));
      await tester.pumpAndSettle();
      expect(find.text('Quitar foto seleccionada'), findsOneWidget);
      await tester.ensureVisible(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(storage.members.single.name, 'Pepe');
      expect(storage.members.single.relationship, 'Padre/Madre');
      expect(storage.members.single.photoPath, isNotNull);
      expect(photos.savedImages, [fixtures.testPickedImage]);
      expect(avatar.uploadedImages, isEmpty);
    },
  );

  testWidgets('creates remote member before saving its own photo', (
    tester,
  ) async {
    final members = fixtures.FakeFamilyMemberService();
    final photos = _Photos(remote: members);
    await tester.pumpWidget(
      fixtures.testApp(
        fixtures.MemoryFamilyMemberStorage(),
        authService: fixtures.FakeAuthService(fixtures.testAuthUser),
        familyMemberService: members,
        familyMemberPhotoService: photos,
        profileImagePicker: fixtures.FakeProfileImagePicker(
          result: fixtures.testPickedImage,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Crear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir ser querido').last);
    await tester.pumpAndSettle();
    await _fillCreateForm(tester);
    await tester.tap(find.byKey(const ValueKey('pick_family_member_photo')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(members.createdOwnerIds, [fixtures.testAuthUser.id]);
    expect(members.members.single.photoPath, isNotNull);
    expect(photos.savedImages, hasLength(1));
  });

  testWidgets(
    'creation can discard optional selection and still save name and relationship',
    (tester) async {
      final storage = fixtures.MemoryFamilyMemberStorage();
      final photos = _Photos(storage: storage);
      await tester.pumpWidget(
        fixtures.testApp(
          storage,
          familyMemberPhotoService: photos,
          profileImagePicker: fixtures.FakeProfileImagePicker(
            result: fixtures.testPickedImage,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Crear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir ser querido').last);
      await tester.pumpAndSettle();
      await _fillCreateForm(tester);
      await tester.tap(find.byKey(const ValueKey('pick_family_member_photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar foto seleccionada'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(storage.members.single.photoPath, isNull);
      expect(storage.members.single.name, 'Pepe');
      expect(photos.savedImages, isEmpty);
    },
  );

  testWidgets(
    'failed optional photo does not lose or duplicate the created member',
    (tester) async {
      final storage = fixtures.MemoryFamilyMemberStorage();
      final photos = _Photos(storage: storage)
        ..saveError = Exception('Storage unavailable');
      await tester.pumpWidget(
        fixtures.testApp(
          storage,
          familyMemberPhotoService: photos,
          profileImagePicker: fixtures.FakeProfileImagePicker(
            result: fixtures.testPickedImage,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Crear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir ser querido').last);
      await tester.pumpAndSettle();
      await _fillCreateForm(tester);
      await tester.tap(find.byKey(const ValueKey('pick_family_member_photo')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(storage.members, hasLength(1));
      expect(storage.members.single.photoPath, isNull);
      expect(
        find.text(
          'El familiar se ha guardado, pero no su foto. Puedes añadirla desde su perfil.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Storage unavailable'), findsNothing);
    },
  );

  for (final remote in [false, true]) {
    testWidgets(
      'profile changes and removes own photo, preserving linked account (remote=$remote)',
      (tester) async {
        final original = _member.withPhotoPath('own/member/original.png');
        final storage = fixtures.MemoryFamilyMemberStorage(members: [original]);
        final members = fixtures.FakeFamilyMemberService(members: [original]);
        final photos = _Photos(
          storage: remote ? null : storage,
          remote: remote ? members : null,
        );
        await tester.pumpWidget(
          _profile(
            member: original,
            photos: photos,
            remote: remote,
            auth: fixtures.FakeAuthService(
              remote ? fixtures.testAuthUser : null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(photos.loadedPaths, ['own/member/original.png']);
        await _choosePhoto(tester);
        var view = tester.widget<FamilyMemberPhotoView>(
          find.byType(FamilyMemberPhotoView),
        );
        expect(view.member.photoPath, 'own/member/1.png');
        expect(view.member.linkedAccountId, 'linked-account');
        expect(photos.loadedPaths.last, 'own/member/1.png');
        await tester.tap(find.text('Eliminar foto'));
        await tester.pumpAndSettle();
        view = tester.widget<FamilyMemberPhotoView>(
          find.byType(FamilyMemberPhotoView),
        );
        expect(view.member.photoPath, isNull);
        expect(view.member.linkedAccountId, 'linked-account');
        expect(photos.savedImages.last, isNull);
        expect(find.byIcon(Icons.person_outline), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('P'), findsOneWidget);
        expect(
          (remote ? members.members : storage.members).single.photoPath,
          isNull,
        );
      },
    );
  }

  testWidgets(
    'cancelled gallery selection and failed save preserve original photo',
    (tester) async {
      final original = _member.withPhotoPath('own/member/original.png');
      final photos = _Photos(
        storage: fixtures.MemoryFamilyMemberStorage(members: [original]),
      );
      final auth = fixtures.FakeAuthService();
      await tester.pumpWidget(
        _profile(
          member: original,
          photos: photos,
          auth: auth,
          picker: fixtures.FakeProfileImagePicker(),
        ),
      );
      await tester.pumpAndSettle();
      await _choosePhoto(tester);
      expect(photos.savedImages, isEmpty);
      expect(
        tester
            .widget<FamilyMemberPhotoView>(find.byType(FamilyMemberPhotoView))
            .member
            .photoPath,
        original.photoPath,
      );
      photos.saveError = Exception('private details');
      await tester.pumpWidget(
        _profile(member: original, photos: photos, auth: auth),
      );
      await tester.pumpAndSettle();
      await _choosePhoto(tester);
      expect(
        tester
            .widget<FamilyMemberPhotoView>(find.byType(FamilyMemberPhotoView))
            .member
            .photoPath,
        original.photoPath,
      );
      expect(find.textContaining('private details'), findsNothing);
      expect(
        find.textContaining('No se pudo guardar la foto.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'guest fallback and missing private images remain safe',
    (tester) async {
      final photos = _Photos();
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyMemberPhotoView(member: _member, photoService: photos),
        ),
      );
      await tester.pumpAndSettle();
      expect(photos.loadedPaths, isEmpty);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      photos.loadError = Exception('file missing');
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyMemberPhotoView(
            member: _member.withPhotoPath('own/member/missing.png'),
            photoService: photos,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.textContaining('file missing'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing session hides remote photo and disables editing', (
    tester,
  ) async {
    final original = _member.withPhotoPath('own/member/original.png');
    final photos = _Photos(
      remote: fixtures.FakeFamilyMemberService(members: [original]),
    );
    final auth = fixtures.FakeAuthService(fixtures.testAuthUser);
    await tester.pumpWidget(
      _profile(member: original, photos: photos, auth: auth, remote: true),
    );
    await tester.pumpAndSettle();
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FamilyMemberPhotoView>(find.byType(FamilyMemberPhotoView))
          .member
          .photoPath,
      isNull,
    );
    expect(
      tester
          .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
          .enabled,
      isFalse,
    );
    expect(photos.savedImages, isEmpty);
  });
}
