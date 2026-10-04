import 'dart:async';
import 'dart:convert';

import 'package:family_stories_app/main.dart';
import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/models/question.dart';
import 'package:family_stories_app/models/user_profile.dart';
import 'package:family_stories_app/screens/question_screen.dart';
import 'package:family_stories_app/services/auth_service.dart';
import 'package:family_stories_app/services/audio_answer_service.dart';
import 'package:family_stories_app/services/avatar_storage_service.dart';
import 'package:family_stories_app/services/family_member_storage.dart';
import 'package:family_stories_app/services/family_story_storage.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/services/profile_service.dart';
import 'package:family_stories_app/widgets/profile_avatar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home muestra el contenido inicial', (tester) async {
    await tester.pumpWidget(testApp(MemoryFamilyMemberStorage()));
    await tester.pumpAndSettle();

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
    expect(find.byTooltip('Perfil'), findsOneWidget);
  });

  testWidgets('inicia sesión con Google desde el perfil', (tester) async {
    final authService = FakeAuthService();
    final profileService = FakeProfileService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: authService,
        profileService: profileService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Aún no has iniciado sesión'), findsOneWidget);
    expect(
      find.text(
        'Inicia sesión para guardar tus historias y acceder a ellas desde otros dispositivos.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continuar con Google'), findsOneWidget);

    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();

    expect(authService.signInCalls, 1);
    expect(profileService.requestedUserIds, ['google-user-id']);
    expect(find.text('Ana García'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('restaura la sesión y permite cerrarla', (tester) async {
    final authService = FakeAuthService(testAuthUser);
    await tester.pumpWidget(
      testApp(MemoryFamilyMemberStorage(), authService: authService),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Ana García'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pump();

    expect(authService.signOutCalls, 1);
    expect(find.text('Aún no has iniciado sesión'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
  });

  testWidgets('mantiene disponible el perfil si falla su carga', (
    tester,
  ) async {
    final profileService = FakeProfileService(error: Exception('fallo'));
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        profileService: profileService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo cargar tu perfil.'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(profileService.requestedUserIds, [
      'google-user-id',
      'google-user-id',
    ]);
  });

  testWidgets('edita el nombre del perfil autenticado', (tester) async {
    final profileService = FakeProfileService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        profileService: profileService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Editar perfil'), findsOneWidget);
    expect(find.text('Ana García'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '  María López  ');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(profileService.updatedUserIds, ['google-user-id']);
    expect(profileService.updatedNames, ['María López']);
    expect(profileService.updatedAvatarKeys, [null]);
    expect(profileService.updatedAvatarUrls, [null]);
    expect(find.text('María López'), findsOneWidget);
    expect(find.text('Ana García'), findsNothing);
  });

  testWidgets('selecciona, guarda y muestra un avatar predefinido', (
    tester,
  ) async {
    final profileService = FakeProfileService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        profileService: profileService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Avatar'), findsOneWidget);
    final gridImages = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(gridImages, hasLength(4));
    expect(gridImages.every((image) => image.fit == BoxFit.contain), isTrue);

    await tester.tap(find.byKey(const ValueKey('avatar_option_avatar_03')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('selected_avatar_avatar_03')),
      findsOneWidget,
    );

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(profileService.updatedAvatarKeys, ['avatar_03']);
    expect(profileService.updatedAvatarUrls, [null]);
    final avatarView = tester.widget<ProfileAvatarView>(
      find.byKey(const ValueKey('profile_avatar')),
    );
    expect(avatarView.avatarKey, 'avatar_03');

    final avatarClip = find.descendant(
      of: find.byKey(const ValueKey('profile_avatar')),
      matching: find.byType(ClipOval),
    );
    expect(tester.getSize(avatarClip), const Size.square(96));

    final avatarImage = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('profile_avatar')),
        matching: find.byType(Image),
      ),
    );
    expect(avatarImage.fit, BoxFit.contain);
    expect(
      (avatarImage.image as AssetImage).assetName,
      'assets/avatars/avatar_03.png',
    );
  });

  testWidgets('valida el nombre y conserva el texto si falla el guardado', (
    tester,
  ) async {
    final profileService = FakeProfileService(
      updateError: Exception('fallo al guardar'),
    );
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        profileService: profileService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar perfil'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Guardar'));
    await tester.pump();

    expect(find.text('Introduce un nombre'), findsOneWidget);
    expect(profileService.updatedNames, isEmpty);

    await tester.enterText(find.byType(TextFormField), 'Nombre conservado');
    await tester.tap(find.byKey(const ValueKey('avatar_option_avatar_04')));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo guardar el perfil. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Editar perfil'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'Nombre conservado',
    );
    expect(
      find.byKey(const ValueKey('selected_avatar_avatar_04')),
      findsOneWidget,
    );
  });

  testWidgets('avatar_url tiene prioridad sobre el avatar local', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileAvatarView(
            avatarKey: 'avatar_02',
            avatarUrl: 'https://example.com/custom-avatar.jpg',
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect(image.fit, BoxFit.cover);
    expect(
      (image.image as NetworkImage).url,
      'https://example.com/custom-avatar.jpg',
    );
  });

  testWidgets('elegir avatar local limpia avatar_url', (tester) async {
    final profileService = FakeProfileService(
      profile: const UserProfile(
        id: 'google-user-id',
        name: 'Ana García',
        avatarUrl: 'https://example.com/old-avatar.jpg',
      ),
    );
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        profileService: profileService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('avatar_option_avatar_01')));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(profileService.updatedAvatarKeys, ['avatar_01']);
    expect(profileService.updatedAvatarUrls, [null]);
  });

  testWidgets('guarda foto personalizada y limpia avatar_key', (tester) async {
    final profileService = FakeProfileService(
      profile: const UserProfile(
        id: 'google-user-id',
        name: 'Ana García',
        avatarKey: 'avatar_02',
      ),
    );
    final imagePicker = FakeProfileImagePicker(result: testPickedImage);
    final storageService = FakeAvatarStorageService(
      uploadedUrl: 'https://example.com/new-avatar.jpg?v=1',
    );
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        profileService: profileService,
        profileImagePicker: imagePicker,
        avatarStorageService: storageService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir foto de la galería'));
    await tester.pump();

    expect(imagePicker.pickCalls, 1);
    expect(
      find.byKey(const ValueKey('selected_profile_photo_preview')),
      findsOneWidget,
    );

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(storageService.uploadedUserIds, ['google-user-id']);
    expect(profileService.updatedAvatarKeys, [null]);
    expect(profileService.updatedAvatarUrls, [storageService.uploadedUrl]);
    final avatarView = tester.widget<ProfileAvatarView>(
      find.byKey(const ValueKey('profile_avatar')),
    );
    expect(avatarView.avatarKey, isNull);
    expect(avatarView.avatarUrl, storageService.uploadedUrl);
  });

  testWidgets('un error de subida conserva el perfil y la edición', (
    tester,
  ) async {
    const originalProfile = UserProfile(
      id: 'google-user-id',
      name: 'Ana García',
      avatarKey: 'avatar_04',
    );
    final profileService = FakeProfileService(profile: originalProfile);
    final storageService = FakeAvatarStorageService(
      error: Exception('fallo de subida'),
    );
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        profileService: profileService,
        profileImagePicker: FakeProfileImagePicker(result: testPickedImage),
        avatarStorageService: storageService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar perfil'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Nombre pendiente');
    await tester.tap(find.text('Elegir foto de la galería'));
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo guardar el perfil. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Editar perfil'), findsOneWidget);
    expect(profileService.updatedUserIds, isEmpty);
    expect(profileService.profile, same(originalProfile));
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'Nombre pendiente',
    );
    expect(
      find.byKey(const ValueKey('selected_profile_photo_preview')),
      findsOneWidget,
    );
  });

  testWidgets('permite añadir un familiar', (tester) async {
    final storage = MemoryFamilyMemberStorage();
    await tester.pumpWidget(testApp(storage));
    await tester.pumpAndSettle();

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
    expect(storage.members.single.name, 'Ana');
    expect(storage.saveCalls, 1);
  });

  testWidgets('valida los campos obligatorios', (tester) async {
    await tester.pumpWidget(testApp(MemoryFamilyMemberStorage()));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(testApp(MemoryFamilyMemberStorage()));
    await tester.pumpAndSettle();

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

    expect(find.text('Responder ahora'), findsOneWidget);
    expect(find.text('Enviar a Ana'), findsOneWidget);

    await tester.tap(find.text('Enviar a Ana'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Para enviar preguntas a Ana, primero tendrás que invitarle a Family Stories.',
      ),
      findsOneWidget,
    );
    expect(find.text('Invitar a Ana'), findsOneWidget);

    await tester.tap(find.text('Invitar a Ana'));
    await tester.pumpAndSettle();
    expect(
      find.text('Las invitaciones estarán disponibles próximamente.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Responder ahora'));
    await tester.pumpAndSettle();

    expect(find.text('Para Ana'), findsOneWidget);
    expect(find.text('Grabar respuesta'), findsOneWidget);

    expect(find.text('Preparado para grabar'), findsOneWidget);
  });

  testWidgets('permite escribir y continuar con una pregunta personalizada', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(MemoryFamilyMemberStorage()));
    await tester.pumpAndSettle();

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
      '¿Ñandú, pingüino y canción? ¡Sí, qué ilusión!',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(
      find.text('¿Ñandú, pingüino y canción? ¡Sí, qué ilusión!'),
      findsOneWidget,
    );
    expect(find.text('Responder ahora'), findsOneWidget);
    expect(find.text('Enviar a Ana'), findsOneWidget);

    await tester.tap(find.text('Responder ahora'));
    await tester.pumpAndSettle();

    expect(find.text('Para Ana'), findsOneWidget);
    expect(find.text('Grabar respuesta'), findsOneWidget);
  });

  testWidgets('carga los familiares persistidos al iniciar', (tester) async {
    final storage = MemoryFamilyMemberStorage(
      members: const [
        FamilyMember(
          id: 'carlos-id',
          name: 'Carlos',
          relationship: 'Padre/Madre',
        ),
      ],
    );

    await tester.pumpWidget(testApp(storage));
    await tester.pumpAndSettle();

    expect(find.text('Carlos'), findsOneWidget);
    expect(find.text('Padre/Madre'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(storage));
    await tester.pumpAndSettle();

    expect(find.text('Carlos'), findsOneWidget);
  });

  testWidgets('recorre los estados de grabación y reproducción', (
    tester,
  ) async {
    final audioService = FakeAudioAnswerService();
    await tester.pumpWidget(
      MaterialApp(
        home: QuestionScreen(
          familyMember: const FamilyMember(
            id: 'ana-id',
            name: 'Ana',
            relationship: 'Abuelo/a',
          ),
          question: const Question('¿Cuál es tu primer recuerdo?'),
          audioService: audioService,
          familyStoryStorage: MemoryFamilyStoryStorage(),
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

  testWidgets('guarda una grabación como historia', (tester) async {
    final audioService = FakeAudioAnswerService();
    final storyStorage = MemoryFamilyStoryStorage();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => QuestionScreen(
                      familyMember: const FamilyMember(
                        id: 'ana-id',
                        name: 'Ana',
                        relationship: 'Abuelo/a',
                      ),
                      question: const Question('¿Cuál es tu primer recuerdo?'),
                      audioService: audioService,
                      familyStoryStorage: storyStorage,
                    ),
                  ),
                );
              },
              child: const Text('Abrir pregunta'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir pregunta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grabar respuesta'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Detener grabación'));
    await tester.pump();
    await tester.tap(find.text('Guardar historia'));
    await tester.pumpAndSettle();

    expect(find.text('Abrir pregunta'), findsOneWidget);
    expect(storyStorage.stories, hasLength(1));
    expect(storyStorage.stories.single.familyMemberId, 'ana-id');
    expect(storyStorage.stories.single.duration, const Duration(seconds: 2));
  });

  testWidgets('muestra las historias guardadas del familiar', (tester) async {
    final familyMember = const FamilyMember(
      id: 'ana-id',
      name: 'Ana',
      relationship: 'Abuelo/a',
    );
    final storyStorage = MemoryFamilyStoryStorage(
      stories: [
        FamilyStory(
          id: 'story-1',
          familyMemberId: 'ana-id',
          question: '¿Cuál es tu primer recuerdo?',
          audioPath: '/persistent/story.m4a',
          duration: const Duration(seconds: 42),
          createdAt: DateTime(2026, 9, 22),
        ),
      ],
    );

    await tester.pumpWidget(
      FamilyStoriesApp(
        familyMemberStorage: MemoryFamilyMemberStorage(members: [familyMember]),
        familyStoryStorage: storyStorage,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    expect(find.text('¿Cuál es tu primer recuerdo?'), findsOneWidget);
    expect(find.text('22/09/2026 · 00:42'), findsOneWidget);
  });

  testWidgets('informa cuando se rechaza el permiso del micrófono', (
    tester,
  ) async {
    final audioService = FakeAudioAnswerService(hasPermission: false);
    await tester.pumpWidget(
      MaterialApp(
        home: QuestionScreen(
          familyMember: const FamilyMember(
            id: 'ana-id',
            name: 'Ana',
            relationship: 'Abuelo/a',
          ),
          question: const Question('¿Cuál es tu primer recuerdo?'),
          audioService: audioService,
          familyStoryStorage: MemoryFamilyStoryStorage(),
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

const testAuthUser = AuthUser(id: 'google-user-id', email: 'ana@example.com');

const testUserProfile = UserProfile(id: 'google-user-id', name: 'Ana García');

FamilyStoriesApp testApp(
  FamilyMemberStorage familyMemberStorage, {
  AuthService? authService,
  ProfileService? profileService,
  ProfileImagePicker? profileImagePicker,
  AvatarStorageService? avatarStorageService,
}) {
  return FamilyStoriesApp(
    authService: authService ?? FakeAuthService(),
    profileService: profileService ?? FakeProfileService(),
    profileImagePicker: profileImagePicker ?? FakeProfileImagePicker(),
    avatarStorageService: avatarStorageService ?? FakeAvatarStorageService(),
    familyMemberStorage: familyMemberStorage,
    familyStoryStorage: MemoryFamilyStoryStorage(),
  );
}

class FakeProfileService implements ProfileService {
  FakeProfileService({
    this.profile = testUserProfile,
    this.error,
    this.updateError,
  });

  UserProfile profile;
  final Object? error;
  final Object? updateError;
  final List<String> requestedUserIds = [];
  final List<String> updatedUserIds = [];
  final List<String> updatedNames = [];
  final List<String?> updatedAvatarKeys = [];
  final List<String?> updatedAvatarUrls = [];

  @override
  Future<UserProfile> loadForUser(String userId) async {
    requestedUserIds.add(userId);
    if (error != null) {
      throw error!;
    }
    return profile;
  }

  @override
  Future<UserProfile> updateProfile({
    required String userId,
    required String name,
    required String? avatarKey,
    required String? avatarUrl,
  }) async {
    updatedUserIds.add(userId);
    updatedNames.add(name);
    updatedAvatarKeys.add(avatarKey);
    updatedAvatarUrls.add(avatarUrl);
    if (updateError != null) {
      throw updateError!;
    }
    profile = UserProfile(
      id: profile.id,
      name: name,
      avatarKey: avatarKey,
      avatarUrl: avatarUrl,
      createdAt: profile.createdAt,
    );
    return profile;
  }
}

final testPickedImage = PickedProfileImage(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
  contentType: 'image/png',
);

class FakeProfileImagePicker implements ProfileImagePicker {
  FakeProfileImagePicker({this.result, this.error});

  final PickedProfileImage? result;
  final Object? error;
  int pickCalls = 0;

  @override
  Future<PickedProfileImage?> pickFromGallery() async {
    pickCalls++;
    if (error != null) {
      throw error!;
    }
    return result;
  }
}

class FakeAvatarStorageService implements AvatarStorageService {
  FakeAvatarStorageService({
    this.uploadedUrl = 'https://example.com/avatar.jpg?v=1',
    this.error,
  });

  final String uploadedUrl;
  final Object? error;
  final List<String> uploadedUserIds = [];
  final List<PickedProfileImage> uploadedImages = [];

  @override
  Future<String> uploadAvatar({
    required String userId,
    required PickedProfileImage image,
  }) async {
    uploadedUserIds.add(userId);
    uploadedImages.add(image);
    if (error != null) {
      throw error!;
    }
    return uploadedUrl;
  }
}

class FakeAuthService implements AuthService {
  FakeAuthService([this._user]);

  final StreamController<AuthUser?> _authController =
      StreamController<AuthUser?>.broadcast();
  AuthUser? _user;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => _authController.stream;

  @override
  Future<AuthUser> signInWithGoogle() async {
    signInCalls++;
    _user = testAuthUser;
    _authController.add(_user);
    return _user!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _user = null;
    _authController.add(null);
  }
}

class MemoryFamilyMemberStorage implements FamilyMemberStorage {
  MemoryFamilyMemberStorage({List<FamilyMember> members = const []})
    : members = List.of(members);

  List<FamilyMember> members;
  int saveCalls = 0;

  @override
  Future<List<FamilyMember>> load() async => List.of(members);

  @override
  Future<void> save(List<FamilyMember> familyMembers) async {
    members = List.of(familyMembers);
    saveCalls++;
  }
}

class MemoryFamilyStoryStorage implements FamilyStoryStorage {
  MemoryFamilyStoryStorage({List<FamilyStory> stories = const []})
    : stories = List.of(stories);

  List<FamilyStory> stories;

  @override
  Future<List<FamilyStory>> loadForFamily(String familyMemberId) async {
    return stories
        .where((story) => story.familyMemberId == familyMemberId)
        .toList();
  }

  @override
  Future<FamilyStory> saveRecording({
    required String familyMemberId,
    required String question,
    required String temporaryAudioPath,
    required Duration duration,
  }) async {
    final story = FamilyStory(
      id: 'story-${stories.length + 1}',
      familyMemberId: familyMemberId,
      question: question,
      audioPath: '/persistent/story.m4a',
      duration: duration,
      createdAt: DateTime(2026, 9, 22),
    );
    stories.add(story);
    return story;
  }
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
