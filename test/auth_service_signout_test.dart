import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_stories_app/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalHttpOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = null);
  tearDown(() => HttpOverrides.global = originalHttpOverrides);

  late HttpServer server;
  late SupabaseClient client;
  late SupabaseGoogleAuthService service;
  late int logoutStatus;
  late List<AuthChangeEvent> events;
  late StreamSubscription<AuthState> subscription;

  setUp(() async {
    logoutStatus = 200;
    events = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode =
          request.uri.path == '/auth/v1/logout' ? logoutStatus : 404;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'message': 'test'}));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': 'owner',
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-11-12T10:00:00Z',
        },
      }),
    );
    subscription = client.auth.onAuthStateChange.listen(
      (state) => events.add(state.event),
    );
    service = SupabaseGoogleAuthService(client: client);
  });

  tearDown(() async {
    await subscription.cancel();
    await client.dispose();
    await server.close(force: true);
  });

  test('el cierre exitoso remueve la sesión y notifica signedOut', () async {
    await service.signOut();
    expect(client.auth.currentSession, isNull);
    expect(events, contains(AuthChangeEvent.signedOut));
  });

  test(
    'un fallo del servidor no deja la sesión viva ni rompe el cierre (S-7)',
    () async {
      logoutStatus = 500;
      await service.signOut(); // Best effort: the local session is already gone.
      expect(client.auth.currentSession, isNull);
      // Without this guarantee the caches of S-6 would never purge.
      expect(events, contains(AuthChangeEvent.signedOut));
    },
  );
}
