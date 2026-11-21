import 'dart:typed_data';

import 'package:family_stories_app/domain/add_family_member.dart';
import 'package:family_stories_app/domain/app_failure.dart';
import 'package:family_stories_app/domain/delete_family_member.dart';
import 'package:family_stories_app/domain/submit_answer.dart';
import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/services/family_member_deletion_service.dart';
import 'package:family_stories_app/services/family_member_photo_service.dart';
import 'package:family_stories_app/services/family_story_service.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/services/story_photo_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

class _Photos implements StoryPhotoService {
  _Photos([this.error]);
  final Object? error;
  final List<String> savedStoryIds = [];
  final List<String> forgottenStoryPaths = [];

  @override
  Future<FamilyStory> save(FamilyStory story, PickedProfileImage? image) async {
    if (error != null) throw error!;
    savedStoryIds.add(story.id);
    return story;
  }

  @override
  Future<void> forgetPhotos(String account, Iterable<String> paths) async {
    forgottenStoryPaths.addAll(paths);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError();
}

class _MemberPhotos implements FamilyMemberPhotoService {
  final List<String> forgottenMemberPaths = [];

  @override
  Future<FamilyMember> save(FamilyMember member, PickedProfileImage? image) async =>
      member;

  @override
  Future<void> forgetPhotos(String account, Iterable<String> paths) async {
    forgottenMemberPaths.addAll(paths);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError();
}

class _Stories implements FamilyStoryService {
  final audioCacheClears = <int>[];

  @override
  Future<void> clearAudioCache() async => audioCacheClears.add(1);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError();
}

class _Deletion implements FamilyMemberDeletionService {
  @override
  bool get enabled => true;

  @override
  Future<FamilyMemberDeletionPlan> delete({
    required String ownerId,
    required String familyMemberId,
  }) async => FamilyMemberDeletionPlan.fromJson(const {
    'resources': [
      {'bucket': 'family-member-photos', 'path': 'owner/m/portrait.png'},
      {'bucket': 'story-photos', 'path': 'owner/story/photo.png'},
      {'bucket': 'story-audio', 'path': 'request/audio.m4a'},
    ],
    'story_ids': <String>[],
  });
}

final _request = fixtures.testQuestionRequest(
  id: 'request-1',
  recipientId: 'recipient',
  questionText: '¿Cuál es tu primer recuerdo?',
  createdAt: DateTime(2026, 10, 4),
);

final _photo = PickedProfileImage(
  bytes: Uint8List.fromList([1, 2, 3]),
  contentType: 'image/png',
);

void main() {
  test('a failed completion rolls the uploaded answer audio back (A-1)',
      () async {
    final requests = fixtures.FakeQuestionRequestService(
      completionError: StateError('rpc'),
    );
    final result = await SubmitAnswer(questionRequests: requests)(
      request: _request,
      audioPath: '/tmp/answer.m4a',
      duration: const Duration(seconds: 12),
      photo: null,
    );
    // The upload happened, the RPC failed, and the compensating delete
    // removed exactly the uploaded object.
    expect(requests.uploadedObjectPaths, hasLength(1));
    expect(
      requests.deletedObjectPaths,
      requests.uploadedObjectPaths,
      reason: 'A-1: the failed answer left its audio behind.',
    );
    expect(result.failure, isA<Unavailable>());
    expect(result.photoAttached, isTrue);
  });

  test('a photo failure never discards a committed answer (A-1)', () async {
    final requests = fixtures.FakeQuestionRequestService(
      answerStories: {
        'request-1': FamilyStory(
          id: 'story-1',
          familyMemberId: 'member',
          question: _request.questionText,
          audioPath: 'request-1/answer.m4a',
          duration: const Duration(seconds: 12),
          createdAt: DateTime(2026, 10, 4),
        ),
      },
    );
    final result = await SubmitAnswer(
      questionRequests: requests,
      photos: _Photos(StateError('upload')),
    )(
      request: _request,
      audioPath: '/tmp/answer.m4a',
      duration: const Duration(seconds: 12),
      photo: _photo,
    );
    expect(result.failure, isNull);
    expect(
      result.photoAttached,
      isFalse,
      reason: 'A-1: a soft photo failure was reported as committed.',
    );
    // Nothing was rolled back: the answer stands.
    expect(requests.deletedObjectPaths, isEmpty);
  });

  test('a failed creation reports a failure and saves nothing (A-1)', () async {
    final members = fixtures.FakeFamilyMemberService(
      createError: StateError('rpc'),
    );
    final result = await AddFamilyMember(
      members: members,
      photos: _MemberPhotos(),
      localStorage: fixtures.MemoryFamilyMemberStorage(),
    )(
      member: const FamilyMember(
        id: 'new-member',
        name: 'Nieto/a',
        relationship: 'Nieto/a',
      ),
      ownerId: 'owner',
      photo: null,
    );
    expect(result.failure, isA<Unavailable>());
    expect(result.saved, isNull);
  });

  test('deletion clears the member cache, both photo trees and audio (A-1)',
      () async {
    final photos = _MemberPhotos();
    final storyPhotos = _Photos();
    final stories = _Stories();
    final failure = await DeleteFamilyMember(
      deletion: _Deletion(),
      photos: photos,
      storyPhotos: storyPhotos,
      remoteStories: stories,
      memberCache: null,
    )(
      ownerId: 'owner',
      member: const FamilyMember(
        id: 'member-1',
        name: 'Usuario B',
        relationship: 'Padre/Madre',
      ),
    );
    expect(failure, isNull);
    expect(photos.forgottenMemberPaths, ['owner/m/portrait.png']);
    expect(storyPhotos.forgottenStoryPaths, ['owner/story/photo.png']);
    expect(stories.audioCacheClears, [1]);
  });
}
