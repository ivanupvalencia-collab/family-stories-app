import 'dart:convert';
import 'dart:io';

import 'package:family_stories_app/models/question_request.dart';
import 'package:family_stories_app/services/question_request_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseQuestionRequestService service;
  late List<({Uri uri, String method, String body, String? authorization})>
  requests;
  dynamic response;
  late int status;
  final storyJson = {
    'id': 'story-id',
    'family_member_id': 'family-id',
    'question': 'Mi respuesta',
    'audio_path': 'request-id/exact-upload.m4a',
    'duration_seconds': 12,
    'created_at': '2026-10-05T12:00:00Z',
    'question_request_id': 'request-id',
    'recorded_by': 'recipient-id',
  };

  setUp(() async {
    requests = [];
    response = null;
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add((
        uri: request.uri,
        method: request.method,
        body: await utf8.decoder.bind(request).join(),
        authorization: request.headers.value('authorization'),
      ));
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-anon-key',
      accessToken: () async => 'test-user-token',
    );
    service = SupabaseQuestionRequestService(client: client);
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'answered list filters recipient/status and orders answered_at descending',
    () async {
      response = [
        {
          'id': 'request-id',
          'sender_id': 'sender-id',
          'recipient_id': 'recipient-id',
          'family_member_id': 'family-id',
          'question_text': 'Mi respuesta',
          'status': 'answered',
          'created_at': '2026-10-04T12:00:00Z',
          'answered_at': '2026-10-05T12:00:00Z',
        },
        {
          'id': 'legacy-request',
          'sender_id': 'sender-id',
          'recipient_id': 'recipient-id',
          'family_member_id': 'family-id',
          'question_text': 'Sin fecha',
          'status': 'answered',
          'created_at': '2026-10-03T12:00:00Z',
          'answered_at': null,
        },
      ];
      final answers = await service.loadAnsweredForRecipient('recipient-id');
      final request = requests.single;
      expect(request.uri.path, '/rest/v1/question_requests');
      expect(request.uri.queryParameters['recipient_id'], 'eq.recipient-id');
      expect(request.uri.queryParameters['status'], 'eq.answered');
      expect(
        request.uri.queryParameters['order'],
        'answered_at.desc.nullslast,created_at.desc.nullslast',
      );
      expect(request.authorization, 'Bearer test-user-token');
      expect(answers.first.status, QuestionRequestStatus.answered);
      expect(answers.first.answeredAt, DateTime.utc(2026, 10, 5, 12));
      expect(answers.last.answeredAt, isNull);
      expect(answers.map((a) => a.id), ['request-id', 'legacy-request']);
    },
  );

  test(
    'loads exact metadata via authenticated RPC without SELECT on stories',
    () async {
      response = storyJson;
      final story = await service.loadAnswerStory('request-id');
      final request = requests.single;
      expect(request.uri.path, '/rest/v1/rpc/get_my_answer_story');
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {'p_question_request_id': 'request-id'});
      expect(request.authorization, 'Bearer test-user-token');
      expect(story!.id, 'story-id');
      expect(story.audioPath, 'request-id/exact-upload.m4a');
      expect(story.duration, const Duration(seconds: 12));
      expect(story.questionRequestId, 'request-id');
      expect(story.recordedBy, 'recipient-id');
    },
  );

  test(
    'null RPC result does not fabricate a story or guess its audio path',
    () async {
      expect(await service.loadAnswerStory('unavailable-request'), isNull);
      expect(requests, hasLength(1));
    },
  );

  test(
    'missing RPC propagates its error and never falls back to stories',
    () async {
      status = 404;
      response = {
        'code': 'PGRST202',
        'message': 'Could not find the function public.get_my_answer_story',
        'details': null,
        'hint': null,
      };
      await expectLater(
        service.loadAnswerStory('request-id'),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', 'PGRST202'),
        ),
      );
      expect(requests, hasLength(1));
      expect(requests.single.uri.path, '/rest/v1/rpc/get_my_answer_story');
    },
  );
}
