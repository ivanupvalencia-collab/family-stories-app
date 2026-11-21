import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_stories_app/services/received_request_details_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseReceivedRequestDetailsService service;
  late List<({String path, String? authorization, List<dynamic> ids})> requests;
  var fail = false;
  Completer<void>? gate;

  setUp(() async {
    requests = [];
    fail = false;
    gate = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      final ids = body['p_request_ids'] as List;
      requests.add((
        path: request.uri.path,
        authorization: request.headers.value('authorization'),
        ids: ids,
      ));
      // C-10: hold the response until the test releases the gate, so a
      // sequential implementation would deadlock instead of passing.
      await gate?.future;
      request.response.headers.contentType = ContentType.json;
      if (fail) {
        request.response.statusCode = 404;
        request.response.write(
          jsonEncode({'code': 'PGRST202', 'message': 'RPC not installed'}),
        );
      } else {
        request.response.write(
          jsonEncode([
            for (final id in ids)
              {
                'request_id': id,
                'sender_name': id == 'unnamed' ? '  ' : ' Usuario A ',
                'duration_seconds': id == 'unnamed' ? null : 75,
              },
          ]),
        );
      }
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-user-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': '11111111-1111-4111-8111-111111111111',
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-10-10T12:00:00Z',
        },
      }),
    );
    service = SupabaseReceivedRequestDetailsService(client: client);
  });
  tearDown(() async {
    if (gate != null && !gate!.isCompleted) gate!.complete();
    await client.dispose();
    await server.close(force: true);
  });

  test('only requests bounded authenticated RPC metadata, not profiles or stories tables', () async {
    final details = await service.load(['answered', 'unnamed', 'answered']);
    expect(requests.single.path, '/rest/v1/rpc/get_received_request_details');
    expect(requests.single.authorization, 'Bearer test-user-token');
    expect(requests.single.ids, ['answered', 'unnamed']);
    expect(details['answered']!.senderName, 'Usuario A');
    expect(details['answered']!.durationSeconds, 75);
    expect(details['unnamed']!.senderName, isNull);
    expect(details['unnamed']!.durationSeconds, isNull);
  });

  test(
    'batches histories longer than the RPC limit without dropping requests',
    () async {
      final ids = List.generate(201, (index) => '$index');
      final details = await service.load(ids);
      // C-10: chunks fly in parallel, so arrival order is not guaranteed.
      final sizes = requests.map((request) => request.ids.length).toList()
        ..sort();
      expect(sizes, [1, 100, 100]);
      expect(details.keys.toSet(), ids.toSet());
      expect(details.length, 201);
    },
  );

  test('chunks are requested concurrently (C-10)', () async {
    gate = Completer<void>();
    final ids = List.generate(250, (index) => '$index');
    final pending = service.load(ids);
    // The sequential implementation would never reach this point: it sends
    // one chunk at a time and blocks on the first gated response.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (requests.length < 3 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      requests,
      hasLength(3),
      reason: 'Chunks not in flight at once: the loop is sequential (C-10).',
    );
    gate!.complete();
    gate = null;
    final details = await pending;
    expect(details.length, 250);
    expect(details.keys.toSet(), ids.toSet());
  });

  test('missing manual RPC propagates for the optional UI fallback', () async {
    fail = true;
    await expectLater(
      service.load(['answer']),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('empty input needs no RPC or Supabase initialization', () async {
    expect(await SupabaseReceivedRequestDetailsService().load([]), isEmpty);
    expect(requests, isEmpty);
  });
}
