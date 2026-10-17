import 'dart:typed_data';

import 'package:family_stories_app/design/aritoria_design.dart';

import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/models/question_request.dart';
import 'package:family_stories_app/services/family_member_photo_service.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/services/received_request_details_service.dart';
import 'package:family_stories_app/services/story_photo_service.dart';
import 'package:family_stories_app/widgets/aritoria_home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

class _Photos extends StoryPhotoService {
  final loaded = <String>[];
  @override
  Future<Uint8List> load(FamilyStory story) async {
    loaded.add(story.id);
    return fixtures.testPickedImage.bytes;
  }

  @override
  Future<bool> canEdit(FamilyStory story) async => false;
  @override
  Future<FamilyStory> save(FamilyStory story, PickedProfileImage? image) =>
      throw UnimplementedError();
}

void main() {
  for (final metadataError in [false, true]) {
    testWidgets(
      'Home answers show photo/play, two rows and existing callbacks; metadata error=$metadataError',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final answers = [
          for (var i = 0; i < 3; i++)
            fixtures.testQuestionRequest(
              id: 'answer-$i',
              recipientId: 'recipient',
              status: QuestionRequestStatus.answered,
              questionText: 'Historia $i',
              answeredAt: DateTime.utc(2026, 10, 17),
            ),
        ];
        final stories = {
          for (var i = 0; i < 2; i++)
            answers[i].id: FamilyStory(
              id: 'story-$i',
              familyMemberId: answers[i].familyMemberId,
              question: answers[i].questionText,
              audioPath: 'private/audio.m4a',
              duration: const Duration(seconds: 65),
              createdAt: DateTime.utc(2026),
              photoPath: i == 0 ? 'private/story-$i/photo.png' : null,
            ),
        };
        final service = fixtures.FakeQuestionRequestService(
          answerStories: stories,
          answerStoryError: metadataError
              ? StateError('metadata unavailable')
              : null,
        );
        final photos = _Photos();
        final opened = <String>[];
        var all = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AritoriaHomeView(
                members: const [],
                photos: LocalFamilyMemberPhotoService(
                  storage: fixtures.MemoryFamilyMemberStorage(),
                ),
                profile: null,
                authenticated: true,
                questions: [
                  fixtures.testQuestionRequest(
                    id: 'pending',
                    recipientId: 'recipient',
                    questionText: 'Pregunta pendiente',
                  ),
                ],
                answers: answers,
                answerService: service,
                storyPhotos: photos,
                details: {
                  for (final request in answers)
                    request.id: const ReceivedRequestDetails(
                      senderName: 'Iván',
                      durationSeconds: 65,
                    ),
                },
                memberStatus: null,
                questionStatus: null,
                answerStatus: null,
                onRefresh: () async {},
                onNotifications: () {},
                onAdd: () {},
                onMember: (_) {},
                onHero: (_) {},
                onAllMembers: () {},
                onAllQuestions: () {},
                onAllAnswers: () => all++,
                onQuestion: (_) {},
                onAnswer: (request) => opened.add(request.id),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(service.requestedAnswerStoryIds, ['answer-0', 'answer-1']);
        expect(find.text('Historia 2'), findsNothing);
        expect(find.text('Para Iván · 17/10/2026 · 1:05'), findsNWidgets(2));
        final rows = find.byType(ReceivedRequestRow);
        expect(rows, findsNWidgets(3));
        final questionTile = tester.widget<ListTile>(
          find.descendant(of: rows.first, matching: find.byType(ListTile)),
        );
        final avatarSize = tester.getSize(find.byWidget(questionTile.leading!));
        final questionStart = tester
            .getTopLeft(find.text('Pregunta pendiente'))
            .dx;
        final photoRow = rows.at(1);
        for (final row in [photoRow, rows.last]) {
          final tile = tester.widget<ListTile>(
            find.descendant(of: row, matching: find.byType(ListTile)),
          );
          expect(tester.getSize(find.byWidget(tile.leading!)), avatarSize);
          expect(
            tester.getTopLeft(find.byWidget(tile.title!)).dx,
            questionStart,
          );
          expect((tile.trailing as Icon).icon, Icons.chevron_right);
        }
        expect(photos.loaded, metadataError ? isEmpty : ['story-0']);
        final fallback = find.descendant(
          of: rows.last,
          matching: find.byKey(const ValueKey('home-story-no-photo')),
        );
        expect(tester.getSize(fallback), const Size(48, 48));
        final decoration =
            tester.widget<DecoratedBox>(fallback).decoration as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(10));
        expect(decoration.color, AritoriaColors.sage.withValues(alpha: .18));
        final play = tester.widget<Icon>(
          find.descendant(of: fallback, matching: find.byType(Icon)),
        );
        expect(play.icon, Icons.play_arrow_rounded);
        expect(play.color, AritoriaColors.olive);
        expect(
          find.descendant(of: rows.last, matching: find.byType(CircleAvatar)),
          findsNothing,
        );
        if (!metadataError) {
          final image = find.descendant(
            of: photoRow,
            matching: find.byType(Image),
          );
          expect(image, findsOneWidget);
          expect(tester.widget<Image>(image).fit, BoxFit.cover);
          final clip = find.descendant(
            of: photoRow,
            matching: find.byType(ClipRRect),
          );
          expect(
            tester.widget<ClipRRect>(clip).borderRadius,
            BorderRadius.circular(10),
          );
        }
        await tester.tap(find.text('Historia 0'));
        expect(opened, ['answer-0']);
        await tester.tap(find.text('Ver todas').last);
        expect(all, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
