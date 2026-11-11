import 'package:family_stories_app/services/secure_session_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sessionKey = 'sb-hwqvdrtehvixqloegilg-auth-token';
const _pkceKey = SecureLocalStorage.pkceVerifierKey;
const _sessionValue = '{"access_token":"jwt","refresh_token":"refresh"}';
const _verifierValue = 'a-pkce-code-verifier';

void main() {
  group('SecureLocalStorage', () {
    late InMemorySecureKeyValueStore store;

    SecureLocalStorage buildStorage() =>
        SecureLocalStorage(sessionKey: _sessionKey, store: store);

    setUp(() {
      store = InMemorySecureKeyValueStore();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('deriva la misma clave de sesión que supabase_flutter', () {
      expect(
        SecureLocalStorage.sessionKeyFor(
          'https://hwqvdrtehvixqloegilg.supabase.co',
        ),
        'sb-hwqvdrtehvixqloegilg-auth-token',
      );
    });

    test('lee, escribe y borra la sesión en el almacén cifrado', () async {
      final storage = buildStorage();
      await storage.initialize();

      expect(await storage.hasAccessToken(), isFalse);

      await storage.persistSession(_sessionValue);

      expect(await storage.hasAccessToken(), isTrue);
      expect(await storage.accessToken(), _sessionValue);
      expect(store.values, containsPair(_sessionKey, _sessionValue));

      await storage.removePersistedSession();

      expect(await storage.hasAccessToken(), isFalse);
      expect(store.values, isEmpty);
    });

    test('migra la sesión y el verificador PKCE y borra el texto plano',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _sessionKey: _sessionValue,
        _pkceKey: _verifierValue,
      });

      await buildStorage().initialize();

      expect(store.values, containsPair(_sessionKey, _sessionValue));
      expect(store.values, containsPair(_pkceKey, _verifierValue));

      final legacy = await SharedPreferences.getInstance();
      expect(legacy.getString(_sessionKey), isNull);
      expect(legacy.getString(_pkceKey), isNull);
    });

    test('no borra el texto plano si la escritura cifrada falla', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _sessionKey: _sessionValue,
      });
      store = InMemorySecureKeyValueStore(failWrites: true);

      await buildStorage().initialize();

      final legacy = await SharedPreferences.getInstance();
      expect(legacy.getString(_sessionKey), _sessionValue);
      expect(store.values, isEmpty);

      // The session is still reachable through the legacy fallback only if
      // the storage were reading it, which it deliberately is not: keeping
      // the plaintext guarantees the next launch can retry the migration.
      expect(legacy.getString(_sessionKey), isNotNull);
    });

    test('es idempotente y nunca pisa la sesión ya cifrada', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _sessionKey: 'stale-plain-value',
      });
      store = InMemorySecureKeyValueStore(initial: {_sessionKey: 'fresh'});

      final storage = buildStorage();
      await storage.initialize();
      await storage.initialize();

      expect(store.values[_sessionKey], 'fresh');

      final legacy = await SharedPreferences.getInstance();
      expect(legacy.getString(_sessionKey), isNull);
    });

    test('migra una sesión nueva si la anterior no llegó a cifrarse',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _sessionKey: _sessionValue,
      });

      await buildStorage().initialize();
      expect(store.values[_sessionKey], _sessionValue);

      // A second run after the plaintext copy was already removed must not
      // resurrect or duplicate anything.
      await buildStorage().initialize();
      expect(store.values, containsPair(_sessionKey, _sessionValue));
    });

    test('sin nada que migrar deja el almacén intacto', () async {
      await buildStorage().initialize();

      expect(store.values, isEmpty);
    });
  });

  group('SecureGotrueAsyncStorage', () {
    late InMemorySecureKeyValueStore store;
    late SecureGotrueAsyncStorage storage;

    setUp(() {
      store = InMemorySecureKeyValueStore();
      storage = SecureGotrueAsyncStorage(store: store);
    });

    test('guarda y recupera el verificador PKCE cifrado', () async {
      expect(
        await storage.getItem(key: SecureLocalStorage.pkceVerifierKey),
        isNull,
      );

      await storage.setItem(
        key: SecureLocalStorage.pkceVerifierKey,
        value: _verifierValue,
      );

      expect(
        await storage.getItem(key: SecureLocalStorage.pkceVerifierKey),
        _verifierValue,
      );
      expect(
        store.values,
        containsPair(SecureLocalStorage.pkceVerifierKey, _verifierValue),
      );

      await storage.removeItem(key: SecureLocalStorage.pkceVerifierKey);

      expect(
        await storage.getItem(key: SecureLocalStorage.pkceVerifierKey),
        isNull,
      );
    });

    test('comparte el almacén con la sesión cuando se le inyecta', () async {
      final localStorage = SecureLocalStorage(
        sessionKey: _sessionKey,
        store: store,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        _sessionKey: _sessionValue,
      });

      await localStorage.initialize();

      // Both storages read the same key from the same store.
      expect(
        await storage.getItem(key: SecureLocalStorage.pkceVerifierKey),
        isNull,
      );
      expect(await localStorage.accessToken(), _sessionValue);
    });
  });
}
