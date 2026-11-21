import 'dart:convert';

import 'package:family_stories_app/services/session_monitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _login(SupabaseClient client, String id) => client.auth
    .recoverSession(
      jsonEncode({
        'access_token': 'test-token-$id',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': id,
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-10-18T12:00:00Z',
        },
      }),
    )
    .then((_) {});

void main() {
  test('one fan-out subscription serves every registered callback (A-4)',
      () async {
    final client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    final monitor = SessionMonitor(client);
    var first = 0;
    var second = 0;
    final detachFirst = monitor.onAuthState((_) => first++);
    monitor.onAuthState((_) => second++);

    await _login(client, 'owner');
    expect(first, greaterThan(0));
    expect(second, greaterThan(0));

    // A detached callback must never fire again.
    detachFirst();
    final detached = first;
    await _login(client, 'other');
    expect(second, greaterThan(detached));
    expect(
      first,
      detached,
      reason: 'A-4: the detached callback still fired.',
    );

    // Disposing the monitor cancels the single shared subscription.
    monitor.dispose();
    final afterDispose = second;
    await _login(client, 'third');
    expect(
      second,
      afterDispose,
      reason: 'A-4: the monitor kept listening after dispose.',
    );
  });
}
