import 'dart:async';
import 'dart:typed_data';

import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/models/user_profile.dart';
import 'package:family_stories_app/services/family_member_photo_service.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/services/visible_account_avatar_service.dart';
import 'package:family_stories_app/widgets/aritoria_home_view.dart';
import 'package:family_stories_app/widgets/family_member_photo_view.dart';
import 'package:family_stories_app/widgets/profile_avatar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

const first = FamilyMember(id: 'first', name: 'Ana', relationship: 'Abuelo/a');
const linked = FamilyMember(
  id: 'linked',
  name: 'Pepe',
  relationship: 'Padre/Madre',
  linkedAccountId: 'account',
);
const account = UserProfile(
  id: 'account',
  name: 'Cuenta de Pepe',
  avatarKey: 'avatar_01',
);

class _Avatars extends VisibleAccountAvatarService {
  final profiles = <String, UserProfile>{};
  Completer<UserProfile?>? pending;
  bool fail = false;
  @override
  UserProfile? cached(String id) => profiles[id];
  @override
  Future<UserProfile?> load(String id) async {
    if (fail) throw StateError('optional RPC unavailable');
    final result = pending == null ? profiles[id] : await pending!.future;
    if (result != null) profiles[id] = result;
    return result;
  }
}

class _Photos extends FamilyMemberPhotoService {
  @override
  Uint8List? cachedPhoto(FamilyMember member) =>
      member.photoPath == null ? null : fixtures.testPickedImage.bytes;
  @override
  Future<Uint8List> load(FamilyMember member) async =>
      fixtures.testPickedImage.bytes;
  @override
  Future<FamilyMember> save(
    FamilyMember member,
    PickedProfileImage? image,
  ) async => member;
}

Widget _home(
  List<FamilyMember> members,
  _Avatars avatars, {
  ValueChanged<FamilyMember?>? onHero,
  bool authenticated = true,
}) => MaterialApp(
  home: Scaffold(
    body: AritoriaHomeView(
      members: members,
      photos: _Photos(),
      profile: null,
      avatarService: avatars,
      authenticated: authenticated,
      questions: const [],
      answers: const [],
      details: const {},
      memberStatus: null,
      questionStatus: null,
      answerStatus: null,
      onRefresh: () async {},
      onNotifications: () {},
      onAdd: () {},
      onMember: (_) {},
      onHero: onHero ?? (_) {},
      onAllMembers: () {},
      onAllQuestions: () {},
      onAllAnswers: () {},
      onQuestion: (_) {},
      onAnswer: (_) {},
    ),
  ),
);

Finder get hero => find.byKey(const ValueKey('home-hero'));
FamilyMember heroMember(WidgetTester tester) => tester
    .widget<FamilyMemberPhotoView>(
      find.descendant(of: hero, matching: find.byType(FamilyMemberPhotoView)),
    )
    .member;

void main() {
  test('first available image includes own path, linked URL and valid catalog avatar', () {
    final own = first.withPhotoPath('own.png');
    expect(selectHomeHero([]), isNull);
    expect(selectHomeHero([first, linked]), same(first));
    expect(
      selectHomeHero([first, linked], linkedProfile: (_) => account),
      same(linked),
    );
    // Priority is list order across members, not all own photos before avatars.
    expect(
      selectHomeHero([linked, own], linkedProfile: (_) => account),
      same(linked),
    );
    expect(
      selectHomeHero([own, linked], linkedProfile: (_) => account),
      same(own),
    );
    expect(
      selectHomeHero(
        [first, linked],
        linkedProfile: (_) => const UserProfile(
          id: 'account',
          name: 'Pepe',
          avatarUrl: 'https://example.test/photo.png',
        ),
      ),
      same(linked),
    );
    expect(
      selectHomeHero(
        [first, linked],
        linkedProfile: (_) => const UserProfile(
          id: 'account',
          name: 'Pepe',
          avatarUrl: '  ',
          avatarKey: 'unknown',
        ),
      ),
      same(first),
    );
    expect(
      selectHomeHero([
        linked,
        own,
      ], linkedProfile: (_) => const UserProfile(id: 'account', name: 'Pepe')),
      same(own),
    );
  });

  testWidgets(
    'cached linked avatar selects immediately, renders same avatar and CTA target',
    (tester) async {
      final avatars = _Avatars()..profiles['account'] = account;
      FamilyMember? tapped;
      await tester.pumpWidget(
        _home([first, linked], avatars, onHero: (member) => tapped = member),
      );
      expect(heroMember(tester), same(linked));
      final avatar = tester.widget<ProfileAvatarView>(
        find.descendant(of: hero, matching: find.byType(ProfileAvatarView)),
      );
      expect(avatar.avatarKey, 'avatar_01');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conoce su historia'));
      expect(tapped, same(linked));
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );

  testWidgets(
    'uncached metadata changes hero to first image, ahead of later own photo',
    (tester) async {
      final avatars = _Avatars()..pending = Completer<UserProfile?>();
      final own = first.withPhotoPath('own.png');
      FamilyMember? tapped;
      await tester.pumpWidget(
        _home([linked, own], avatars, onHero: (member) => tapped = member),
      );
      expect(heroMember(tester), same(own));
      avatars.pending!.complete(account);
      await tester.pumpAndSettle();
      expect(heroMember(tester), same(linked));
      await tester.tap(find.text('Conoce su historia'));
      expect(tapped, same(linked));
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );

  testWidgets(
    'own image still overrides linked avatar for the selected member',
    (tester) async {
      final avatars = _Avatars()..profiles['account'] = account;
      final own = linked.withPhotoPath('own.png');
      await tester.pumpWidget(_home([first, own], avatars));
      await tester.pumpAndSettle();
      expect(heroMember(tester), same(own));
      expect(
        find.descendant(of: hero, matching: find.byType(ProfileAvatarView)),
        findsNothing,
      );
      expect(
        find.descendant(of: hero, matching: find.byType(Image)),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );

  testWidgets(
    'missing metadata/RPC keeps first-member fallback; guest ignores remote avatars',
    (tester) async {
      final avatars = _Avatars()..fail = true;
      await tester.pumpWidget(_home([first, linked], avatars));
      await tester.pumpAndSettle();
      expect(heroMember(tester), same(first));
      expect(tester.takeException(), isNull);
      avatars.profiles['account'] = account;
      await tester.pumpWidget(
        _home([first, linked], avatars, authenticated: false),
      );
      await tester.pumpAndSettle();
      expect(heroMember(tester), same(first));
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );

  testWidgets(
    'cleared session cache and removed members stop selecting the old avatar',
    (tester) async {
      final avatars = _Avatars()..profiles['account'] = account;
      await tester.pumpWidget(_home([first, linked], avatars));
      await tester.pumpAndSettle();
      expect(heroMember(tester), same(linked));
      avatars.profiles.clear();
      avatars.notifyListeners();
      await tester.pumpAndSettle();
      expect(heroMember(tester), same(first));
      avatars.profiles['account'] = account;
      await tester.pumpWidget(_home([linked], avatars));
      await tester.pumpAndSettle();
      expect(heroMember(tester), same(linked));
      await tester.pumpWidget(_home([first], avatars));
      await tester.pumpAndSettle();
      expect(heroMember(tester), same(first));
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );
}
