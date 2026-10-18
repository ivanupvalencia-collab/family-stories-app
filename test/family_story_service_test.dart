import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/services/family_story_service.dart';
import 'package:family_stories_app/services/story_waveform_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _BackgroundWaveforms extends StoryWaveformService {
  final entered = Completer<String>();
  final finish = Completer<List<double>>();
  @override
  Future<List<double>> extract(String localAudioPath) {
    if (!entered.isCompleted) entered.complete(localAudioPath);
    return finish.future;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These service tests use only a loopback server, not Flutter's HTTP stub.
  final originalHttpOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = null);
  tearDown(() => HttpOverrides.global = originalHttpOverrides);
  late Directory temporary;
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseFamilyStoryService service;
  late List<String> requestedPaths;
  late List<String?> authorizationHeaders;
  late List<int> responseBytes;
  late int status;
  Completer<void>? downloadGate;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final story = FamilyStory.fromSupabaseJson({
    'id': 'story-id',
    'family_member_id': 'family-id',
    'question': 'Pregunta',
    'audio_path': 'request-id/original-audio.m4a',
    'duration_seconds': 12,
    'created_at': '2026-10-04T10:00:00Z',
  });

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('remote_audio_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => temporary.path);
    requestedPaths = [];
    authorizationHeaders = [];
    responseBytes = [0, 0, 0, 16, ...ascii.encode('ftypM4A '), 0, 0, 0, 0];
    status = 200;
    downloadGate = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestedPaths.add(request.uri.path);
      authorizationHeaders.add(request.headers.value('authorization'));
      request.response.statusCode = status;
      if (status == 200) {
        request.response.headers.contentType = ContentType('audio', 'mp4');
        request.response.add(responseBytes);
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'statusCode': '$status',
            'error': 'Unauthorized',
            'message': 'permission denied for storage object',
          }),
        );
      }
      await downloadGate?.future;
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': 'test-owner',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'aud': 'authenticated',
          'created_at': '2026-10-04T10:00:00Z',
        },
      }),
    );
    service = SupabaseFamilyStoryService(client: client);
  });

  test(
    'deletion cache cleanup rejects late audio downloads before writing files',
    () async {
      downloadGate = Completer<void>();
      final pending = service.localAudioPathFor(story);
      final assertion = expectLater(pending, throwsStateError);
      while (requestedPaths.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await service.clearAudioCache();
      downloadGate!.complete();
      downloadGate = null;
      await assertion;
      expect(await temporary.list(recursive: true).toList(), isEmpty);
    },
  );

  tearDown(() async {
    await service.clearAudioCache();
    await client.dispose();
    await server.close(force: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temporary.delete(recursive: true);
  });

  test(
    'downloads the exact object with session and writes all M4A bytes',
    () async {
      final path = await service.localAudioPathFor(story);
      expect(requestedPaths, [
        '/storage/v1/object/story-audio/${story.audioPath}',
      ]);
      expect(authorizationHeaders, ['Bearer test-access-token']);
      expect(path.endsWith('.m4a'), isTrue);
      expect(await File(path).readAsBytes(), responseBytes);
      expect(await service.localAudioPathFor(story), path);
      expect(requestedPaths, hasLength(1));
      await service.clearAudioCache();
      expect(await File(path).exists(), isFalse);
    },
  );

  test('remote waveform starts after full local write and does not block returning audio', () async {
    final waveforms = _BackgroundWaveforms();
    final warming = SupabaseFamilyStoryService(
      client: client,
      waveformService: waveforms,
    );
    final path = await warming.localAudioPathFor(story);
    expect(await waveforms.entered.future, path);
    expect(await File(path).readAsBytes(), responseBytes);
    expect(waveforms.finish.isCompleted, isFalse);
    waveforms.finish.complete([0, 1]);
    await warming.clearAudioCache();
  });

  for (final damage in ['empty', 'truncated', 'missing']) {
    test('redownloads a $damage cached file', () async {
      final path = await service.localAudioPathFor(story);
      final file = File(path);
      if (damage == 'missing') {
        await file.delete();
      } else {
        await file.writeAsBytes(
          damage == 'empty' ? [] : responseBytes.sublist(0, 8),
        );
      }
      await service.localAudioPathFor(story);
      expect(requestedPaths, hasLength(2));
      expect(await file.readAsBytes(), responseBytes);
    });
  }

  test('rejects empty downloads without caching and allows a retry', () async {
    final originalBytes = responseBytes;
    responseBytes = [];
    await expectLater(service.localAudioPathFor(story), throwsStateError);
    responseBytes = originalBytes;
    final path = await service.localAudioPathFor(story);
    expect(requestedPaths, hasLength(2));
    expect(await File(path).readAsBytes(), originalBytes);
  });

  test(
    'preserves StorageException and allows retry after a failed download',
    () async {
      status = 403;
      await expectLater(
        service.localAudioPathFor(story),
        throwsA(
          isA<StorageException>()
              .having((e) => e.statusCode, 'statusCode', '403')
              .having(
                (e) => e.message,
                'message',
                contains('permission denied for storage object'),
              ),
        ),
      );
      status = 200;
      await service.localAudioPathFor(story);
      expect(requestedPaths, hasLength(2));
    },
  );
}
