import 'dart:typed_data';

import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/models/question_request.dart';
import 'package:family_stories_app/models/user_profile.dart';
import 'package:family_stories_app/services/family_member_photo_service.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/services/received_request_details_service.dart';
import 'package:family_stories_app/services/visible_account_avatar_service.dart';
import 'package:family_stories_app/widgets/account_avatar_view.dart';
import 'package:family_stories_app/widgets/aritoria_home_view.dart';
import 'package:family_stories_app/widgets/family_member_photo_view.dart';
import 'package:family_stories_app/widgets/profile_avatar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

class _Avatars extends VisibleAccountAvatarService {
  UserProfile? profile = const UserProfile(
    id: 'linked',
    name: 'Claudia',
    avatarKey: 'avatar_01',
  );
  final loads = <String>[];
  bool fail = false;
  @override
  UserProfile? cached(String accountId) => profile;
  @override
  Future<UserProfile?> load(String accountId) async {
    loads.add(accountId);
    if (fail) throw StateError('RPC not installed');
    return profile;
  }
}

class _Photos extends FamilyMemberPhotoService {
  bool fail = false;
  final loads = <String?>[];
  @override
  Future<Uint8List> load(FamilyMember member) async {
    loads.add(member.photoPath);
    if (fail) throw StateError('missing own image');
    return fixtures.testPickedImage.bytes;
  }

  @override
  Future<FamilyMember> save(
    FamilyMember member,
    PickedProfileImage? image,
  ) async => member;
}

const _member = FamilyMember(
  id: 'member',
  name: 'Pepe',
  relationship: 'Padre/Madre',
  linkedAccountId: 'linked',
);

void main() {
  testWidgets(
    'uploaded avatar URL is reused and broken network image shows sender initial',
    (tester) async {
      final avatars = _Avatars()
        ..profile = const UserProfile(
          id: 'sender-user-id',
          name: 'Claudia',
          avatarUrl: 'https://example.test/avatar.png?v=2',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceivedRequestRow(
              request: fixtures.testQuestionRequest(
                id: 'q',
                recipientId: 'recipient',
                questionText: 'Pregunta',
              ),
              avatarService: avatars,
              onTap: () {},
            ),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as NetworkImage).url,
        'https://example.test/avatar.png?v=2',
      );
      expect(image.fit, BoxFit.cover);
      // Test binding returns HTTP 400: errorBuilder must render a safe initial.
      await tester.pumpAndSettle();
      expect(find.text('C'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );

  testWidgets(
    'unlinked member preserves its fallback without requesting a profile',
    (tester) async {
      final avatars = _Avatars();
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyMemberPhotoView(
            member: const FamilyMember(
              id: 'local',
              name: 'Ana',
              relationship: 'Abuelo/a',
            ),
            photoService: _Photos(),
            avatarService: avatars,
            fallback: const Text('Original'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(avatars.loads, isEmpty);
      expect(find.text('Original'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );

  testWidgets(
    'own photo and preview take priority without looking up linked avatar',
    (tester) async {
      final avatars = _Avatars();
      final photos = _Photos();
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyMemberPhotoView(
            member: _member.withPhotoPath('private/own.png'),
            photoService: photos,
            avatarService: avatars,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(avatars.loads, isEmpty);
      expect(find.byType(AccountAvatarView), findsNothing);
      expect(photos.loads, ['private/own.png']);
      final image =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect(image.imageProvider, isA<MemoryImage>());
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyMemberPhotoView(
            member: _member,
            photoService: photos,
            avatarService: avatars,
            previewBytes: fixtures.testPickedImage.bytes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(avatars.loads, isEmpty);
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );

  testWidgets(
    'linked avatar works in rectangular hero, own reference stays null',
    (tester) async {
      final avatars = _Avatars();
      final photos = _Photos();
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyMemberPhotoView(
            member: _member,
            photoService: photos,
            avatarService: avatars,
            circular: false,
            width: 300,
            height: 240,
          ),
        ),
      );
      final view = tester.widget<ProfileAvatarView>(
        find.byType(ProfileAvatarView),
      );
      expect(view.avatarKey, 'avatar_01');
      expect(view.circular, isFalse);
      expect(view.width, 300);
      expect(view.height, 240);
      await tester.pumpAndSettle();
      expect(avatars.loads, ['linked']);
      expect(photos.loads, isEmpty);
      expect(_member.photoPath, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );

  testWidgets(
    'absent avatar or unavailable RPC preserves member fallback; broken own photo never switches to account avatar',
    (tester) async {
      final avatars = _Avatars()
        ..profile = null
        ..fail = true;
      final photos = _Photos()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyMemberPhotoView(
            member: _member,
            photoService: photos,
            avatarService: avatars,
            fallback: const Text('Original fallback'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original fallback'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyMemberPhotoView(
            member: _member.withPhotoPath('broken.png'),
            photoService: photos,
            avatarService: avatars,
            fallback: const Text('Original fallback'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(avatars.loads, ['linked']);
      expect(find.byType(AccountAvatarView), findsNothing);
      expect(find.text('Original fallback'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );

  testWidgets(
    'pending row uses sender account, initial, subtitle, chevron and existing tap',
    (tester) async {
      final avatars = _Avatars()
        ..profile = const UserProfile(id: 'sender', name: 'Claudia');
      var taps = 0;
      final request = fixtures.testQuestionRequest(
        id: 'pending',
        recipientId: 'recipient',
        questionText: '¿Cuál fue tu primer trabajo?',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceivedRequestRow(
              request: request,
              avatarService: avatars,
              details: const ReceivedRequestDetails(senderName: 'Claudia'),
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(avatars.loads, ['sender-user-id']);
      expect(find.text('C'), findsOneWidget);
      expect(find.textContaining('De Claudia'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      await tester.tap(find.byType(ListTile));
      expect(taps, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceivedRequestRow(
              request: fixtures.testQuestionRequest(
                id: 'answered',
                recipientId: 'recipient',
                questionText: 'Already answered',
                status: QuestionRequestStatus.answered,
              ),
              avatarService: avatars,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AccountAvatarView), findsNothing);
      expect(avatars.loads, ['sender-user-id']);
      await tester.pumpWidget(const SizedBox());
      avatars.dispose();
    },
  );

  testWidgets('cleared account cache immediately hides previous avatar', (
    tester,
  ) async {
    final avatars = _Avatars();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAvatarView(
          accountId: 'linked',
          service: avatars,
          fallback: const Text('Hidden'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    avatars.profile = null;
    avatars.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Hidden'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    avatars.dispose();
  });
}
