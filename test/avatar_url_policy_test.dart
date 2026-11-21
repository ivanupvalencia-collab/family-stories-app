import 'package:family_stories_app/services/avatar_url_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const backend = 'https://hwqvdrtehvixqloegilg.supabase.co/storage/v1';
  const allowed =
      'https://hwqvdrtehvixqloegilg.supabase.co/storage/v1/object/'
      'public/avatars/11111111-1111-4111-8111-111111111111/profile?v=1763000000000';

  group('AvatarUrlPolicy.forBackend', () {
    late AvatarUrlPolicy policy;

    setUp(() => policy = AvatarUrlPolicy.forBackend(backend));

    test('acepta la única URL que genera la app', () {
      expect(policy.allows(allowed), isTrue);
      expect(policy.allows('  $allowed  '), isTrue);
    });

    test('tolera normalización de host y barra final en el backend', () {
      expect(
        AvatarUrlPolicy.forBackend('$backend/')
          .allows(allowed),
        isTrue,
      );
      expect(
        policy.allows(
          'https://HWQVDRTEHVIXQLOEGILG.supabase.co/storage/v1/object/'
          'public/avatars/u/profile?v=1',
        ),
        isTrue,
      );
    });

    test('rechaza cualquier host que no sea el del backend', () {
      for (final url in <String>[
        'https://evil.example.com/storage/v1/object/public/avatars/u/profile',
        'https://hwqvdrtehvixqloegilg.supabase.co.evil.com/storage/v1/'
            'object/public/avatars/u/profile',
        'https://evilhwqvdrtehvixqloegilg.supabase.co/storage/v1/object/'
            'public/avatars/u/profile',
        'https://hwqvdrtehvixqloegilg.supabase.co./storage/v1/object/'
            'public/avatars/u/profile',
        'https://storage.supabase.co/storage/v1/object/public/avatars/u/p',
      ]) {
        expect(policy.allows(url), isFalse, reason: url);
      }
    });

    test('rechaza objetivos de red interna aunque el esquema coincida', () {
      for (final url in <String>[
        'http://127.0.0.1/storage/v1/object/public/avatars/u/profile',
        'http://localhost/storage/v1/object/public/avatars/u/profile',
        'https://192.168.1.1/router.cgi',
        'https://10.0.0.1/admin',
        'https://169.254.169.254/latest/meta-data/',
        'https://[::1]/storage/v1/object/public/avatars/u/profile',
        'file:///etc/passwd',
      ]) {
        expect(policy.allows(url), isFalse, reason: url);
      }
    });

    test('rechaza bajadas de esquema, puertos y credenciales en la URL', () {
      expect(
        policy.allows('http://hwqvdrtehvixqloegilg.supabase.co/storage/v1/'
            'object/public/avatars/u/profile'),
        isFalse,
      );
      expect(
        policy.allows('https://hwqvdrtehvixqloegilg.supabase.co:8443/storage/v1/'
            'object/public/avatars/u/profile'),
        isFalse,
      );
      expect(
        policy.allows('https://user:pass@hwqvdrtehvixqloegilg.supabase.co/'
            'storage/v1/object/public/avatars/u/profile'),
        isFalse,
      );
    });

    test('rechaza rutas fuera del bucket de avatares', () {
      for (final url in <String>[
        'https://hwqvdrtehvixqloegilg.supabase.co/storage/v1/object/'
            'public/stories/anything.png',
        'https://hwqvdrtehvixqloegilg.supabase.co/storage/v1/object/'
            'public/avatars-evasion/u/profile',
        'https://hwqvdrtehvixqloegilg.supabase.co/functions/v1/anything',
        'https://hwqvdrtehvixqloegilg.supabase.co/auth/v1/token',
        'https://hwqvdrtehvixqloegilg.supabase.co/storage/v1/object/'
            'sign/avatars/u/profile',
      ]) {
        expect(policy.allows(url), isFalse, reason: url);
      }
    });

    test('rechaza basura y URLs relativas', () {
      for (final url in <String>[
        '',
        '   ',
        'not a url',
        '/storage/v1/object/public/avatars/u/profile',
        'avatars/u/profile',
        'javascript:alert(1)',
      ]) {
        expect(policy.allows(url), isFalse, reason: url);
      }
    });
  });

  group('AvatarUrlPolicy con un backend inutilizable', () {
    test('rechaza todo en lugar de permitir todo', () {
      for (final backend in <String>['', '   ', 'not-a-url']) {
        final policy = AvatarUrlPolicy.forBackend(backend);
        expect(policy.allows(allowed), isFalse, reason: backend);
        expect(policy.allows('https://evil.example.com/x'), isFalse);
        expect(policy.allows('http://127.0.0.1/x'), isFalse);
      }
    });
  });

  group('AvatarUrlPolicy.permissive', () {
    test('solo acepta http(s), para los tests que sirven sus propios bytes',
        () {
      final policy = AvatarUrlPolicy.permissive();
      expect(policy.allows('http://127.0.0.1:8080/avatar?v=1'), isTrue);
      expect(policy.allows('https://example.test/avatar.png'), isTrue);
      expect(policy.allows('file:///etc/passwd'), isFalse);
      expect(policy.allows('not a url'), isFalse);
    });
  });
}
