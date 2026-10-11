import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_stories_app/services/visible_account_avatar_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseVisibleAccountAvatarService service;
  late List<({String path, String? authorization, List<dynamic> ids})> requests;
  Completer<void>? gate;
  var fail = false;

  Future<void> signIn(String id) => client.auth
      .recoverSession(
        jsonEncode({
          'access_token': 'test-user-token',
          'refresh_token': 'test-refresh-token',
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

  setUp(() async {
    requests = [];
    gate = null;
    fail = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path.startsWith('/auth/')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
        return;
      }
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      final ids = body['p_account_ids'] as List;
      requests.add((
        path: request.uri.path,
        authorization: request.headers.value('authorization'),
        ids: ids,
      ));
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
            for (final id in ids.where((id) => id != 'hidden'))
              {
                'id': id,
                'name': 'Claudia',
                'avatar_key': 'avatar_01',
                'avatar_url': 'https://example.test/avatar.png',
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
    await signIn('11111111-1111-4111-8111-111111111111');
    service = SupabaseVisibleAccountAvatarService(client: client);
  });

  tearDown(() async {
    service.dispose();
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'authenticated bounded RPC, coalesced loads, shared cached metadata',
    () async {
      final profiles = await Future.wait([
        service.load('sender'),
        service.load('sender'),
      ]);
      expect(requests.length, 1);
      expect(requests.single.path, '/rest/v1/rpc/get_visible_account_avatars');
      expect(requests.single.ids, ['sender']);
      expect(requests.single.authorization, 'Bearer test-user-token');
      expect(profiles.first!.avatarUrl, 'https://example.test/avatar.png');
      expect(service.cached('sender'), same(profiles.first));
      await service.load('sender');
      expect(requests.length, 1);
    },
  );

  test('unauthorized/missing profile is null; RPC failure can retry', () async {
    expect(await service.load('hidden'), isNull);
    expect(service.cached('hidden'), isNull);
    fail = true;
    await expectLater(service.load('new'), throwsA(isA<PostgrestException>()));
    fail = false;
    expect(await service.load('new'), isNotNull);
  });

  test(
    'switching accounts invalidates cache and discards in-flight response',
    () async {
      await service.load('cached');
      gate = Completer<void>();
      final pending = service.load('slow');
      while (requests.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await signIn('22222222-2222-4222-8222-222222222222');
      expect(service.cached('cached'), isNull);
      gate!.complete();
      expect(await pending, isNull);
      expect(service.cached('slow'), isNull);
      expect(await service.load('cached'), isNotNull);
      expect(requests.length, 3);
    },
  );

  test(
    'signout clears cache and guest never requests account metadata',
    () async {
      await service.load('cached');
      await client.auth.signOut(scope: SignOutScope.local);
      expect(service.cached('cached'), isNull);
      expect(await service.load('cached'), isNull);
      expect(requests.length, 1);
    },
  );
}
