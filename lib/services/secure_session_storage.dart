import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal key-value contract for the auth session.
///
/// Supabase's own storages talk to SharedPreferences directly, which leaves
/// the JWT, the refresh token and the PKCE verifier readable by anyone with
/// the app's private directory or a device backup. Everything the session
/// touches goes through this interface so the real implementation can be
/// swapped for a fake in tests.
abstract class SecureKeyValueStore {
  const SecureKeyValueStore();

  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<bool> containsKey(String key);
}

/// [SecureKeyValueStore] backed by the platform Keystore/Keychain.
class FlutterSecureKeyValueStore extends SecureKeyValueStore {
  const FlutterSecureKeyValueStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);
}

/// In-memory [SecureKeyValueStore] for tests.
class InMemorySecureKeyValueStore extends SecureKeyValueStore {
  InMemorySecureKeyValueStore({
    Map<String, String>? initial,
    this.failWrites = false,
  }) : _values = {...?initial};

  final Map<String, String> _values;

  /// When true every write throws, which is how the migration guard is
  /// tested: a failed secure write must never destroy the plaintext copy.
  final bool failWrites;

  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) {
      throw Exception('secure storage unavailable');
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);
}

/// Session persistence on top of [SecureKeyValueStore].
///
/// Replaces `SharedPreferencesLocalStorage` from supabase_flutter. It also
/// migrates whatever the app stored in plain SharedPreferences before S-3, so
/// upgrading does not sign the user out.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({
    required this.sessionKey,
    SecureKeyValueStore? store,
    Future<SharedPreferences> Function()? legacy,
  })  : _store = store ?? const FlutterSecureKeyValueStore(),
        _legacy = legacy ?? SharedPreferences.getInstance;

  /// Key used both in secure storage and in the legacy plain storage.
  final String sessionKey;

  final SecureKeyValueStore _store;
  final Future<SharedPreferences> Function() _legacy;

  /// Key of the PKCE code verifier written by gotrue
  /// (`Constants.defaultStorageKey` in gotrue_client.dart).
  static const pkceVerifierKey = 'supabase.auth.token-code-verifier';

  /// Key supabase_flutter derives from the project URL for the session.
  ///
  /// Mirrors `Supabase.initialize` so both always agree; a mismatch would
  /// silently skip the migration.
  static String sessionKeyFor(String url) =>
      'sb-${Uri.parse(url).host.split('.').first}-auth-token';

  @override
  Future<void> initialize() => _migrateFromPlainStorage();

  @override
  Future<bool> hasAccessToken() => _store.containsKey(sessionKey);

  @override
  Future<String?> accessToken() => _store.read(sessionKey);

  @override
  Future<void> removePersistedSession() => _store.delete(sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(sessionKey, persistSessionString);

  /// Moves the session and the PKCE verifier out of plain SharedPreferences.
  ///
  /// The plaintext copy is only deleted after the secure copy has been read
  /// back and compared: if the Keystore rejects the write, keeping the token
  /// in plain storage is the lesser problem compared with signing everyone
  /// out. Runs on every launch and is idempotent.
  Future<void> _migrateFromPlainStorage() async {
    final legacy = await _legacy();

    for (final key in <String>[sessionKey, pkceVerifierKey]) {
      if (await _store.containsKey(key)) {
        // The secure copy is authoritative; drop any stale plaintext leftover.
        await legacy.remove(key);
        continue;
      }

      final value = legacy.getString(key);
      if (value == null) {
        continue;
      }

      try {
        await _store.write(key, value);
      } catch (_) {
        // Leave the plaintext in place so the session survives a failing
        // Keystore; the next launch retries the migration.
        continue;
      }

      if (await _store.read(key) == value) {
        await legacy.remove(key);
      }
    }
  }
}

/// PKCE verifier storage on top of [SecureKeyValueStore].
///
/// Replaces `SharedPreferencesGotrueAsyncStorage` from supabase_flutter.
/// The verifier itself is migrated by [SecureLocalStorage]; both must share
/// the same store so they read the same key.
class SecureGotrueAsyncStorage extends GotrueAsyncStorage {
  SecureGotrueAsyncStorage({SecureKeyValueStore? store})
      : _store = store ?? const FlutterSecureKeyValueStore();

  final SecureKeyValueStore _store;

  @override
  Future<String?> getItem({required String key}) => _store.read(key);

  @override
  Future<void> setItem({required String key, required String value}) =>
      _store.write(key, value);

  @override
  Future<void> removeItem({required String key}) => _store.delete(key);
}
