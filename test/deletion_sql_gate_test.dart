import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// S-8: `familyMemberRemoteDeletionEnabled` is a compile-time claim that the
// backend has the remote-deletion RPCs installed. The claim must be checked
// against the versioned baseline on every run — never against a comment.
void main() {
  Directory repoRoot() {
    var dir = Directory.current;
    while (!File('${dir.path}/pubspec.yaml').existsSync()) {
      final parent = dir.parent;
      if (parent.path == dir.path) {
        fail('No se encontró la raíz del repositorio.');
      }
      dir = parent;
    }
    return dir;
  }

  test(
    'el flag de borrado remoto solo está activo con las RPCs versionadas (S-8)',
    () {
      final root = repoRoot();
      final flagSource = File(
        '${root.path}/lib/services/family_member_deletion_service.dart',
      ).readAsStringSync();
      final match = RegExp(
        r'familyMemberRemoteDeletionEnabled\s*=\s*(true|false)',
      ).firstMatch(flagSource);
      expect(match, isNotNull, reason: 'Flag no encontrado en el servicio.');
      final enabled = match!.group(1) == 'true';
      if (!enabled) {
        // Apagado: el backend no necesita ninguna RPC.
        return;
      }

      final migrations =
          Directory('${root.path}/supabase/migrations')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.sql'))
              .map((f) => f.readAsStringSync())
              .join('\n');

      for (final fn in [
        'prepare_family_member_delete',
        'finish_family_member_delete',
      ]) {
        expect(
          migrations,
          contains('create or replace function public.$fn('),
          reason:
              'Flag activo pero falta $fn en supabase/migrations/ (S-8).',
        );
        expect(
          migrations,
          contains('revoke all on function public.$fn(uuid) from public, anon;'),
          reason: 'Falta el revoke de $fn para public/anon (S-8).',
        );
        expect(
          migrations,
          contains(
            'grant execute on function public.$fn(uuid) to authenticated;',
          ),
          reason: 'Falta el grant de $fn a authenticated (S-8).',
        );
      }
    },
  );
}
