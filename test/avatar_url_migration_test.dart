import 'dart:io';

import 'package:family_stories_app/services/private_photo_service.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = '11111111-1111-4111-8111-111111111111';
const _base =
    'https://hwqvdrtehvixqloegilg.supabase.co/storage/v1/object/public/avatars';
const _migration =
    'supabase/migrations/20261121000001_avatar_url_image_extensions.sql';

// Exercise the pattern actually installed by the migration, including the
// row's id. This is a static regression check, not a PostgreSQL integration test.
RegExp _checkPattern(String path) {
  final sql = File(path).readAsStringSync();
  final match = RegExp(
    r"avatar_url ~ \(\s*'([^']+)'\s*\|\| id::text\s*\|\| '([^']+)'",
  ).firstMatch(sql);
  expect(match, isNotNull, reason: 'Missing per-user avatar URL CHECK: $path');
  return RegExp('${match!.group(1)}$_owner${match.group(2)}');
}

void main() {
  test('previous CHECK rejects the JPEG URL produced by the uploader', () {
    final previous = _checkPattern(
      'supabase/migrations/20261112000001_avatar_url_allowlist.sql',
    );
    expect(previous.hasMatch('$_base/$_owner/profile?v=123'), isTrue);
    expect(previous.hasMatch('$_base/$_owner/profile.jpg?v=123'), isFalse);
  });

  test(
    'new CHECK accepts legacy avatars and every supported image extension',
    () {
      final check = _checkPattern(_migration);
      expect(check.hasMatch('$_base/$_owner/profile?v=123'), isTrue);
      for (final mime in [
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/heic',
        'image/heif',
      ]) {
        final extension = privatePhotoExtension(
          PickedProfileImage(bytes: Uint8List.fromList([1]), contentType: mime),
        );
        expect(
          check.hasMatch('$_base/$_owner/profile.$extension?v=123'),
          isTrue,
          reason: mime,
        );
      }
    },
  );

  test('new CHECK rejects other owners, origins, buckets and file formats', () {
    final check = _checkPattern(_migration);
    final valid = '$_base/$_owner/profile.jpg?v=123';
    for (final invalid in [
      valid.replaceFirst(_owner, '22222222-2222-4222-8222-222222222222'),
      valid.replaceFirst('https:', 'http:'),
      valid.replaceFirst('.supabase.co/', '.supabase.co.evil.test/'),
      valid.replaceFirst('.supabase.co/', '.supabaseXco/'),
      valid.replaceFirst('/avatars/', '/story-photos/'),
      valid.replaceFirst('/public/', '/sign/'),
      valid.replaceFirst('/profile', '/../$_owner/profile'),
      valid.replaceFirst('/profile', '/other'),
      for (final extension in ['svg', 'gif', 'html', 'jpeg', 'JPG', 'jpg.exe'])
        valid.replaceFirst('.jpg', '.$extension'),
      valid.replaceFirst('.jpg', 'Xjpg'),
      valid.replaceFirst('?v=123', ''),
      valid.replaceFirst('?v=123', '?v=abc'),
      '$valid&redirect=https://evil.test',
      '$valid#fragment',
      'https://evil.test/$valid',
    ]) {
      expect(check.hasMatch(invalid), isFalse, reason: invalid);
    }
  });

  test('replacement is atomic and preserves null and catalogue avatars', () {
    final sql = File(_migration)
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');
    expect(
      sql.split(';').where((part) => part.trim().isNotEmpty),
      hasLength(1),
    );
    expect(sql, contains('alter table public.profiles'));
    expect(
      sql,
      contains('drop constraint if exists profiles_avatar_url_storage_only,'),
    );
    expect(sql, contains('add constraint profiles_avatar_url_storage_only'));
    expect(sql, contains('avatar_url is null'));
    expect(sql, contains("or avatar_url = ''"));
    expect(sql.toLowerCase(), isNot(contains('not valid')));
  });
}
