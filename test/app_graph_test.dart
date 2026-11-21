import 'package:family_stories_app/app_graph.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

void main() {
  test('the graph passes the injected services through (A-3)', () {
    final auth = fixtures.FakeAuthService();
    final profile = fixtures.FakeProfileService();
    final members = fixtures.FakeFamilyMemberService();
    final stories = fixtures.FakeFamilyStoryService();
    final invitations = fixtures.FakeInvitationService();
    final questions = fixtures.FakeQuestionRequestService();
    final storage = fixtures.MemoryFamilyMemberStorage();
    final graph = AppGraph(
      authService: auth,
      profileService: profile,
      invitationService: invitations,
      questionRequestService: questions,
      familyMemberStorage: storage,
      familyMemberService: members,
      familyStoryService: stories,
    );
    expect(graph.authService, same(auth));
    expect(graph.profileService, same(profile));
    expect(graph.invitationService, same(invitations));
    expect(graph.questionRequestService, same(questions));
    expect(graph.familyMemberStorage, same(storage));
    expect(graph.familyMemberService, same(members));
    expect(graph.familyStoryService, same(stories));
    // No Supabase client in tests: the avatar metadata service stays null
    // and the UI renders its fallback, exactly like the old .shared getter
    // did in the same environment.
    expect(graph.visibleAccountAvatarService, isNull);
    // A-4: with both auth-listening services injected there is nothing to
    // subscribe, so no shared monitor exists.
    expect(graph.sessionMonitor, isNull);
  });
}
