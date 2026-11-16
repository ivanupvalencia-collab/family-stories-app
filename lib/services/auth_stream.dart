import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// S-10: gotrue reports refresh failures (device offline, revoked token) as
// errors on `onAuthStateChange`. Any listener without its own `onError` turns
// that into an unhandled exception. These helpers are the supported way to
// subscribe: the error is reported, never rethrown, and the auth state is
// deliberately untouched — a flaky network must neither log the user out nor
// fake a session.
void handleAuthStreamError(Object error, StackTrace stackTrace) {
  debugPrint('Auth stream error (session unchanged): $error');
}

StreamSubscription<AuthState> listenAuthSafely(
  Stream<AuthState> source,
  void Function(AuthState state) onData,
) => source.listen(onData, onError: handleAuthStreamError);
