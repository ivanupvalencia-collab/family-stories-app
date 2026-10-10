import 'dart:async';
import 'dart:convert';

import 'package:family_stories_app/main.dart';
import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/models/family_invitation.dart';
import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/models/question.dart';
import 'package:family_stories_app/models/question_request.dart';
import 'package:family_stories_app/models/user_profile.dart';
import 'package:family_stories_app/screens/question_screen.dart';
import 'package:family_stories_app/screens/question_request_screen.dart';
import 'package:family_stories_app/screens/story_screen.dart';
import 'package:family_stories_app/screens/answer_screen.dart';
import 'package:family_stories_app/screens/accept_invitation_screen.dart';
import 'package:family_stories_app/screens/answer_options_screen.dart';
import 'package:family_stories_app/services/auth_service.dart';
import 'package:family_stories_app/services/audio_answer_service.dart';
import 'package:family_stories_app/services/avatar_storage_service.dart';
import 'package:family_stories_app/services/family_member_service.dart';
import 'package:family_stories_app/services/family_member_storage.dart';
import 'package:family_stories_app/services/family_member_photo_service.dart';
import 'package:family_stories_app/services/family_story_storage.dart';
import 'package:family_stories_app/services/family_story_service.dart';
import 'package:family_stories_app/services/incoming_link_service.dart';
import 'package:family_stories_app/services/invitation_link.dart';
import 'package:family_stories_app/services/invitation_service.dart';
import 'package:family_stories_app/services/invitation_share_service.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/services/profile_service.dart';
import 'package:family_stories_app/services/question_request_service.dart';
import 'package:family_stories_app/services/received_request_details_service.dart';
import 'package:family_stories_app/widgets/profile_avatar_view.dart';
import 'package:family_stories_app/widgets/question_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('construye y parsea un enlace de invitación válido', () {
    final link = InvitationLink.build(testInvitationToken);

    expect(
      link.toString(),
      'https://familystories.app/invite/$testInvitationToken',
    );
    expect(InvitationLink.tokenFrom(link), testInvitationToken);
  });

  test('rechaza enlaces de invitación inválidos', () {
    expect(
      InvitationLink.tokenFrom(
        Uri.parse('http://familystories.app/invite/$testInvitationToken'),
      ),
      isNull,
    );
    expect(
      InvitationLink.tokenFrom(
        Uri.parse('https://example.com/invite/$testInvitationToken'),
      ),
      isNull,
    );
    expect(
      InvitationLink.tokenFrom(
        Uri.parse(
          'https://familystories.app/invite/$testInvitationToken/extra',
        ),
      ),
      isNull,
    );
    expect(
      InvitationLink.tokenFrom(
        Uri.parse('https://familystories.app/invite/short'),
      ),
      isNull,
    );
  });

  test('mapea FamilyMember entre Supabase y el formato local', () {
    const memberId = '11111111-1111-4111-8111-111111111111';
    const ownerId = '22222222-2222-4222-8222-222222222222';
    const linkedAccountId = '33333333-3333-4333-8333-333333333333';
    final member = FamilyMember.fromSupabaseJson(const {
      'id': memberId,
      'name': 'Ana',
      'relationship': 'Abuelo/a',
      'linked_account_id': linkedAccountId,
    });

    expect(member.id, memberId);
    expect(member.linkedAccountId, linkedAccountId);
    expect(member.toSupabaseInsert(ownerId: ownerId), const {
      'owner_id': ownerId,
      'name': 'Ana',
      'relationship': 'Abuelo/a',
      'linked_account_id': linkedAccountId,
    });

    final localCopy = FamilyMember.fromJson(member.toJson());
    expect(localCopy.id, memberId);
    expect(localCopy.linkedAccountId, linkedAccountId);
  });

  testWidgets('Home muestra el contenido inicial', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(testApp(MemoryFamilyMemberStorage()));
    await tester.pumpAndSettle();

    expect(find.text('Family Stories'), findsOneWidget);
    expect(
      find.text('Las historias de tu familia empiezan aquí'),
      findsOneWidget,
    );
    expect(find.text('Añadir ser querido'), findsOneWidget);
    expect(find.text('Tus seres queridos'), findsOneWidget);
    expect(
      find.text('Las historias de tu familia empiezan aquí'),
      findsOneWidget,
    );
    expect(find.byTooltip('Perfil'), findsOneWidget);
  });

  testWidgets('muestra las preguntas pendientes del usuario autenticado', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final questionRequestService = FakeQuestionRequestService(
      pendingByRecipient: {
        testAuthUser.id: [
          testQuestionRequest(
            id: 'request-1',
            recipientId: testAuthUser.id,
            questionText: '¿Qué recuerdo guardas de tu infancia?',
          ),
        ],
      },
    );
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        questionRequestService: questionRequestService,
      ),
    );
    await tester.pumpAndSettle();

    expect(questionRequestService.requestedRecipientIds, [testAuthUser.id]);
    expect(find.text('Preguntas para ti'), findsOneWidget);
    expect(find.text('¿Qué recuerdo guardas de tu infancia?'), findsOneWidget);
    expect(find.text('Una pregunta para ti · 04/10/2026'), findsOneWidget);

    await tester.tap(find.text('¿Qué recuerdo guardas de tu infancia?'));
    await tester.pumpAndSettle();

    expect(find.text('Pregunta para ti'), findsOneWidget);
    expect(find.text('Responder'), findsOneWidget);
  });

  testWidgets('muestra un estado discreto sin preguntas pendientes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final questionRequestService = FakeQuestionRequestService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        questionRequestService: questionRequestService,
      ),
    );
    await tester.pumpAndSettle();

    expect(questionRequestService.requestedRecipientIds, [testAuthUser.id]);
    expect(find.text('Preguntas para ti'), findsOneWidget);
    expect(find.text('No tienes preguntas pendientes.'), findsOneWidget);
  });

  testWidgets('sin sesión no carga ni muestra preguntas recibidas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final localStorage = MemoryFamilyMemberStorage();
    final questionRequestService = FakeQuestionRequestService(
      pendingByRecipient: {
        testAuthUser.id: [
          testQuestionRequest(
            id: 'request-1',
            recipientId: testAuthUser.id,
            questionText: 'Pregunta privada',
          ),
        ],
      },
    );
    await tester.pumpWidget(
      testApp(localStorage, questionRequestService: questionRequestService),
    );
    await tester.pumpAndSettle();

    expect(questionRequestService.requestedRecipientIds, isEmpty);
    expect(questionRequestService.watchedRecipientIds, isEmpty);
    expect(questionRequestService.requestedAnsweredRecipientIds, isEmpty);
    expect(find.text('Historias contadas'), findsNothing);
    expect(find.text('Preguntas para ti'), findsNothing);
    expect(find.text('Pregunta privada'), findsNothing);

    localStorage.members = const [
      FamilyMember(
        id: 'local-member',
        name: 'Carmen',
        relationship: 'Abuelo/a',
      ),
    ];
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(find.text('Carmen'), findsOneWidget);
    expect(questionRequestService.requestedRecipientIds, isEmpty);
  });

  testWidgets('pull-to-refresh actualiza familiares y preguntas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final familyMemberService = FakeFamilyMemberService();
    final questionRequestService = FakeQuestionRequestService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        familyMemberService: familyMemberService,
        questionRequestService: questionRequestService,
      ),
    );
    await tester.pumpAndSettle();

    questionRequestService.pendingByRecipient[testAuthUser.id] = [
      testQuestionRequest(
        id: 'request-refresh',
        recipientId: testAuthUser.id,
        questionText: 'Pregunta actualizada manualmente',
      ),
    ];
    questionRequestService.answeredByRecipient[testAuthUser.id] = [
      testQuestionRequest(
        id: 'answered-refresh',
        recipientId: testAuthUser.id,
        questionText: 'Respuesta actualizada',
        status: QuestionRequestStatus.answered,
      ),
    ];
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();

    expect(questionRequestService.requestedAnsweredRecipientIds, [
      testAuthUser.id,
      testAuthUser.id,
    ]);
    expect(find.text('Respuesta actualizada'), findsOneWidget);
    expect(familyMemberService.requestedOwnerIds, [
      testAuthUser.id,
      testAuthUser.id,
    ]);
    expect(questionRequestService.requestedRecipientIds, [
      testAuthUser.id,
      testAuthUser.id,
    ]);
    expect(find.text('Pregunta actualizada manualmente'), findsOneWidget);
  });

  testWidgets('un evento Realtime relevante refresca las preguntas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FakeQuestionRequestService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        questionRequestService: service,
      ),
    );
    await tester.pumpAndSettle();

    service.pendingByRecipient[testAuthUser.id] = [
      testQuestionRequest(
        id: 'request-realtime',
        recipientId: testAuthUser.id,
        questionText: 'Pregunta recibida en tiempo real',
      ),
    ];
    service.emitRealtimeChange(testAuthUser.id);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(service.requestedRecipientIds, [testAuthUser.id, testAuthUser.id]);
    expect(find.text('Pregunta recibida en tiempo real'), findsOneWidget);

    service.pendingByRecipient[testAuthUser.id]!.clear();
    service.emitRealtimeChange(testAuthUser.id);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Pregunta recibida en tiempo real'), findsNothing);
  });

  testWidgets('un evento Realtime no relevante no refresca las preguntas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FakeQuestionRequestService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        questionRequestService: service,
      ),
    );
    await tester.pumpAndSettle();

    service.emitRealtimeChange('another-user-id');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(service.requestedRecipientIds, [testAuthUser.id]);
  });

  testWidgets('Realtime sustituye y cancela la suscripción al cambiar sesión', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const secondUser = AuthUser(
      id: 'second-user-id',
      email: 'bruno@example.com',
    );
    final authService = FakeAuthService(testAuthUser);
    final service = FakeQuestionRequestService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: authService,
        questionRequestService: service,
      ),
    );
    await tester.pumpAndSettle();
    expect(service.watchedRecipientIds, [testAuthUser.id]);

    authService.setUser(secondUser);
    await tester.pumpAndSettle();
    expect(service.cancelledRecipientIds, [testAuthUser.id]);
    expect(service.watchedRecipientIds, [testAuthUser.id, secondUser.id]);

    authService.setUser(null);
    await tester.pumpAndSettle();
    expect(service.cancelledRecipientIds, [testAuthUser.id, secondUser.id]);
  });

  testWidgets(
    'no crea suscripciones Realtime duplicadas para la misma sesión',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final authService = FakeAuthService(testAuthUser);
      final service = FakeQuestionRequestService();
      await tester.pumpWidget(
        testApp(
          MemoryFamilyMemberStorage(),
          authService: authService,
          questionRequestService: service,
        ),
      );
      await tester.pumpAndSettle();

      authService.setUser(testAuthUser);
      await tester.pumpAndSettle();
      service.emitRealtimeChange(testAuthUser.id);
      service.emitRealtimeChange(testAuthUser.id);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(service.watchedRecipientIds, [testAuthUser.id]);
      expect(service.requestedRecipientIds, [testAuthUser.id, testAuthUser.id]);
    },
  );

  testWidgets('muestra un error recuperable si fallan las preguntas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final questionRequestService = FakeQuestionRequestService(
      loadError: Exception('network failure'),
    );
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        questionRequestService: questionRequestService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preguntas para ti'), findsOneWidget);
    expect(find.text('No se pudieron cargar tus preguntas.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('network failure'), findsNothing);
  });

  testWidgets('un cambio de sesión no muestra preguntas del usuario anterior', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const secondUser = AuthUser(
      id: 'second-user-id',
      email: 'bruno@example.com',
    );
    final firstLoad = Completer<List<QuestionRequest>>();
    final authService = FakeAuthService(testAuthUser);
    final storyService = FakeFamilyStoryService();
    final questionRequestService = FakeQuestionRequestService(
      pendingByRecipient: {
        secondUser.id: [
          testQuestionRequest(
            id: 'request-b',
            recipientId: secondUser.id,
            questionText: 'Pregunta para Bruno',
          ),
        ],
      },
      loadCompleters: {testAuthUser.id: firstLoad},
    );
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: authService,
        familyStoryService: storyService,
        questionRequestService: questionRequestService,
      ),
    );
    await tester.pump();

    authService.setUser(secondUser);
    await tester.pumpAndSettle();
    expect(find.text('Pregunta para Bruno'), findsOneWidget);

    firstLoad.complete([
      testQuestionRequest(
        id: 'request-a',
        recipientId: testAuthUser.id,
        questionText: 'Pregunta antigua de Ana',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(questionRequestService.requestedRecipientIds, [
      testAuthUser.id,
      secondUser.id,
    ]);
    expect(find.text('Pregunta para Bruno'), findsOneWidget);
    expect(find.text('Pregunta antigua de Ana'), findsNothing);
    expect(storyService.clearAudioCacheCalls, 1);
  });

  testWidgets('abre el grabador desde una pregunta recibida', (tester) async {
    final audioService = FakeAudioAnswerService();
    await tester.pumpWidget(
      questionRequestAnswerApp(
        questionRequestService: FakeQuestionRequestService(),
        audioService: audioService,
      ),
    );

    await tester.tap(find.text('Abrir pregunta recibida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Responder'));
    await tester.pumpAndSettle();

    expect(find.text('Tu respuesta'), findsOneWidget);
    expect(find.text('¿Qué recuerdo guardas de tu infancia?'), findsOneWidget);
    expect(find.text('Grabar respuesta'), findsOneWidget);
  });

  testWidgets('sube el audio, completa la solicitud y vuelve al terminar', (
    tester,
  ) async {
    final service = FakeQuestionRequestService();
    final audioService = FakeAudioAnswerService();
    await tester.pumpWidget(
      questionRequestAnswerApp(
        questionRequestService: service,
        audioService: audioService,
      ),
    );
    await openAndRecordQuestionRequest(tester, seconds: 2);

    await tester.tap(find.text('Enviar respuesta'));
    await tester.pumpAndSettle();

    expect(find.text('Abrir pregunta recibida'), findsOneWidget);
    expect(service.uploadedLocalPaths, ['/temporary/answer.m4a']);
    expect(service.uploadedObjectPaths, hasLength(1));
    expect(
      service.uploadedObjectPaths.single,
      matches(RegExp(r'^request-1/[0-9a-f]{32}\.m4a$')),
    );
    expect(service.completedQuestionRequestIds, ['request-1']);
    expect(service.completedAudioPaths, service.uploadedObjectPaths);
    expect(service.completedDurations, [2]);
    expect(service.deletedObjectPaths, isEmpty);
    expect(audioService.discardedPaths, ['/temporary/answer.m4a']);
  });

  testWidgets('bloquea dobles pulsaciones mientras envía la respuesta', (
    tester,
  ) async {
    final completion = Completer<String>();
    final service = FakeQuestionRequestService(completionCompleter: completion);
    await tester.pumpWidget(
      questionRequestAnswerApp(
        questionRequestService: service,
        audioService: FakeAudioAnswerService(),
      ),
    );
    await openAndRecordQuestionRequest(tester);

    await tester.tap(find.text('Enviar respuesta'));
    await tester.pump();
    expect(find.text('Enviando respuesta...'), findsOneWidget);

    await tester.tap(find.text('Enviando respuesta...'));
    await tester.pump();
    expect(service.completedQuestionRequestIds, hasLength(1));

    completion.complete('story-id');
    await tester.pumpAndSettle();
    expect(find.text('Abrir pregunta recibida'), findsOneWidget);
  });

  testWidgets('conserva el audio si falla la subida', (tester) async {
    final service = FakeQuestionRequestService(
      uploadError: Exception('storage failure'),
    );
    final audioService = FakeAudioAnswerService();
    await tester.pumpWidget(
      questionRequestAnswerApp(
        questionRequestService: service,
        audioService: audioService,
      ),
    );
    await openAndRecordQuestionRequest(tester);

    await tester.tap(find.text('Enviar respuesta'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo enviar la respuesta. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Enviar respuesta'), findsOneWidget);
    expect(service.completedQuestionRequestIds, isEmpty);
    expect(service.deletedObjectPaths, isEmpty);
    expect(audioService.discardedPaths, isEmpty);
    expect(find.textContaining('storage failure'), findsNothing);
  });

  testWidgets('limpia el objeto subido y conserva el audio si falla la RPC', (
    tester,
  ) async {
    final service = FakeQuestionRequestService(
      completionError: Exception('database failure'),
    );
    final audioService = FakeAudioAnswerService();
    await tester.pumpWidget(
      questionRequestAnswerApp(
        questionRequestService: service,
        audioService: audioService,
      ),
    );
    await openAndRecordQuestionRequest(tester);

    await tester.tap(find.text('Enviar respuesta'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo enviar la respuesta. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(service.completedQuestionRequestIds, ['request-1']);
    expect(service.deletedObjectPaths, service.uploadedObjectPaths);
    expect(audioService.discardedPaths, isEmpty);
    expect(find.text('Enviar respuesta'), findsOneWidget);
    expect(find.textContaining('database failure'), findsNothing);
  });

  testWidgets('refresca Home cuando una respuesta se completa', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final request = testQuestionRequest(
      id: 'request-1',
      recipientId: testAuthUser.id,
      questionText: 'Pregunta pendiente',
    );
    final service = FakeQuestionRequestService(
      pendingByRecipient: {
        testAuthUser.id: [request],
      },
    );
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        questionRequestService: service,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pregunta pendiente'));
    await tester.pumpAndSettle();

    service.pendingByRecipient[testAuthUser.id]!.clear();
    service.answeredByRecipient[testAuthUser.id] = [
      testQuestionRequest(
        id: request.id,
        recipientId: testAuthUser.id,
        questionText: 'Respuesta recién enviada',
        status: QuestionRequestStatus.answered,
        answeredAt: DateTime.utc(2026, 10, 5),
      ),
    ];
    Navigator.of(tester.element(find.text('Pregunta para ti'))).pop(true);
    await tester.pumpAndSettle();

    expect(service.requestedRecipientIds, [testAuthUser.id, testAuthUser.id]);
    expect(find.text('Pregunta pendiente'), findsNothing);
    expect(find.text('Respuesta enviada'), findsOneWidget);
    expect(service.requestedAnsweredRecipientIds, [
      testAuthUser.id,
      testAuthUser.id,
    ]);
    expect(find.text('Respuesta recién enviada'), findsOneWidget);
  });

  testWidgets('inicia sesión con Google desde el perfil', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    expect(profileService.requestedUserIds, isNotEmpty);
    expect(profileService.requestedUserIds, everyElement('google-user-id'));
    expect(find.text('Ana García'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('restaura la sesión y permite cerrarla', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

  testWidgets(
    'muestra el perfil cacheado durante la actualización silenciosa',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final refreshCompleter = Completer<UserProfile>();
      final profileService = FakeProfileService(
        refreshCompleter: refreshCompleter,
      );
      await tester.pumpWidget(
        testApp(
          MemoryFamilyMemberStorage(),
          authService: FakeAuthService(testAuthUser),
          profileService: profileService,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        profileService.cachedForUser('google-user-id')?.name,
        'Ana García',
      );

      await tester.tap(find.byTooltip('Perfil'));
      await tester.pumpAndSettle();

      expect(find.text('Ana García'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      refreshCompleter.complete(
        const UserProfile(id: 'google-user-id', name: 'Ana actualizada'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ana actualizada'), findsOneWidget);
    },
  );

  testWidgets('limpia la caché y no reutiliza datos entre sesiones', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final authService = FakeAuthService(testAuthUser);
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

    expect(find.text('Ana García'), findsOneWidget);

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(profileService.cachedForUser('google-user-id'), isNull);
    expect(profileService.clearCacheCalls, greaterThan(0));

    profileService.profile = const UserProfile(
      id: 'second-user-id',
      name: 'Bruno Pérez',
    );
    authService.setUser(
      const AuthUser(id: 'second-user-id', email: 'bruno@example.com'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bruno Pérez'), findsOneWidget);
    expect(find.text('bruno@example.com'), findsOneWidget);
    expect(find.text('Ana García'), findsNothing);
  });

  testWidgets('mantiene disponible el perfil si falla su carga', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    expect(profileService.requestedUserIds, hasLength(3));
    expect(profileService.requestedUserIds, everyElement('google-user-id'));
  });

  testWidgets('edita el nombre del perfil autenticado', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    expect(profileService.cachedForUser('google-user-id')?.name, 'María López');
    expect(find.text('María López'), findsOneWidget);
    expect(find.text('Ana García'), findsNothing);
  });

  testWidgets('selecciona, guarda y muestra un avatar predefinido', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = MemoryFamilyMemberStorage();
    await tester.pumpWidget(testApp(storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Crear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir ser querido').last);
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
    await tester.tap(find.text('Seres queridos'));
    await tester.pumpAndSettle();
    expect(find.text('Abuelo/a'), findsOneWidget);
    expect(
      find.text('Las historias de tu familia empiezan aquí'),
      findsNothing,
    );
    expect(storage.members.single.name, 'Ana');
    expect(storage.saveCalls, 1);
  });

  testWidgets('sin sesión carga únicamente los familiares locales', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = MemoryFamilyMemberStorage(
      members: const [
        FamilyMember(
          id: 'local-id',
          name: 'Familiar local',
          relationship: 'Otro',
        ),
      ],
    );
    final remoteService = FakeFamilyMemberService(
      members: const [
        FamilyMember(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Familiar remoto',
          relationship: 'Otro',
        ),
      ],
    );

    await tester.pumpWidget(
      testApp(storage, familyMemberService: remoteService),
    );
    await tester.pumpAndSettle();

    expect(find.text('Familiar local'), findsOneWidget);
    expect(find.text('Familiar remoto'), findsNothing);
    expect(storage.loadCalls, 1);
    expect(remoteService.requestedOwnerIds, isEmpty);
  });

  testWidgets('con sesión carga únicamente los familiares remotos', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = MemoryFamilyMemberStorage(
      members: const [
        FamilyMember(
          id: 'local-id',
          name: 'Familiar local',
          relationship: 'Otro',
        ),
      ],
    );
    final remoteService = FakeFamilyMemberService(
      members: const [
        FamilyMember(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Familiar remoto',
          relationship: 'Padre/Madre',
        ),
      ],
    );

    await tester.pumpWidget(
      testApp(
        storage,
        authService: FakeAuthService(testAuthUser),
        familyMemberService: remoteService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Familiar remoto'), findsOneWidget);
    expect(find.text('Familiar local'), findsNothing);
    expect(remoteService.requestedOwnerIds, ['google-user-id']);
    expect(storage.loadCalls, 0);
  });

  testWidgets('con sesión crea el familiar mediante el servicio remoto', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = MemoryFamilyMemberStorage();
    final remoteService = FakeFamilyMemberService();
    await tester.pumpWidget(
      testApp(
        storage,
        authService: FakeAuthService(testAuthUser),
        familyMemberService: remoteService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Crear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir ser querido').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Elena');
    await tester.tap(find.text('Relación contigo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hermano/a').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Elena'), findsOneWidget);
    expect(remoteService.createdOwnerIds, ['google-user-id']);
    expect(remoteService.createdNames, ['Elena']);
    expect(remoteService.createdRelationships, ['Hermano/a']);
    expect(storage.saveCalls, 0);
  });

  testWidgets(
    'un error remoto conserva los datos locales y permite reintentar',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = MemoryFamilyMemberStorage(
        members: const [
          FamilyMember(
            id: 'local-id',
            name: 'Familiar local',
            relationship: 'Otro',
          ),
        ],
      );
      final remoteService = FakeFamilyMemberService(
        loadError: Exception('fallo remoto'),
      );
      await tester.pumpWidget(
        testApp(
          storage,
          authService: FakeAuthService(testAuthUser),
          familyMemberService: remoteService,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No se pudieron cargar los familiares.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Familiar local'), findsNothing);
      expect(storage.members.single.name, 'Familiar local');
      expect(storage.loadCalls, 0);
      expect(storage.saveCalls, 0);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(remoteService.requestedOwnerIds, [
        'google-user-id',
        'google-user-id',
      ]);
      expect(storage.members.single.name, 'Familiar local');
    },
  );

  testWidgets('valida los campos obligatorios', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(testApp(MemoryFamilyMemberStorage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Crear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir ser querido').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pump();

    expect(find.text('Introduce un nombre'), findsOneWidget);
    expect(find.text('Selecciona una relación'), findsOneWidget);
  });

  testWidgets('navega desde un familiar hasta el aviso de grabación', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(testApp(MemoryFamilyMemberStorage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Crear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir ser querido').last);
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
    expect(find.text('Ver todas las preguntas'), findsOneWidget);
    expect(find.text('Sus historias'), findsOneWidget);
    expect(
      find.text(
        'Cada vida guarda recuerdos que merecen escucharse. Empieza con una pregunta.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Ver todas las preguntas'));
    await tester.pumpAndSettle();

    expect(find.text('Escribir mi propia pregunta'), findsOneWidget);
    expect(find.text('O elige una categoría'), findsOneWidget);
    expect(find.text('Infancia'), findsOneWidget);
    expect(find.text('¿Cómo era tu casa cuando eras pequeño/a?'), findsNothing);

    await tester.tap(find.text('Infancia'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        questionDisplayText('¿Cómo era tu casa cuando eras pequeño/a?'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.text(
        questionDisplayText('¿Cómo era tu casa cuando eras pequeño/a?'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Responder ahora'), findsOneWidget);
    expect(find.text('Enviar a Ana'), findsOneWidget);

    await tester.tap(find.text('Enviar a Ana'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Inicia sesión para invitar y conectar con otras personas en Family Stories.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Responder ahora'));
    await tester.pumpAndSettle();

    expect(find.text('Para Ana'), findsOneWidget);
    expect(find.text('Grabar respuesta'), findsOneWidget);

    expect(find.text('Preparado para grabar'), findsOneWidget);
  });

  testWidgets('crea una invitación para un familiar remoto no vinculado', (
    tester,
  ) async {
    const familyMember = FamilyMember(
      id: '11111111-1111-4111-8111-111111111111',
      name: 'Pepe',
      relationship: 'Padre/Madre',
    );
    final invitationService = FakeInvitationService();
    final shareService = FakeInvitationShareService();
    final questionRequestService = FakeQuestionRequestService();
    await tester.pumpWidget(
      invitationOptionsApp(
        familyMember: familyMember,
        authService: FakeAuthService(testAuthUser),
        invitationService: invitationService,
        shareService: shareService,
        questionRequestService: questionRequestService,
        isRemoteFamilyMember: true,
      ),
    );

    await tester.tap(find.text('Enviar a Pepe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invitar a Pepe'));
    await tester.pumpAndSettle();

    expect(invitationService.createdFamilyMemberIds, [familyMember.id]);
    expect(find.text('Invitación creada'), findsOneWidget);
    expect(find.text(testInvitationToken), findsOneWidget);
    expect(familyMember.linkedAccountId, isNull);
    expect(questionRequestService.familyMemberIds, isEmpty);

    await tester.tap(find.text('Compartir invitación'));
    await tester.pump();
    expect(shareService.sharedTokens, [testInvitationToken]);
  });

  testWidgets('envía una pregunta a un familiar vinculado', (tester) async {
    final invitationService = FakeInvitationService();
    final questionRequestService = FakeQuestionRequestService();
    await tester.pumpWidget(
      invitationOptionsApp(
        familyMember: const FamilyMember(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Pepe',
          relationship: 'Padre/Madre',
          linkedAccountId: 'second-user-id',
        ),
        authService: FakeAuthService(testAuthUser),
        invitationService: invitationService,
        questionRequestService: questionRequestService,
        isRemoteFamilyMember: true,
      ),
    );

    await tester.tap(find.text('Enviar a Pepe'));
    await tester.pumpAndSettle();

    expect(questionRequestService.familyMemberIds, [
      '11111111-1111-4111-8111-111111111111',
    ]);
    expect(questionRequestService.questionTexts, [
      '¿Cuál es tu primer recuerdo?',
    ]);
    expect(find.text('Pregunta enviada a Pepe'), findsOneWidget);
    expect(invitationService.createdFamilyMemberIds, isEmpty);
  });

  testWidgets('actualiza el familiar remoto antes de enviar la pregunta', (
    tester,
  ) async {
    const staleFamilyMember = FamilyMember(
      id: '11111111-1111-4111-8111-111111111111',
      name: 'Pepe',
      relationship: 'Padre/Madre',
    );
    final familyMemberService = FakeFamilyMemberService(
      members: const [
        FamilyMember(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Pepe',
          relationship: 'Padre/Madre',
          linkedAccountId: 'second-user-id',
        ),
      ],
    );
    final invitationService = FakeInvitationService();
    final questionRequestService = FakeQuestionRequestService();
    await tester.pumpWidget(
      invitationOptionsApp(
        familyMember: staleFamilyMember,
        authService: FakeAuthService(testAuthUser),
        invitationService: invitationService,
        familyMemberService: familyMemberService,
        questionRequestService: questionRequestService,
        isRemoteFamilyMember: true,
      ),
    );

    await tester.tap(find.text('Enviar a Pepe'));
    await tester.pumpAndSettle();

    expect(familyMemberService.requestedOwnerIds, [testAuthUser.id]);
    expect(questionRequestService.familyMemberIds, [staleFamilyMember.id]);
    expect(invitationService.createdFamilyMemberIds, isEmpty);
  });

  testWidgets('bloquea dobles pulsaciones mientras envía la pregunta', (
    tester,
  ) async {
    final completer = Completer<String>();
    final questionRequestService = FakeQuestionRequestService(
      completer: completer,
    );
    await tester.pumpWidget(
      invitationOptionsApp(
        familyMember: const FamilyMember(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Pepe',
          relationship: 'Padre/Madre',
          linkedAccountId: 'second-user-id',
        ),
        authService: FakeAuthService(testAuthUser),
        invitationService: FakeInvitationService(),
        questionRequestService: questionRequestService,
        isRemoteFamilyMember: true,
      ),
    );

    await tester.tap(find.text('Enviar a Pepe'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Enviando pregunta...'), findsOneWidget);
    await tester.tap(find.text('Enviar a Pepe'));
    await tester.pump();
    expect(questionRequestService.familyMemberIds, hasLength(1));

    completer.complete('55555555-5555-4555-8555-555555555555');
    await tester.pumpAndSettle();
    expect(find.text('Pregunta enviada a Pepe'), findsOneWidget);
  });

  testWidgets('muestra un error comprensible si falla el envío', (
    tester,
  ) async {
    final questionRequestService = FakeQuestionRequestService(
      error: Exception('internal database error'),
    );
    await tester.pumpWidget(
      invitationOptionsApp(
        familyMember: const FamilyMember(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Pepe',
          relationship: 'Padre/Madre',
          linkedAccountId: 'second-user-id',
        ),
        authService: FakeAuthService(testAuthUser),
        invitationService: FakeInvitationService(),
        questionRequestService: questionRequestService,
        isRemoteFamilyMember: true,
      ),
    );

    await tester.tap(find.text('Enviar a Pepe'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo enviar la pregunta. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.textContaining('internal database error'), findsNothing);
  });

  testWidgets('un familiar local requiere iniciar sesión para invitar', (
    tester,
  ) async {
    final invitationService = FakeInvitationService();
    await tester.pumpWidget(
      invitationOptionsApp(
        familyMember: const FamilyMember(
          id: 'local-id',
          name: 'Pepe',
          relationship: 'Padre/Madre',
        ),
        authService: FakeAuthService(),
        invitationService: invitationService,
        isRemoteFamilyMember: false,
      ),
    );

    await tester.tap(find.text('Enviar a Pepe'));
    await tester.pumpAndSettle();

    expect(find.text('Necesitas iniciar sesión'), findsOneWidget);
    expect(invitationService.createdFamilyMemberIds, isEmpty);
  });

  testWidgets('previsualiza una invitación válida', (tester) async {
    final invitationService = FakeInvitationService();
    await tester.pumpWidget(
      MaterialApp(
        home: AcceptInvitationScreen(invitationService: invitationService),
      ),
    );

    await tester.enterText(find.byType(TextFormField), testInvitationToken);
    await tester.tap(find.text('Comprobar código'));
    await tester.pumpAndSettle();

    expect(invitationService.previewedTokens, [testInvitationToken]);
    expect(
      find.text('Ana García te invita a conectarte como Pepe.'),
      findsOneWidget,
    );
    expect(find.text('Aceptar'), findsOneWidget);
  });

  testWidgets('informa de forma genérica si el token no es válido', (
    tester,
  ) async {
    final invitationService = FakeInvitationService(hasPreview: false);
    await tester.pumpWidget(
      MaterialApp(
        home: AcceptInvitationScreen(invitationService: invitationService),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'codigo-no-valido');
    await tester.tap(find.text('Comprobar código'));
    await tester.pumpAndSettle();

    expect(
      find.text('El código no es válido o ya no está disponible.'),
      findsOneWidget,
    );
    expect(find.text('Pepe'), findsNothing);
  });

  testWidgets('acepta correctamente una invitación', (tester) async {
    final invitationService = FakeInvitationService();
    await tester.pumpWidget(
      MaterialApp(
        home: AcceptInvitationScreen(invitationService: invitationService),
      ),
    );

    await tester.enterText(find.byType(TextFormField), testInvitationToken);
    await tester.tap(find.text('Comprobar código'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(invitationService.acceptedTokens, [testInvitationToken]);
    expect(find.text('Invitación aceptada'), findsOneWidget);
    expect(find.text('Ya estás conectado con este familiar.'), findsOneWidget);
  });

  testWidgets('mantiene el flujo disponible si falla la aceptación', (
    tester,
  ) async {
    final invitationService = FakeInvitationService(
      acceptError: Exception('fallo'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AcceptInvitationScreen(invitationService: invitationService),
      ),
    );

    await tester.enterText(find.byType(TextFormField), testInvitationToken);
    await tester.tap(find.text('Comprobar código'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo aceptar la invitación. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Aceptar'), findsOneWidget);
    expect(find.text('Invitación aceptada'), findsNothing);
  });

  testWidgets(
    'informa cuando el usuario intenta aceptar su propia invitación',
    (tester) async {
      final invitationService = FakeInvitationService(
        acceptError: const CannotAcceptOwnInvitationException(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AcceptInvitationScreen(invitationService: invitationService),
        ),
      );

      await tester.enterText(find.byType(TextFormField), testInvitationToken);
      await tester.tap(find.text('Comprobar código'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      expect(invitationService.acceptedTokens, [testInvitationToken]);
      expect(
        find.text('No puedes aceptar una invitación creada por ti mismo.'),
        findsOneWidget,
      );
      expect(find.text('Invitación aceptada'), findsNothing);
    },
  );

  testWidgets('un enlace con sesión abre la previsualización', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final incomingLinks = FakeIncomingLinkService();
    final invitationService = FakeInvitationService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        invitationService: invitationService,
        incomingLinkService: incomingLinks,
      ),
    );
    await tester.pumpAndSettle();

    incomingLinks.emit(InvitationLink.build(testInvitationToken));
    await tester.pumpAndSettle();

    expect(invitationService.previewedTokens, [testInvitationToken]);
    expect(
      find.text('Ana García te invita a conectarte como Pepe.'),
      findsOneWidget,
    );
  });

  testWidgets('sin sesión conserva el token y continúa después del login', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final authService = FakeAuthService();
    final incomingLinks = FakeIncomingLinkService();
    final invitationService = FakeInvitationService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: authService,
        invitationService: invitationService,
        incomingLinkService: incomingLinks,
      ),
    );
    await tester.pumpAndSettle();

    incomingLinks.emit(InvitationLink.build(testInvitationToken));
    await tester.pumpAndSettle();

    expect(find.text('Aún no has iniciado sesión'), findsOneWidget);
    expect(invitationService.previewedTokens, isEmpty);

    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();

    expect(authService.signInCalls, 1);
    expect(invitationService.previewedTokens, [testInvitationToken]);
    expect(find.text('Aceptar'), findsOneWidget);
  });

  testWidgets('no procesa dos veces el mismo enlace entrante', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final incomingLinks = FakeIncomingLinkService();
    final invitationService = FakeInvitationService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        invitationService: invitationService,
        incomingLinkService: incomingLinks,
      ),
    );
    await tester.pumpAndSettle();

    final link = InvitationLink.build(testInvitationToken);
    incomingLinks.emit(link);
    incomingLinks.emit(link);
    await tester.pumpAndSettle();

    expect(invitationService.previewedTokens, [testInvitationToken]);
    expect(find.text('Código de invitación'), findsNWidgets(2));
  });

  testWidgets('aceptar desde enlace usa el mismo InvitationService', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final incomingLinks = FakeIncomingLinkService();
    final invitationService = FakeInvitationService();
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        invitationService: invitationService,
        incomingLinkService: incomingLinks,
      ),
    );
    await tester.pumpAndSettle();

    incomingLinks.emit(InvitationLink.build(testInvitationToken));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(invitationService.acceptedTokens, [testInvitationToken]);
    expect(find.text('Invitación aceptada'), findsOneWidget);
  });

  testWidgets('permite escribir y continuar con una pregunta personalizada', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(testApp(MemoryFamilyMemberStorage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Crear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir ser querido').last);
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
    await tester.tap(find.text('Ver todas las preguntas'));
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
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await tester.tap(find.text('Seres queridos'));
    await tester.pumpAndSettle();
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
        authService: FakeAuthService(),
        profileService: FakeProfileService(),
        invitationService: FakeInvitationService(),
        invitationShareService: FakeInvitationShareService(),
        questionRequestService: FakeQuestionRequestService(),
        incomingLinkService: FakeIncomingLinkService(),
        familyMemberStorage: MemoryFamilyMemberStorage(members: [familyMember]),
        familyMemberService: FakeFamilyMemberService(),
        familyStoryStorage: storyStorage,
        familyStoryService: FakeFamilyStoryService(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seres queridos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    expect(find.text('¿Cuál es tu primer recuerdo?'), findsOneWidget);
    expect(find.text('22/09/2026 · 00:42'), findsOneWidget);
  });

  testWidgets('carga, filtra y ordena las historias remotas del familiar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const familyMember = FamilyMember(
      id: 'remote-family-id',
      name: 'Pepe',
      relationship: 'Padre/Madre',
    );
    final storyService = FakeFamilyStoryService(
      stories: [
        FamilyStory(
          id: 'older-story',
          familyMemberId: familyMember.id,
          question: 'Pregunta anterior',
          audioPath: 'request-old/audio.m4a',
          duration: const Duration(seconds: 20),
          createdAt: DateTime.utc(2026, 10, 1),
        ),
        FamilyStory(
          id: 'other-story',
          familyMemberId: 'another-family-id',
          question: 'Historia de otro familiar',
          audioPath: 'request-other/audio.m4a',
          duration: const Duration(seconds: 30),
          createdAt: DateTime.utc(2026, 10, 4),
        ),
        FamilyStory(
          id: 'newer-story',
          familyMemberId: familyMember.id,
          question: 'Pregunta reciente',
          audioPath: 'request-new/audio.m4a',
          duration: const Duration(seconds: 40),
          createdAt: DateTime.utc(2026, 10, 3),
        ),
      ],
    );
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        familyMemberService: FakeFamilyMemberService(members: [familyMember]),
        familyStoryService: storyService,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pepe'));
    await tester.pumpAndSettle();

    expect(storyService.requestedFamilyMemberIds, [familyMember.id]);
    expect(find.text('Historia de otro familiar'), findsNothing);
    expect(find.text('Pregunta reciente'), findsOneWidget);
    expect(find.text('Pregunta anterior'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Pregunta reciente')).dy,
      lessThan(tester.getTopLeft(find.text('Pregunta anterior')).dy),
    );
  });

  testWidgets('descarga y reproduce el audio privado de una historia remota', (
    tester,
  ) async {
    final story = FamilyStory(
      id: 'remote-story',
      familyMemberId: 'remote-family-id',
      question: '¿Qué recuerdas de tu infancia?',
      audioPath: 'request-1/private-audio.m4a',
      duration: const Duration(seconds: 12),
      createdAt: DateTime.utc(2026, 10, 4),
    );
    final storyService = FakeFamilyStoryService();
    final audioService = FakeAudioAnswerService();
    await tester.pumpWidget(
      MaterialApp(
        home: StoryScreen(
          story: story,
          remoteStoryService: storyService,
          audioService: audioService,
        ),
      ),
    );

    await tester.tap(find.text('Reproducir historia'));
    await tester.pumpAndSettle();

    expect(storyService.requestedAudioStoryIds, [story.id]);
    expect(audioService.playedPaths, [storyService.resolvedAudioPath]);
    expect(find.text('Pausar'), findsOneWidget);

    audioService._playbackCompleteController.add(null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reproducir historia'));
    await tester.pumpAndSettle();
    expect(storyService.requestedAudioStoryIds, [story.id, story.id]);
    expect(audioService.playedPaths, [
      storyService.resolvedAudioPath,
      storyService.resolvedAudioPath,
    ]);
  });

  testWidgets('reproduce una historia local sin servicio remoto', (
    tester,
  ) async {
    final audioService = FakeAudioAnswerService();
    final story = FamilyStory(
      id: 'local-story',
      familyMemberId: 'local-family',
      question: 'Pregunta local',
      audioPath: '/persistent/local-story.m4a',
      duration: const Duration(seconds: 12),
      createdAt: DateTime.utc(2026, 10, 4),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StoryScreen(story: story, audioService: audioService),
      ),
    );
    await tester.tap(find.text('Reproducir historia'));
    await tester.pumpAndSettle();
    expect(audioService.playedPaths, [story.audioPath]);
    expect(find.text('Pausar'), findsOneWidget);
  });

  testWidgets('muestra un error recuperable al cargar historias remotas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const familyMember = FamilyMember(
      id: 'remote-family-id',
      name: 'Pepe',
      relationship: 'Padre/Madre',
    );
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: FakeAuthService(testAuthUser),
        familyMemberService: FakeFamilyMemberService(members: [familyMember]),
        familyStoryService: FakeFamilyStoryService(
          loadError: Exception('database details'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pepe'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudieron cargar sus historias.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('database details'), findsNothing);
  });

  testWidgets('muestra un error comprensible si falla el audio privado', (
    tester,
  ) async {
    final story = FamilyStory(
      id: 'remote-story',
      familyMemberId: 'remote-family-id',
      question: 'Pregunta remota',
      audioPath: 'request-1/private-audio.m4a',
      duration: const Duration(seconds: 12),
      createdAt: DateTime.utc(2026, 10, 4),
    );
    final audioService = FakeAudioAnswerService();
    await tester.pumpWidget(
      MaterialApp(
        home: StoryScreen(
          story: story,
          remoteStoryService: FakeFamilyStoryService(
            audioError: Exception('storage details'),
          ),
          audioService: audioService,
        ),
      ),
    );

    await tester.tap(find.text('Reproducir historia'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo reproducir esta historia.'), findsOneWidget);
    expect(find.text('Reproducir historia'), findsOneWidget);
    expect(audioService.playedPaths, isEmpty);
    expect(find.textContaining('storage details'), findsNothing);
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
  testWidgets(
    'Historias que has contado muestra fecha y abre la carga de la respuesta',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final loading = Completer<FamilyStory?>();
      final service = FakeQuestionRequestService(
        answeredByRecipient: {
          testAuthUser.id: [
            testQuestionRequest(
              id: 'newer',
              recipientId: testAuthUser.id,
              questionText: 'Respuesta reciente',
              status: QuestionRequestStatus.answered,
              answeredAt: DateTime.utc(2026, 10, 5, 12),
            ),
            testQuestionRequest(
              id: 'older',
              recipientId: testAuthUser.id,
              questionText: 'Respuesta anterior',
              status: QuestionRequestStatus.answered,
              answeredAt: DateTime.utc(2026, 10, 4, 12),
            ),
            testQuestionRequest(
              id: 'no-date',
              recipientId: testAuthUser.id,
              questionText: 'Respuesta sin fecha',
              status: QuestionRequestStatus.answered,
            ),
          ],
        },
        answerStoryCompleters: {'newer': loading},
      );
      await tester.pumpWidget(
        testApp(
          MemoryFamilyMemberStorage(),
          authService: FakeAuthService(testAuthUser),
          questionRequestService: service,
        ),
      );
      await tester.pumpAndSettle();
      expect(service.requestedAnsweredRecipientIds, [testAuthUser.id]);
      expect(find.text('Historias contadas'), findsOneWidget);
      expect(find.text('Para quien te preguntó · 05/10/2026'), findsOneWidget);
      expect(find.text('Para quien te preguntó · 04/10/2026'), findsOneWidget);
      expect(find.text('Respuesta sin fecha'), findsNothing);
      await tester.tap(find.text('Ver todas'));
      await tester.pumpAndSettle();
      expect(find.text('Respuesta sin fecha'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Respuesta reciente')).dy,
        lessThan(tester.getTopLeft(find.text('Respuesta anterior')).dy),
      );
      await tester.tap(find.text('Respuesta reciente'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AnswerScreen), findsOneWidget);
      expect(service.requestedAnswerStoryIds, ['newer']);
      loading.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('No se pudo abrir esta respuesta.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    },
  );

  testWidgets(
    'un error en Historias que has contado no impide cargar las pendientes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = FakeQuestionRequestService(
        answersLoadError: Exception('private database details'),
        pendingByRecipient: {
          testAuthUser.id: [
            testQuestionRequest(
              id: 'pending',
              recipientId: testAuthUser.id,
              questionText: 'Sigue pendiente',
            ),
          ],
        },
      );
      await tester.pumpWidget(
        testApp(
          MemoryFamilyMemberStorage(),
          authService: FakeAuthService(testAuthUser),
          questionRequestService: service,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sigue pendiente'), findsOneWidget);
      expect(
        find.text('No se pudieron cargar tus respuestas.'),
        findsOneWidget,
      );
      expect(find.textContaining('private database details'), findsNothing);
      service.answersLoadError = null;
      await tester.ensureVisible(find.text('Reintentar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('No se pudieron cargar tus respuestas.'), findsNothing);
      expect(service.requestedAnsweredRecipientIds, hasLength(2));
      expect(service.requestedRecipientIds, hasLength(2));
    },
  );

  testWidgets(
    'Historias que has contado se refresca con Realtime y al reabrir la app',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = FakeQuestionRequestService();
      await tester.pumpWidget(
        testApp(
          MemoryFamilyMemberStorage(),
          authService: FakeAuthService(testAuthUser),
          questionRequestService: service,
        ),
      );
      await tester.pumpAndSettle();
      service.answeredByRecipient[testAuthUser.id] = [
        testQuestionRequest(
          id: 'answered',
          recipientId: testAuthUser.id,
          questionText: 'Respuesta nueva',
          status: QuestionRequestStatus.answered,
        ),
      ];
      service.emitRealtimeChange(testAuthUser.id);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Respuesta nueva'), findsOneWidget);
      expect(service.watchedRecipientIds, [testAuthUser.id]);
      service.answeredByRecipient[testAuthUser.id]!.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Respuesta nueva'), findsNothing);
      expect(service.requestedAnsweredRecipientIds, hasLength(3));
      expect(service.watchedRecipientIds, [testAuthUser.id]);
    },
  );

  testWidgets('un cambio de sesión descarta respuestas que llegan tarde', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final loading = Completer<List<QuestionRequest>>();
    final auth = FakeAuthService(testAuthUser);
    final service = FakeQuestionRequestService(
      answersLoadCompleters: {testAuthUser.id: loading},
    );
    await tester.pumpWidget(
      testApp(
        MemoryFamilyMemberStorage(),
        authService: auth,
        questionRequestService: service,
      ),
    );
    await tester.pump();
    auth.setUser(
      const AuthUser(id: 'another-user', email: 'other@example.com'),
    );
    await tester.pumpAndSettle();
    loading.complete([
      testQuestionRequest(
        id: 'private',
        recipientId: testAuthUser.id,
        questionText: 'Respuesta privada antigua',
        status: QuestionRequestStatus.answered,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Respuesta privada antigua'), findsNothing);
    expect(service.requestedAnsweredRecipientIds, [
      testAuthUser.id,
      'another-user',
    ]);
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Historias contadas'), findsNothing);
  });

  testWidgets('Tu respuesta reutiliza la descarga privada y StoryScreen', (
    tester,
  ) async {
    final request = testQuestionRequest(
      id: 'answered',
      recipientId: testAuthUser.id,
      questionText: 'Mi respuesta',
      status: QuestionRequestStatus.answered,
    );
    final story = FamilyStory(
      id: 'sent-story',
      familyMemberId: request.familyMemberId,
      question: request.questionText,
      audioPath: 'answered/exact-upload.m4a',
      duration: const Duration(seconds: 10),
      createdAt: DateTime.utc(2026, 10, 5),
      questionRequestId: request.id,
      recordedBy: testAuthUser.id,
    );
    final requests = FakeQuestionRequestService(
      answerStories: {request.id: story},
    );
    final stories = FakeFamilyStoryService();
    final audio = FakeAudioAnswerService();
    final auth = FakeAuthService(testAuthUser);
    await tester.pumpWidget(
      MaterialApp(
        home: AnswerScreen(
          questionRequest: request,
          questionRequestService: requests,
          familyStoryService: stories,
          authService: auth,
          audioService: audio,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(StoryScreen), findsOneWidget);
    expect(
      tester.widget<StoryScreen>(find.byType(StoryScreen)).story.audioPath,
      'answered/exact-upload.m4a',
    );
    expect(stories.requestedFamilyMemberIds, isEmpty);
    await tester.tap(find.text('Reproducir historia'));
    await tester.pumpAndSettle();
    expect(stories.requestedAudioStoryIds, [story.id]);
    expect(audio.playedPaths, [stories.resolvedAudioPath]);
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(StoryScreen), findsNothing);
    expect(find.text('Reproducir historia'), findsNothing);
  });

  testWidgets(
    'Tu respuesta permite reintentar metadatos y descarta cargas de otra sesión',
    (tester) async {
      final request = testQuestionRequest(
        id: 'answered',
        recipientId: testAuthUser.id,
        questionText: 'Mi respuesta',
        status: QuestionRequestStatus.answered,
      );
      final loading = Completer<FamilyStory?>();
      final auth = FakeAuthService(testAuthUser);
      final service = FakeQuestionRequestService(
        answerStoryError: Exception('RPC missing'),
        answerStoryCompleters: {request.id: loading},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AnswerScreen(
            questionRequest: request,
            questionRequestService: service,
            familyStoryService: FakeFamilyStoryService(),
            authService: auth,
            audioService: FakeAudioAnswerService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No se pudo abrir esta respuesta.'), findsOneWidget);
      expect(find.textContaining('RPC missing'), findsNothing);
      service.answerStoryError = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await auth.signOut();
      await tester.pumpAndSettle();
      loading.complete(
        FamilyStory(
          id: 'private',
          familyMemberId: request.familyMemberId,
          question: request.questionText,
          audioPath: 'private.m4a',
          duration: Duration.zero,
          createdAt: DateTime.utc(2026, 10, 5),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StoryScreen), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
      expect(service.requestedAnswerStoryIds, [request.id, request.id]);
    },
  );
  testWidgets('no reproduce una descarga tardía después de cerrar sesión', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final request = testQuestionRequest(
      id: 'answered',
      recipientId: testAuthUser.id,
      questionText: 'Mi respuesta',
      status: QuestionRequestStatus.answered,
    );
    final story = FamilyStory(
      id: 'sent-story',
      familyMemberId: request.familyMemberId,
      question: request.questionText,
      audioPath: 'answered/exact-upload.m4a',
      duration: const Duration(seconds: 10),
      createdAt: DateTime.utc(2026, 10, 5),
    );
    final loading = Completer<String>();
    final auth = FakeAuthService(testAuthUser);
    final audio = FakeAudioAnswerService();
    await tester.pumpWidget(
      MaterialApp(
        home: AnswerScreen(
          questionRequest: request,
          questionRequestService: FakeQuestionRequestService(
            answerStories: {request.id: story},
          ),
          familyStoryService: FakeFamilyStoryService(
            audioPathCompleter: loading,
          ),
          authService: auth,
          audioService: audio,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reproducir historia'));
    await tester.pump();
    await auth.signOut();
    await tester.pumpAndSettle();
    loading.complete('/temporary/old-session.m4a');
    await tester.pumpAndSettle();
    expect(audio.playedPaths, isEmpty);
    expect(find.byType(StoryScreen), findsNothing);
  });
}

const testAuthUser = AuthUser(id: 'google-user-id', email: 'ana@example.com');

const testUserProfile = UserProfile(id: 'google-user-id', name: 'Ana García');

const testInvitationToken =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final testFamilyInvitation = FamilyInvitation(
  id: '44444444-4444-4444-8444-444444444444',
  token: testInvitationToken,
  expiresAt: DateTime.utc(2026, 10, 11),
);

final testInvitationPreview = InvitationPreview(
  familyMemberName: 'Pepe',
  inviterName: 'Ana García',
  expiresAt: DateTime.utc(2026, 10, 11),
);

QuestionRequest testQuestionRequest({
  required String id,
  required String recipientId,
  required String questionText,
  DateTime? createdAt,
  QuestionRequestStatus status = QuestionRequestStatus.pending,
  DateTime? answeredAt,
}) {
  return QuestionRequest(
    id: id,
    senderId: 'sender-user-id',
    recipientId: recipientId,
    familyMemberId: '11111111-1111-4111-8111-111111111111',
    questionText: questionText,
    status: status,
    answeredAt: answeredAt,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 4),
  );
}

Widget questionRequestAnswerApp({
  required QuestionRequestService questionRequestService,
  required AudioAnswerService audioService,
}) {
  final request = testQuestionRequest(
    id: 'request-1',
    recipientId: testAuthUser.id,
    questionText: '¿Qué recuerdo guardas de tu infancia?',
  );

  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: FilledButton(
          onPressed: () {
            Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (context) => QuestionRequestScreen(
                  questionRequest: request,
                  questionRequestService: questionRequestService,
                  audioService: audioService,
                ),
              ),
            );
          },
          child: const Text('Abrir pregunta recibida'),
        ),
      ),
    ),
  );
}

Future<void> openAndRecordQuestionRequest(
  WidgetTester tester, {
  int seconds = 1,
}) async {
  await tester.tap(find.text('Abrir pregunta recibida'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Responder'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Grabar respuesta'));
  await tester.pump();
  await tester.pump(Duration(seconds: seconds));
  await tester.tap(find.text('Detener grabación'));
  await tester.pump();
}

Widget invitationOptionsApp({
  required FamilyMember familyMember,
  required AuthService authService,
  required InvitationService invitationService,
  required bool isRemoteFamilyMember,
  InvitationShareService? shareService,
  FamilyMemberService? familyMemberService,
  QuestionRequestService? questionRequestService,
}) {
  return MaterialApp(
    home: AnswerOptionsScreen(
      familyMember: familyMember,
      question: const Question('¿Cuál es tu primer recuerdo?'),
      familyStoryStorage: MemoryFamilyStoryStorage(),
      authService: authService,
      invitationService: invitationService,
      invitationShareService: shareService ?? FakeInvitationShareService(),
      familyMemberService:
          familyMemberService ??
          FakeFamilyMemberService(members: [familyMember]),
      questionRequestService:
          questionRequestService ?? FakeQuestionRequestService(),
      isRemoteFamilyMember: isRemoteFamilyMember,
    ),
  );
}

FamilyStoriesApp testApp(
  FamilyMemberStorage familyMemberStorage, {
  AuthService? authService,
  ProfileService? profileService,
  ProfileImagePicker? profileImagePicker,
  AvatarStorageService? avatarStorageService,
  FamilyMemberService? familyMemberService,
  FamilyMemberPhotoService? familyMemberPhotoService,
  FamilyStoryService? familyStoryService,
  InvitationService? invitationService,
  InvitationShareService? invitationShareService,
  IncomingLinkService? incomingLinkService,
  QuestionRequestService? questionRequestService,
  ReceivedRequestDetailsService? receivedRequestDetailsService,
}) {
  return FamilyStoriesApp(
    authService: authService ?? FakeAuthService(),
    profileService: profileService ?? FakeProfileService(),
    profileImagePicker: profileImagePicker ?? FakeProfileImagePicker(),
    avatarStorageService: avatarStorageService ?? FakeAvatarStorageService(),
    familyMemberStorage: familyMemberStorage,
    familyMemberService: familyMemberService ?? FakeFamilyMemberService(),
    familyMemberPhotoService: familyMemberPhotoService,
    familyStoryStorage: MemoryFamilyStoryStorage(),
    familyStoryService: familyStoryService ?? FakeFamilyStoryService(),
    invitationService: invitationService ?? FakeInvitationService(),
    invitationShareService:
        invitationShareService ?? FakeInvitationShareService(),
    incomingLinkService: incomingLinkService ?? FakeIncomingLinkService(),
    questionRequestService:
        questionRequestService ?? FakeQuestionRequestService(),
    receivedRequestDetailsService: receivedRequestDetailsService,
  );
}

class FakeProfileService implements ProfileService {
  FakeProfileService({
    this.profile = testUserProfile,
    this.error,
    this.updateError,
    this.refreshCompleter,
  });

  UserProfile profile;
  final Object? error;
  final Object? updateError;
  final Completer<UserProfile>? refreshCompleter;
  final List<String> requestedUserIds = [];
  final List<String> updatedUserIds = [];
  final List<String> updatedNames = [];
  final List<String?> updatedAvatarKeys = [];
  final List<String?> updatedAvatarUrls = [];
  UserProfile? _cachedProfile;
  int clearCacheCalls = 0;

  @override
  UserProfile? cachedForUser(String userId) {
    final cachedProfile = _cachedProfile;
    return cachedProfile?.id == userId ? cachedProfile : null;
  }

  @override
  Future<UserProfile> loadForUser(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final cachedProfile = cachedForUser(userId);
    if (!forceRefresh && cachedProfile != null) {
      return cachedProfile;
    }
    requestedUserIds.add(userId);
    if (error != null) {
      throw error!;
    }
    if (forceRefresh && refreshCompleter != null) {
      profile = await refreshCompleter!.future;
    }
    _cachedProfile = profile;
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
    _cachedProfile = profile;
    return profile;
  }

  @override
  void clearCache() {
    clearCacheCalls++;
    _cachedProfile = null;
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
    setUser(null);
  }

  void setUser(AuthUser? user) {
    _user = user;
    _authController.add(user);
  }
}

class FakeFamilyMemberService implements FamilyMemberService {
  FakeFamilyMemberService({
    List<FamilyMember> members = const [],
    this.loadError,
    this.createError,
  }) : members = List.of(members);

  List<FamilyMember> members;
  final Object? loadError;
  final Object? createError;
  final List<String> requestedOwnerIds = [];
  final List<String> createdOwnerIds = [];
  final List<String> createdNames = [];
  final List<String> createdRelationships = [];

  @override
  Future<List<FamilyMember>> loadForOwner(String ownerId) async {
    requestedOwnerIds.add(ownerId);
    if (loadError != null) {
      throw loadError!;
    }
    return List.of(members);
  }

  @override
  Future<FamilyMember?> loadMemberForOwner({
    required String ownerId,
    required String familyMemberId,
  }) async {
    requestedOwnerIds.add(ownerId);
    if (loadError != null) {
      throw loadError!;
    }
    for (final member in members) {
      if (member.id == familyMemberId) {
        return member;
      }
    }
    return null;
  }

  @override
  Future<FamilyMember> create({
    required String ownerId,
    required String name,
    required String relationship,
  }) async {
    createdOwnerIds.add(ownerId);
    createdNames.add(name);
    createdRelationships.add(relationship);
    if (createError != null) {
      throw createError!;
    }

    final member = FamilyMember(
      id: '00000000-0000-4000-8000-${(members.length + 1).toString().padLeft(12, '0')}',
      name: name,
      relationship: relationship,
    );
    members.add(member);
    return member;
  }

  @override
  Future<FamilyMember> updatePhoto({
    required String ownerId,
    required String familyMemberId,
    required String? photoPath,
    required String? expectedPhotoPath,
  }) async {
    final index = members.indexWhere((member) => member.id == familyMemberId);
    if (index < 0 || members[index].photoPath != expectedPhotoPath) {
      throw StateError('Photo changed or member unavailable.');
    }
    final updated = members[index].withPhotoPath(photoPath);
    members[index] = updated;
    return updated;
  }
}

class FakeInvitationService implements InvitationService {
  FakeInvitationService({
    FamilyInvitation? invitation,
    InvitationPreview? preview,
    this.hasPreview = true,
    this.acceptResult = true,
    this.cancelResult = true,
    this.createError,
    this.previewError,
    this.acceptError,
    this.cancelError,
  }) : invitation = invitation ?? testFamilyInvitation,
       preview = hasPreview ? (preview ?? testInvitationPreview) : null;

  final FamilyInvitation invitation;
  final InvitationPreview? preview;
  final bool hasPreview;
  final bool acceptResult;
  final bool cancelResult;
  final Object? createError;
  final Object? previewError;
  final Object? acceptError;
  final Object? cancelError;
  final List<String> createdFamilyMemberIds = [];
  final List<String> previewedTokens = [];
  final List<String> acceptedTokens = [];
  final List<String> cancelledInvitationIds = [];

  @override
  Future<FamilyInvitation> createInvitation(String familyMemberId) async {
    createdFamilyMemberIds.add(familyMemberId);
    if (createError != null) {
      throw createError!;
    }
    return invitation;
  }

  @override
  Future<InvitationPreview?> getInvitationPreview(String token) async {
    previewedTokens.add(token);
    if (previewError != null) {
      throw previewError!;
    }
    return preview;
  }

  @override
  Future<bool> acceptInvitation(String token) async {
    acceptedTokens.add(token);
    if (acceptError != null) {
      throw acceptError!;
    }
    return acceptResult;
  }

  @override
  Future<bool> cancelInvitation(String invitationId) async {
    cancelledInvitationIds.add(invitationId);
    if (cancelError != null) {
      throw cancelError!;
    }
    return cancelResult;
  }
}

class FakeInvitationShareService implements InvitationShareService {
  final List<String> sharedTokens = [];

  @override
  Future<void> shareInvitation(String token) async {
    sharedTokens.add(token);
  }
}

class FakeIncomingLinkService implements IncomingLinkService {
  final StreamController<Uri> _controller = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get uriLinks => _controller.stream;

  void emit(Uri uri) {
    _controller.add(uri);
  }
}

class FakeQuestionRequestService implements QuestionRequestService {
  FakeQuestionRequestService({
    this.error,
    this.completer,
    this.loadError,
    this.uploadError,
    this.completionError,
    this.deleteError,
    this.completionCompleter,
    this.answersLoadError,
    this.answerStoryError,
    Map<String, List<QuestionRequest>> answeredByRecipient = const {},
    Map<String, FamilyStory> answerStories = const {},
    Map<String, Completer<List<QuestionRequest>>> answersLoadCompleters =
        const {},
    Map<String, Completer<FamilyStory?>> answerStoryCompleters = const {},
    Map<String, List<QuestionRequest>> pendingByRecipient = const {},
    Map<String, Completer<List<QuestionRequest>>> loadCompleters = const {},
  }) : pendingByRecipient = pendingByRecipient.map(
         (key, value) => MapEntry(key, List.of(value)),
       ),
       loadCompleters = Map.of(loadCompleters),
       answeredByRecipient = answeredByRecipient.map(
         (key, value) => MapEntry(key, List.of(value)),
       ),
       answerStories = Map.of(answerStories),
       answersLoadCompleters = Map.of(answersLoadCompleters),
       answerStoryCompleters = Map.of(answerStoryCompleters);

  Object? answersLoadError;
  Object? answerStoryError;
  final Map<String, List<QuestionRequest>> answeredByRecipient;
  final Map<String, FamilyStory> answerStories;
  final Map<String, Completer<List<QuestionRequest>>> answersLoadCompleters;
  final Map<String, Completer<FamilyStory?>> answerStoryCompleters;
  final List<String> requestedAnsweredRecipientIds = [];
  final List<String> requestedAnswerStoryIds = [];

  @override
  Future<List<QuestionRequest>> loadAnsweredForRecipient(
    String recipientId,
  ) async {
    requestedAnsweredRecipientIds.add(recipientId);
    if (answersLoadError != null) throw answersLoadError!;
    final completer = answersLoadCompleters[recipientId];
    if (completer != null) return completer.future;
    return List.of(answeredByRecipient[recipientId] ?? const []);
  }

  @override
  Future<FamilyStory?> loadAnswerStory(String questionRequestId) async {
    requestedAnswerStoryIds.add(questionRequestId);
    if (answerStoryError != null) throw answerStoryError!;
    return answerStoryCompleters[questionRequestId]?.future ??
        answerStories[questionRequestId];
  }

  final Object? error;
  final Completer<String>? completer;
  final Object? loadError;
  final Object? uploadError;
  final Object? completionError;
  final Object? deleteError;
  final Completer<String>? completionCompleter;
  final Map<String, List<QuestionRequest>> pendingByRecipient;
  final Map<String, Completer<List<QuestionRequest>>> loadCompleters;
  final List<String> familyMemberIds = [];
  final List<String> questionTexts = [];
  final List<String> requestedRecipientIds = [];
  final List<String> uploadedLocalPaths = [];
  final List<String> uploadedObjectPaths = [];
  final List<String> completedQuestionRequestIds = [];
  final List<String> completedAudioPaths = [];
  final List<int> completedDurations = [];
  final List<String> deletedObjectPaths = [];
  final List<String> watchedRecipientIds = [];
  final List<String> cancelledRecipientIds = [];
  final Map<String, StreamController<void>> _realtimeControllers = {};

  @override
  Stream<void> watchChangesForRecipient(String recipientId) {
    watchedRecipientIds.add(recipientId);
    late final StreamController<void> controller;
    controller = StreamController<void>.broadcast(
      onCancel: () {
        cancelledRecipientIds.add(recipientId);
        if (identical(_realtimeControllers[recipientId], controller)) {
          _realtimeControllers.remove(recipientId);
        }
      },
    );
    _realtimeControllers[recipientId] = controller;
    return controller.stream;
  }

  void emitRealtimeChange(String recipientId) {
    _realtimeControllers[recipientId]?.add(null);
  }

  @override
  Future<List<QuestionRequest>> loadPendingForRecipient(
    String recipientId,
  ) async {
    requestedRecipientIds.add(recipientId);
    if (loadError != null) {
      throw loadError!;
    }
    final pendingLoad = loadCompleters[recipientId];
    if (pendingLoad != null) {
      return pendingLoad.future;
    }
    return List.of(pendingByRecipient[recipientId] ?? const []);
  }

  @override
  Future<String> sendQuestion({
    required String familyMemberId,
    required String questionText,
  }) async {
    familyMemberIds.add(familyMemberId);
    questionTexts.add(questionText);
    if (error != null) {
      throw error!;
    }
    return completer?.future ?? '55555555-5555-4555-8555-555555555555';
  }

  @override
  Future<void> uploadAnswerAudio({
    required String localAudioPath,
    required String objectPath,
  }) async {
    uploadedLocalPaths.add(localAudioPath);
    uploadedObjectPaths.add(objectPath);
    if (uploadError != null) {
      throw uploadError!;
    }
  }

  @override
  Future<String> completeQuestionRequest({
    required String questionRequestId,
    required String audioPath,
    required int durationSeconds,
  }) async {
    completedQuestionRequestIds.add(questionRequestId);
    completedAudioPaths.add(audioPath);
    completedDurations.add(durationSeconds);
    if (completionError != null) {
      throw completionError!;
    }
    final result =
        await (completionCompleter?.future ??
            Future.value('story-from-question-request'));
    for (final requests in pendingByRecipient.values) {
      requests.removeWhere((request) => request.id == questionRequestId);
    }
    return result;
  }

  @override
  Future<void> deleteAnswerAudio(String objectPath) async {
    deletedObjectPaths.add(objectPath);
    if (deleteError != null) {
      throw deleteError!;
    }
  }
}

class MemoryFamilyMemberStorage implements FamilyMemberStorage {
  MemoryFamilyMemberStorage({List<FamilyMember> members = const []})
    : members = List.of(members);

  List<FamilyMember> members;
  int loadCalls = 0;
  int saveCalls = 0;

  @override
  Future<List<FamilyMember>> load() async {
    loadCalls++;
    return List.of(members);
  }

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

class FakeFamilyStoryService implements FamilyStoryService {
  FakeFamilyStoryService({
    List<FamilyStory> stories = const [],
    this.loadError,
    this.audioError,
    this.resolvedAudioPath = '/temporary/remote-story.m4a',
    this.audioPathCompleter,
  }) : stories = List.of(stories);

  final List<FamilyStory> stories;
  final Object? loadError;
  final Object? audioError;
  final String resolvedAudioPath;
  final Completer<String>? audioPathCompleter;
  final List<String> requestedFamilyMemberIds = [];
  final List<String> requestedAudioStoryIds = [];
  int clearAudioCacheCalls = 0;

  @override
  Future<void> clearAudioCache() async {
    clearAudioCacheCalls++;
  }

  @override
  Future<List<FamilyStory>> loadForFamily(String familyMemberId) async {
    requestedFamilyMemberIds.add(familyMemberId);
    if (loadError != null) {
      throw loadError!;
    }
    return stories
        .where((story) => story.familyMemberId == familyMemberId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<String> localAudioPathFor(FamilyStory story) async {
    requestedAudioStoryIds.add(story.id);
    if (audioError != null) {
      throw audioError!;
    }
    return audioPathCompleter?.future ?? resolvedAudioPath;
  }
}

class FakeAudioAnswerService implements AudioAnswerService {
  FakeAudioAnswerService({this.hasPermission = true});

  final bool hasPermission;
  final List<String> discardedPaths = [];
  final List<String> playedPaths = [];
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
  Future<void> play(String path) async {
    playedPaths.add(path);
  }

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
