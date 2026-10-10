import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_stories_app/services/family_member_deletion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _login(SupabaseClient client, String id) => client.auth
    .recoverSession(
      jsonEncode({
        'access_token': 'test-$id',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': id,
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-10-10T12:00:00Z',
        },
      }),
    )
    .then((_) {});

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseFamilyMemberDeletionService service;
  final calls = <String>[];
  List<Map<String, String>> resources = [];
  String owner = 'ivan';
  String? failBucket;
  bool missing = false, phantom = false, finishFailure = false;
  int prepareCalls = 0, finishCalls = 0;
  Completer<void>? gate;

  setUp(() async {
    calls.clear();
    resources = [
      {'bucket': 'family-member-photos', 'path': 'ivan/member/photo.png'},
      {'bucket': 'story-photos', 'path': 'pepe/story/photo.png'},
      {'bucket': 'story-audio', 'path': 'request/actual-response.m4a'},
    ];
    owner = 'ivan';
    failBucket = null;
    missing = phantom = finishFailure = false;
    prepareCalls = finishCalls = 0;
    gate = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final path = request.uri.path;
      calls.add(path);
      request.response.headers.contentType = ContentType.json;
      final account = request.headers.value('authorization');
      if (path.endsWith('/prepare_family_member_delete')) {
        prepareCalls++;
        expect(jsonDecode(body), {'p_family_member_id': 'member'});
        if (account != 'Bearer test-$owner') {
          request.response.statusCode = 403;
          request.response.write(
            '{"code":"42501","message":"Only the family owner may delete"}',
          );
        } else {
          await gate?.future;
          request.response.write(
            jsonEncode({
              'resources': resources,
              'story_ids': ['story'],
            }),
          );
        }
      } else if (request.method == 'DELETE') {
        final bucket = path.split('/').last;
        expect((jsonDecode(body) as Map)['prefixes'], [
          resources.singleWhere((r) => r['bucket'] == bucket)['path'],
        ]);
        if (bucket == failBucket || missing) {
          request.response.statusCode = missing ? 404 : 403;
          request.response.write(
            jsonEncode({
              'statusCode': missing ? '404' : '403',
              'error': missing ? 'Not found' : 'Forbidden',
              'message': 'Storage failure',
            }),
          );
        } else {
          // An empty remove result is not proof of cleanup. finish checks DB.
          request.response.write('[]');
        }
      } else if (path.endsWith('/finish_family_member_delete')) {
        finishCalls++;
        expect(jsonDecode(body), {'p_family_member_id': 'member'});
        if (phantom || finishFailure) {
          request.response.statusCode = 409;
          request.response.write(
            '{"code":"55000","message":"Storage cleanup incomplete"}',
          );
        } else {
          request.response.write('null');
        }
      } else {
        request.response.write('{}');
      }
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await _login(client, 'ivan');
    service = SupabaseFamilyMemberDeletionService(
      client: client,
      enabled: true,
    );
  });
  tearDown(() async {
    gate?.complete();
    await client.dispose();
    await server.close(force: true);
  });
  Future<FamilyMemberDeletionPlan> remove({String account = 'ivan'}) =>
      service.delete(ownerId: account, familyMemberId: 'member');

  test(
    'remote deletion is enabled by default after SQL installation confirmation',
    () async {
      final enabled = SupabaseFamilyMemberDeletionService(client: client);
      expect(enabled.enabled, isTrue);
      await enabled.delete(ownerId: 'ivan', familyMemberId: 'member');
      expect(finishCalls, 1);
    },
  );
  test(
    'owner: exact server paths, private Storage API then final CASCADE RPC',
    () async {
      final plan = await remove();
      expect(plan.resources, hasLength(3));
      expect(plan.storyIds, ['story']);
      expect(calls.first, endsWith('/prepare_family_member_delete'));
      expect(calls.last, endsWith('/finish_family_member_delete'));
      expect(calls.where((c) => c.contains('/storage/')), hasLength(3));
      expect(calls.where((c) => c.endsWith('/family_members')), isEmpty);
    },
  );
  for (final account in ['outsider', 'pepe-linked-recorder']) {
    test(
      '$account is rejected by owner RPC before Storage or DB deletion',
      () async {
        await _login(client, account);
        await expectLater(
          remove(account: account),
          throwsA(isA<PostgrestException>()),
        );
        expect(calls, hasLength(1));
        expect(finishCalls, 0);
      },
    );
  }
  test('mismatched client owner/session never reaches RPC', () async {
    await expectLater(remove(account: 'pepe'), throwsStateError);
    expect(calls, isEmpty);
  });
  test('no photos or audio still finalizes', () async {
    resources = [];
    expect((await remove()).resources, isEmpty);
    expect(calls, hasLength(2));
  });
  test('audio only preserves its actual request path', () async {
    resources = resources.where((r) => r['bucket'] == 'story-audio').toList();
    await remove();
    expect(calls, hasLength(3));
  });
  test('already absent files are clean', () async {
    missing = true;
    await remove();
    expect(finishCalls, 1);
  });
  test(
    'partial Storage failure never finalizes; retry uses full durable plan',
    () async {
      failBucket = 'story-photos';
      await expectLater(remove(), throwsA(isA<StorageException>()));
      expect(finishCalls, 0);
      expect(calls.where((c) => c.endsWith('/story-audio')), isEmpty);
      failBucket = null;
      await remove();
      expect(prepareCalls, 2);
      expect(finishCalls, 1);
    },
  );
  test(
    'RLS silently filtering remove is caught by final verification',
    () async {
      phantom = true;
      await expectLater(remove(), throwsA(isA<PostgrestException>()));
      expect(finishCalls, 1);
    },
  );
  test('final RPC error is retryable and never reported as success', () async {
    finishFailure = true;
    await expectLater(remove(), throwsA(isA<PostgrestException>()));
    finishFailure = false;
    await remove();
    expect(finishCalls, 2);
  });
  test('double submission runs only one deletion', () async {
    gate = Completer<void>();
    final pending = remove();
    await expectLater(remove(), throwsStateError);
    gate!.complete();
    gate = null;
    await pending;
    expect(prepareCalls, 1);
    expect(finishCalls, 1);
  });
  test(
    'account changes during preparation prevent Storage and final deletion',
    () async {
      gate = Completer<void>();
      final pending = remove();
      final assertion = expectLater(pending, throwsStateError);
      while (prepareCalls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await _login(client, 'pepe');
      gate!.complete();
      gate = null;
      await assertion;
      expect(finishCalls, 0);
      expect(calls.where((c) => c.contains('/storage/')), isEmpty);
    },
  );
}
