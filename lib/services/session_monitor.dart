import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_stream.dart';

/// A-4: one auth subscription for the whole service graph. Services
/// register callbacks here instead of subscribing to `onAuthStateChange`
/// individually, so the S-10 error guarantee and the disposal live in a
/// single place and no constructor can leak a listener again.
class SessionMonitor {
  SessionMonitor(SupabaseClient client) {
    _subscription = listenAuthSafely(client.auth.onAuthStateChange, (state) {
      for (final callback in List.of(_callbacks)) {
        callback(state);
      }
    });
  }

  late final StreamSubscription<AuthState> _subscription;
  final _callbacks = <void Function(AuthState)>[];

  /// Registers [callback]; the returned function detaches it.
  void Function() onAuthState(void Function(AuthState) callback) {
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  /// Cancels the single subscription and drops every registration. Idem
  /// potent for the detached callbacks, which are already gone from the
  /// list.
  void dispose() {
    _subscription.cancel();
    _callbacks.clear();
  }
}
