import 'dart:async';
import 'dart:typed_data';

import 'package:family_stories_app/screens/accept_invitation_screen.dart';
import 'package:family_stories_app/screens/edit_profile_screen.dart';
import 'package:family_stories_app/screens/profile_screen.dart';
import 'package:family_stories_app/widgets/profile_avatar_view.dart';
import 'package:family_stories_app/widgets/aritoria_home_view.dart';
import 'package:family_stories_app/models/user_profile.dart';
import 'package:family_stories_app/services/profile_avatar_image_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;
import 'photo_editor_test_support.dart';

class _SavedProfiles extends fixtures.FakeProfileService
    implements ProfileAvatarImageSource {
  _SavedProfiles()
    : super(
        profile: const UserProfile(
          id: 'google-user-id',
          name: 'Usuario D',
          avatarUrl: 'https://example.com/old.jpg?v=1',
        ),
      );

  @override
  final avatarImages = ProfileAvatarImageCache();
  Uint8List? savedBytes;

  @override
  Future<UserProfile> updateProfile({
    required String userId,
    required String name,
    required String? avatarKey,
    required String? avatarUrl,
    Uint8List? avatarBytes,
  }) async {
    final updated = await super.updateProfile(
      userId: userId,
      name: name,
      avatarKey: avatarKey,
      avatarUrl: avatarUrl,
    );
    savedBytes = avatarBytes;
    await avatarImages.remember(updated, bytes: avatarBytes);
    return updated;
  }
}

class _AvatarImages extends ProfileAvatarImageCache {
  final image = MemoryImage(fixtures.testPickedImage.bytes);
  int clears = 0;

  @override
  ImageProvider? imageFor(UserProfile profile) =>
      profile.avatarUrl == null ? null : image;

  @override
  void clear() {
    clears++;
    super.clear();
  }
}

class _ProfilesWithImages extends fixtures.FakeProfileService
    implements ProfileAvatarImageSource {
  _ProfilesWithImages()
    : super(
        profile: const UserProfile(
          id: 'google-user-id',
          name: 'Usuario D',
          avatarUrl: 'https://aritoria.test/avatars/own-profile?v=1',
        ),
      );

  @override
  final _AvatarImages avatarImages = _AvatarImages();
}

// S-7: the server refuses the sign-out, so no `signedOut` event is emitted.
class _OfflineAuthService extends fixtures.FakeAuthService {
  _OfflineAuthService(super.user);

  int attempts = 0;

  @override
  Future<void> signOut() async {
    attempts++;
    throw StateError('No network');
  }
}

void main() {
  testWidgets(
    'saving the local photo refreshes Perfil and mounted Home immediately',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final profiles = _SavedProfiles();
      addTearDown(profiles.avatarImages.dispose);
      await tester.runAsync(
        () => profiles.avatarImages.remember(
          profiles.profile,
          bytes: fixtures.testPickedImage.bytes,
        ),
      );
      final originalImage = profiles.avatarImages.imageFor(profiles.profile)!;
      final storage = fixtures.FakeAvatarStorageService(
        uploadedUrl: 'https://example.com/new.jpg?v=2',
      );
      await tester.pumpWidget(
        fixtures.testApp(
          fixtures.MemoryFamilyMemberStorage(),
          authService: fixtures.FakeAuthService(fixtures.testAuthUser),
          profileService: profiles,
          profileImagePicker: fixtures.FakeProfileImagePicker(
            result: fixtures.testPickedImage,
          ),
          avatarStorageService: storage,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editar foto de perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick_profile_photo')));
      await tester.pump();
      await confirmPhotoCrop(tester);
      await tester.tap(find.text('Guardar'));
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(EditProfileScreen).evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
      final avatar = tester.widget<ProfileAvatarView>(
        find.byKey(const ValueKey('profile_avatar')),
      );
      expect(avatar.avatarUrl, storage.uploadedUrl);
      expect(profiles.savedBytes, same(storage.uploadedImages.single.bytes));
      expect(
        avatar.imageProvider,
        same(profiles.avatarImages.imageFor(profiles.profile)),
      );
      final image = tester.widget<RawImage>(
        find.descendant(
          of: find.byKey(const ValueKey('profile_avatar')),
          matching: find.byType(RawImage),
        ),
      );
      // No HTTP can succeed in this widget test: decoded pixels must come from
      // the selected bytes, not a fresh download of the uploaded URL.
      expect(image.image, isNotNull);
      expect(
        PaintingBinding.instance.imageCache.containsKey(originalImage),
        isFalse,
      );
      final home = tester.widget<AritoriaHomeView>(
        find.byType(AritoriaHomeView, skipOffstage: false),
      );
      expect(home.profile!.avatarUrl, storage.uploadedUrl);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  Future<void> openProfile(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    fixtures.FakeAuthService? auth,
    fixtures.FakeProfileService? profiles,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ProfileScreen(
          authService: auth ?? fixtures.FakeAuthService(fixtures.testAuthUser),
          profileService: profiles ?? fixtures.FakeProfileService(),
          invitationService: fixtures.FakeInvitationService(),
          profileImagePicker: fixtures.FakeProfileImagePicker(),
          avatarStorageService: fixtures.FakeAvatarStorageService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Perfil reutiliza la imagen del servicio y la limpia al salir', (
    tester,
  ) async {
    final profiles = _ProfilesWithImages();
    final auth = fixtures.FakeAuthService(fixtures.testAuthUser);
    await tester.runAsync(() async {
      final ready = Completer<void>();
      final stream = profiles.avatarImages.image.resolve(
        ImageConfiguration.empty,
      );
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, synchronous) {
        info.dispose();
        stream.removeListener(listener);
        ready.complete();
      }, onError: ready.completeError);
      stream.addListener(listener);
      await ready.future;
    });
    await openProfile(tester, auth: auth, profiles: profiles);
    final avatar = find.byKey(const ValueKey('profile_avatar'));
    final image = tester.widget<Image>(
      find.descendant(of: avatar, matching: find.byType(Image)),
    );
    expect(image.image, same(profiles.avatarImages.image));
    final pixels = tester.widget<RawImage>(
      find.descendant(of: avatar, matching: find.byType(RawImage)),
    );
    expect(pixels.image, isNotNull);

    auth.setUser(null);
    await tester.pumpAndSettle();
    expect(profiles.avatarImages.clears, 1);
    expect(
      find.descendant(of: avatar, matching: find.byType(Image)),
      findsNothing,
    );
  });

  testWidgets('el control del avatar abre la edición existente', (
    tester,
  ) async {
    await openProfile(tester);
    final avatar = tester.widget<ProfileAvatarView>(
      find.byKey(const ValueKey('profile_avatar')),
    );
    expect(avatar.avatarUrl, fixtures.testUserProfile.avatarUrl);
    expect(avatar.avatarKey, fixtures.testUserProfile.avatarKey);
    expect(find.text('Usuario D'), findsOneWidget);
    expect(find.text('usuario-e@example.com'), findsOneWidget);
    await tester.tap(find.byTooltip('Editar foto de perfil'));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsOneWidget);
  });

  testWidgets('el código sigue abriendo la aceptación de una invitación', (
    tester,
  ) async {
    await openProfile(tester);
    final invitation = find.text('Introducir código de invitación');
    expect(find.text('Acepta una invitación recibida'), findsOneWidget);
    await tester.ensureVisible(invitation);
    await tester.tap(invitation);
    await tester.pumpAndSettle();
    expect(find.byType(AcceptInvitationScreen), findsOneWidget);
  });

  testWidgets('ajustes y cierre son accesibles con pantalla y texto grandes', (
    tester,
  ) async {
    final auth = fixtures.FakeAuthService(fixtures.testAuthUser);
    await openProfile(
      tester,
      size: const Size(320, 640),
      textScale: 1.6,
      auth: auth,
    );
    expect(tester.takeException(), isNull);
    for (final label in ['Notificaciones', 'Privacidad', 'Ayuda y soporte']) {
      final option = find.text(label);
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(find.text('Próximamente'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    final signOut = find.text('Cerrar sesión');
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'un cierre que falla limpia la caché y no miente sobre la sesión viva',
    (tester) async {
      final auth = _OfflineAuthService(fixtures.testAuthUser);
      final profiles = fixtures.FakeProfileService();
      await openProfile(tester, auth: auth, profiles: profiles);

      final signOut = find.text('Cerrar sesión');
      await tester.ensureVisible(signOut);
      await tester.tap(signOut);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(auth.attempts, 1);
      // S-7: the cache purge must run even though signOut() threw.
      expect(profiles.clearCacheCalls, 1);
      expect(
        find.text('No se pudo cerrar sesión. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      // The session is still alive, so the screen must not log the user out.
      expect(find.text('Continuar con Google'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
