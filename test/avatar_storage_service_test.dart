import 'dart:convert';
import 'dart:io';

import 'package:family_stories_app/services/avatar_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'jpeg_test_fixture.dart';

void main() {
  test(
    'new avatar uses .jpg, JPEG MIME, correct bytes and a revisioned URL',
    () async {
      final image = await jpegTestPhoto();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <({String path, String? mime, List<int> bytes})>[];
      server.listen((request) async {
        final bytes = await request.fold<List<int>>(
          [],
          (all, part) => all..addAll(part),
        );
        requests.add((
          path: request.uri.path,
          mime: request.headers.contentType?.mimeType,
          bytes: bytes,
        ));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'Key': 'avatars/owner/profile.jpg'}),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
      );
      try {
        final service = SupabaseAvatarStorageService(client: client);
        final url = Uri.parse(
          await service.uploadAvatar(userId: 'owner', image: image),
        );
        expect(
          requests.single.path,
          '/storage/v1/object/avatars/owner/profile.jpg',
        );
        expect(requests.single.mime, 'multipart/form-data');
        final multipart = latin1.decode(requests.single.bytes);
        expect(multipart.toLowerCase(), contains('content-type: image/jpeg'));
        expect(multipart, contains(latin1.decode(image.bytes)));
        expect(url.path, '/storage/v1/object/public/avatars/owner/profile.jpg');
        expect(url.queryParameters['v'], isNotEmpty);
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    },
  );
}
