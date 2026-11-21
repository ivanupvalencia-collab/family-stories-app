import 'dart:async';

import 'package:family_stories_app/services/auth_service.dart';
import 'package:family_stories_app/services/auth_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

// S-10: gotrue reports refresh failures (offline device, revoked token) as
// errors on `onAuthStateChange`. These tests prove both supported entry points
// report the error without forwarding it to the listener and without losing
// the events that follow it — a flaky network must not break the app or the
// auth state.
void main() {
  test('authUserChanges swallows stream errors and keeps delivering events',
      () async {
    final source = StreamController<AuthState>();
    final received = <AuthUser?>[];
    var listenerErrors = 0;

    final subscription = authUserChanges(
      source.stream,
      (_) => null,
    ).listen(
      received.add,
      onError: (_) => listenerErrors++,
    );

    source.add(const AuthState(AuthChangeEvent.signedIn, null));
    await pumpEventQueue();
    source.addError(Exception('refresh failed'));
    await pumpEventQueue();
    source.add(const AuthState(AuthChangeEvent.signedOut, null));
    await pumpEventQueue();

    expect(listenerErrors, 0, reason: 'the error must never reach the listener');
    expect(received, hasLength(2), reason: 'events after the error still arrive');

    await subscription.cancel();
    await source.close();
  });

  test('listenAuthSafely reports errors without unhandled exceptions',
      () async {
    final source = StreamController<AuthState>();
    final received = <AuthState>[];
    Object? uncaught;

    final subscription = runZonedGuarded<StreamSubscription<AuthState>>(
      () => listenAuthSafely(source.stream, received.add),
      (error, _) => uncaught = error,
    )!;

    source.add(const AuthState(AuthChangeEvent.signedIn, null));
    await pumpEventQueue();
    source.addError(Exception('refresh failed'));
    await pumpEventQueue();
    source.add(const AuthState(AuthChangeEvent.signedOut, null));
    await pumpEventQueue();

    expect(uncaught, isNull, reason: 'no unhandled exception may escape');
    expect(
      received.map((state) => state.event),
      [AuthChangeEvent.signedIn, AuthChangeEvent.signedOut],
      reason: 'events after the error still arrive',
    );

    await subscription.cancel();
    await source.close();
  });
}
