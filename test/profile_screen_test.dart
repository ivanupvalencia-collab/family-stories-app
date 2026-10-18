import 'dart:async';

import 'package:family_stories_app/screens/accept_invitation_screen.dart';
import 'package:family_stories_app/screens/edit_profile_screen.dart';
import 'package:family_stories_app/screens/profile_screen.dart';
import 'package:family_stories_app/widgets/profile_avatar_view.dart';
import 'package:family_stories_app/models/user_profile.dart';
import 'package:family_stories_app/services/profile_avatar_image_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

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
          name: 'Ana García',
          avatarUrl: 'https://aritoria.test/avatars/own-profile?v=1',
        ),
      );

  @override
  final _AvatarImages avatarImages = _AvatarImages();
}

void main() {
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
    expect(find.text('Ana García'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);
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
}
