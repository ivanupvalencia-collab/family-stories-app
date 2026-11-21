import 'dart:io';

import 'package:http/http.dart';
import 'package:http/io_client.dart';

// C-7: one connection stack for every download in the app. Avatar bytes and
// Supabase storage/REST/auth requests share the same sockets (TLS handshakes
// are reused instead of opening a fresh HttpClient per download) and the same
// S-5 connection timeout.
//
// These are process-lifetime singletons and are never closed:
// SupabaseClient.dispose() only closes clients it created itself, and the
// idle connections are released by HttpClient.idleTimeout (120 s default).
final HttpClient sharedHttpClient = HttpClient()
  ..connectionTimeout = const Duration(seconds: 10);

/// [sharedHttpClient] behind the `package:http` interface that
/// `SupabaseClient(httpClient: ...)` requires for storage/REST/auth.
final Client sharedSupabaseHttpClient = IOClient(sharedHttpClient);
