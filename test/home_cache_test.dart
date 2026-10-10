import 'dart:async';

import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/models/question_request.dart';
import 'package:family_stories_app/services/auth_service.dart';
import 'package:family_stories_app/services/remote_family_member_cache.dart';
import 'package:family_stories_app/widgets/aritoria_home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

class _Members extends fixtures.FakeFamilyMemberService
    implements CachedFamilyMemberService {
  final cached = <String, List<FamilyMember>>{};
  final cachedGates = <String, Completer<List<FamilyMember>?>>{};
  final remote = <String, Completer<List<FamilyMember>>>{};
  @override
  Future<List<FamilyMember>?> loadCachedForOwner(String ownerId) async =>
      cachedGates[ownerId]?.future ?? cached[ownerId];
  @override
  Future<List<FamilyMember>> loadForOwner(String ownerId) async {
    requestedOwnerIds.add(ownerId);
    return remote[ownerId]!.future;
  }
}

const _member = FamilyMember(
  id: 'pepe',
  name: 'Pepe',
  relationship: 'Padre/Madre',
);
const _secondUser = AuthUser(id: 'account-b', email: 'b@example.com');

void main() {
  Future<void> surface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  AritoriaHomeView view(WidgetTester tester) =>
      tester.widget(find.byType(AritoriaHomeView));

  testWidgets(
    'cache appears before remote members and questions complete; refresh silently updates',
    (tester) async {
      await surface(tester);
      final owner = fixtures.testAuthUser.id;
      final members = _Members()
        ..cached[owner] = [_member]
        ..remote[owner] = Completer();
      final questions = Completer<List<QuestionRequest>>();
      final answers = Completer<List<QuestionRequest>>();
      await tester.pumpWidget(
        fixtures.testApp(
          fixtures.MemoryFamilyMemberStorage(),
          authService: fixtures.FakeAuthService(fixtures.testAuthUser),
          familyMemberService: members,
          questionRequestService: fixtures.FakeQuestionRequestService(
            loadCompleters: {owner: questions},
            answersLoadCompleters: {owner: answers},
          ),
        ),
      );
      await tester.pump();
      expect(view(tester).members.single, same(_member));
      expect(view(tester).memberStatus, isNull);
      expect(members.requestedOwnerIds, [owner]);
      members.remote[owner]!.complete([
        const FamilyMember(id: 'ana', name: 'Ana', relationship: 'Otro'),
      ]);
      await tester.pump();
      expect(view(tester).members.single.name, 'Ana');
      expect(view(tester).memberStatus, isNull);
      questions.complete([]);
      answers.complete([]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'identical results preserve cached member instances and a failed refresh keeps content',
    (tester) async {
      await surface(tester);
      final owner = fixtures.testAuthUser.id;
      final members = _Members()
        ..cached[owner] = [_member]
        ..remote[owner] = Completer();
      await tester.pumpWidget(
        fixtures.testApp(
          fixtures.MemoryFamilyMemberStorage(),
          authService: fixtures.FakeAuthService(fixtures.testAuthUser),
          familyMemberService: members,
        ),
      );
      await tester.pumpAndSettle();
      members.remote[owner]!.complete([
        FamilyMember.fromJson(_member.toJson()),
      ]);
      await tester.pumpAndSettle();
      expect(view(tester).members.single, same(_member));
      members.remote[owner] = Completer();
      final refreshing = view(tester).onRefresh();
      await tester.pump();
      expect(view(tester).memberStatus, isNull);
      expect(view(tester).members.single, same(_member));
      members.remote[owner]!.completeError(StateError('Offline'));
      await refreshing;
      await tester.pumpAndSettle();
      expect(view(tester).members.single, same(_member));
      expect(view(tester).memberStatus, isNull);
      expect(members.requestedOwnerIds, [owner, owner]);
    },
  );

  testWidgets(
    'account switch and logout clear old content and reject late cache and remote results',
    (tester) async {
      await surface(tester);
      final owner = fixtures.testAuthUser.id;
      final auth = fixtures.FakeAuthService(fixtures.testAuthUser);
      final members = _Members()
        ..cached[owner] = [_member]
        ..remote[owner] = Completer()
        ..cached[_secondUser.id] = [
          const FamilyMember(id: 'b', name: 'Cuenta B', relationship: 'Otro'),
        ]
        ..cachedGates[_secondUser.id] = Completer()
        ..remote[_secondUser.id] = Completer();
      await tester.pumpWidget(
        fixtures.testApp(
          fixtures.MemoryFamilyMemberStorage(),
          authService: auth,
          familyMemberService: members,
        ),
      );
      await tester.pumpAndSettle();
      expect(view(tester).members.single.name, 'Pepe');
      auth.setUser(_secondUser);
      await tester.pump();
      expect(view(tester).members, isEmpty);
      members.remote[owner]!.complete([_member]);
      await tester.pump();
      expect(view(tester).members, isEmpty);
      await auth.signOut();
      await tester.pumpAndSettle();
      members.cachedGates[_secondUser.id]!.complete(
        members.cached[_secondUser.id],
      );
      await tester.pumpAndSettle();
      expect(view(tester).members, isEmpty);
      expect(view(tester).authenticated, isFalse);
      expect(members.requestedOwnerIds, [owner]);
    },
  );

  testWidgets(
    'Realtime and pull refresh retain known question and answer rows while loading',
    (tester) async {
      await surface(tester);
      final owner = fixtures.testAuthUser.id;
      final question = fixtures.testQuestionRequest(
        id: 'q',
        recipientId: owner,
        questionText: 'Pregunta conocida',
      );
      final answer = fixtures.testQuestionRequest(
        id: 'a',
        recipientId: owner,
        questionText: 'Respuesta conocida',
        status: QuestionRequestStatus.answered,
      );
      final requests = fixtures.FakeQuestionRequestService(
        pendingByRecipient: {
          owner: [question],
        },
        answeredByRecipient: {
          owner: [answer],
        },
      );
      await tester.pumpWidget(
        fixtures.testApp(
          fixtures.MemoryFamilyMemberStorage(),
          authService: fixtures.FakeAuthService(fixtures.testAuthUser),
          questionRequestService: requests,
        ),
      );
      await tester.pumpAndSettle();
      requests.loadCompleters[owner] = Completer();
      requests.answersLoadCompleters[owner] = Completer();
      requests.emitRealtimeChange(owner);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(view(tester).questions.single.id, 'q');
      expect(view(tester).answers.single.id, 'a');
      expect(view(tester).questionStatus, isNull);
      expect(view(tester).answerStatus, isNull);
      final refresh = view(tester).onRefresh();
      await tester.pump();
      expect(view(tester).questions.single, same(question));
      requests.loadCompleters[owner]!.complete([]);
      requests.answersLoadCompleters[owner]!.complete([]);
      await refresh;
      await tester.pumpAndSettle();
      expect(view(tester).questions, isEmpty);
      expect(view(tester).answers, isEmpty);
    },
  );
}
