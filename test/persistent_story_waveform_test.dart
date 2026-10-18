import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/services/family_story_storage.dart';
import 'package:family_stories_app/services/persistent_story_waveform_service.dart';
import 'package:family_stories_app/services/story_waveform_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'widget_test.dart' as fixtures;

class _Extractor extends StoryWaveformService {
  final entered = Completer<void>();
  Completer<List<double>>? gate;
  List<double> samples = [0, .2, 1, .4];
  int calls = 0;
  bool disposed = false;
  @override
  Future<List<double>> extract(String localAudioPath) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    return gate?.future ?? samples;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _Preferences implements SharedPreferencesAsync {
  final List<String> values = [];
  @override
  Future<List<String>?> getStringList(String key) async => List.of(values);
  @override
  Future<void> setStringList(String key, List<String> value) async {
    values
      ..clear()
      ..addAll(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedDisk extends StoryWaveformDiskCache {
  _DelayedDisk(Directory directory)
    : super(directoryProvider: () async => directory);
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(
    String backend,
    String account,
    FamilyStory story,
    Map<String, dynamic> data,
    bool Function() valid,
  ) async {
    entered.complete();
    await release.future;
    await super.write(backend, account, story, data, valid);
  }
}

class _UnavailableDisk extends StoryWaveformDiskCache {
  @override
  Future<Map<String, dynamic>?> read(
    String backend,
    String account,
    FamilyStory story,
  ) async => throw const FileSystemException('Unavailable cache');
  @override
  Future<void> write(
    String backend,
    String account,
    FamilyStory story,
    Map<String, dynamic> data,
    bool Function() valid,
  ) async => throw const FileSystemException('Full cache');
}

FamilyStory _story({
  String id = 'story',
  String family = 'family',
  String path = 'request/original.m4a',
}) => FamilyStory(
  id: id,
  familyMemberId: family,
  question: 'Un recuerdo',
  audioPath: path,
  duration: const Duration(seconds: 12),
  createdAt: DateTime(2026),
);

Future<void> _login(SupabaseClient client, String account) => client.auth
    .recoverSession(
      jsonEncode({
        'access_token': 'test-token-$account',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': account,
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-10-18T12:00:00Z',
        },
      }),
    )
    .then((_) {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File audio;
  late StoryWaveformDiskCache disk;
  late _Extractor extractor;
  int resolutions = 0;
  Future<String> resolve() async {
    resolutions++;
    return audio.path;
  }

  PersistentStoryWaveformService cache({
    bool remote = true,
    String account = 'owner',
    String backend = 'https://example.test/storage/v1',
    _Extractor? native,
  }) => PersistentStoryWaveformService(
    backend: backend,
    account: account,
    remote: remote,
    disk: disk,
    extractorFactory: () => native ?? extractor,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'aritoria_persistent_waves_',
    );
    audio = await File('${directory.path}/audio.m4a').writeAsBytes([1, 2, 3]);
    disk = StoryWaveformDiskCache(
      directoryProvider: () async => Directory('${directory.path}/support'),
    );
    extractor = _Extractor();
    resolutions = 0;
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'disk failure still returns valid native samples and keeps them in memory',
    () async {
      final shared = PersistentStoryWaveformService(
        backend: 'backend',
        account: 'user',
        remote: true,
        disk: _UnavailableDisk(),
        extractorFactory: () => extractor,
      );
      expect(await shared.loadForStory(_story(), resolve), extractor.samples);
      expect(shared.cachedForStory(_story()), extractor.samples);
      expect(extractor.calls, 1);
    },
  );

  test(
    'invalidation during disk write cannot recreate the cleared scope',
    () async {
      final delayed = _DelayedDisk(Directory('${directory.path}/cache'));
      final shared = PersistentStoryWaveformService(
        backend: 'backend',
        account: 'user',
        remote: true,
        disk: delayed,
        extractorFactory: () => extractor,
      );
      final pending = shared.loadForStory(_story(), resolve);
      final rejected = expectLater(pending, throwsStateError);
      await delayed.entered.future;
      await shared.invalidate();
      delayed.release.complete();
      await rejected;
      expect(await delayed.read('backend', 'user', _story()), isNull);
    },
  );

  test(
    'logout clears active account samples and makes old handles unusable',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      try {
        await _login(client, 'owner');
        final shared = StoryWaveforms.forClient(
          client,
          diskCache: disk,
          extractorFactory: () => extractor,
        );
        await shared.loadForStory(_story(), resolve);
        await client.auth.signOut(scope: SignOutScope.local);
        StoryWaveforms.forClient(client);
        expect(shared.cachedForStory(_story()), isNull);
        await expectLater(
          shared.loadForStory(_story(), resolve),
          throwsStateError,
        );
        await (shared as PersistentStoryWaveformService).invalidate();
        expect(await disk.read(client.storage.url, 'owner', _story()), isNull);
      } finally {
        await client.dispose();
        await server.close(force: true);
        HttpOverrides.global = previous;
      }
    },
  );

  test('persists valid samples; reopened cache needs neither audio download nor extraction', () async {
    final first = cache();
    expect(await first.loadForStory(_story(), resolve), extractor.samples);
    expect(first.cachedForStory(_story()), extractor.samples);
    final reopened = cache(native: _Extractor()..samples = [.9]);
    await audio.delete();
    expect(
      await reopened.loadForStory(
        _story(),
        () => throw StateError('Must not download'),
      ),
      extractor.samples,
    );
    expect(extractor.calls, 1);
    expect(resolutions, 1);
  });

  test('warm-up and multiple readers share one extraction and survive screen disposal', () async {
    extractor.gate = Completer<List<double>>();
    final shared = cache();
    final warming = shared.warm(_story(), resolve);
    final reader1 = shared.loadForStory(_story(), resolve);
    final reader2 = shared.loadForStory(_story(), resolve);
    await extractor.entered.future;
    await shared.dispose();
    expect(extractor.calls, 1);
    expect(resolutions, 1);
    extractor.gate!.complete(extractor.samples);
    expect(await reader1, extractor.samples);
    expect(await reader2, extractor.samples);
    await warming;
  });

  test('backend and account namespaces never share samples', () async {
    await cache().loadForStory(_story(), resolve);
    final other = _Extractor()..samples = [.8, .1];
    expect(
      await cache(
        account: 'pepe',
        native: other,
      ).loadForStory(_story(), resolve),
      other.samples,
    );
    expect(
      await cache(
        backend: 'https://other.test',
        native: other,
      ).loadForStory(_story(), resolve),
      other.samples,
    );
    expect(other.calls, 2);
    expect(await cache().loadForStory(_story(), resolve), extractor.samples);
  });

  test(
    'changed remote object path and changed local file invalidate old samples',
    () async {
      final shared = cache();
      await shared.loadForStory(_story(), resolve);
      await shared.loadForStory(
        _story(path: 'request/replacement.m4a'),
        resolve,
      );
      expect(extractor.calls, 2);
      final local = cache(remote: false, account: 'device', backend: 'local');
      final story = _story(path: audio.path);
      await local.loadForStory(story, resolve);
      await audio.writeAsBytes([4, 5, 6, 7]);
      await local.loadForStory(story, resolve);
      expect(extractor.calls, 4);
    },
  );

  test(
    'broken, wrong-version and invalid sample cache is regenerated safely',
    () async {
      for (final broken in [
        '{',
        jsonEncode({'format': 'old'}),
        jsonEncode({
          'format': 'audio_waveforms-2.0.2-rms256-peak-v1',
          'identity': jsonEncode(['family', 'story', 'request/original.m4a']),
          'stamp': null,
          'samples': [2],
        }),
      ]) {
        await cache().loadForStory(_story(), resolve);
        final files = await directory
            .list(recursive: true)
            .where((entry) => entry is File && entry.path.endsWith('.json'))
            .cast<File>()
            .toList();
        await files.single.writeAsString(broken);
        final before = extractor.calls;
        expect(
          await cache().loadForStory(_story(), resolve),
          extractor.samples,
        );
        expect(extractor.calls, before + 1);
      }
    },
  );

  test('delete family removes disk/memory and prevents late extraction restoring it', () async {
    final shared = cache();
    await shared.loadForStory(_story(family: 'keep'), resolve);
    extractor.gate = Completer<List<double>>();
    final pending = shared.loadForStory(_story(), resolve);
    final rejected = expectLater(pending, throwsStateError);
    while (extractor.calls < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    await shared.forgetFamily('family');
    extractor.gate!.complete(extractor.samples);
    await rejected;
    expect(shared.cachedForStory(_story()), isNull);
    await expectLater(shared.loadForStory(_story(), resolve), throwsStateError);
    expect(
      await cache().loadForStory(
        _story(family: 'keep'),
        () => throw StateError('Keep cached'),
      ),
      extractor.samples,
    );
    final next = _Extractor();
    await cache(native: next).loadForStory(_story(), resolve);
    expect(next.calls, 1);
  });

  test('account invalidation cancels work, removes persisted data and ignores late results', () async {
    final shared = cache();
    await shared.loadForStory(_story(id: 'cached'), resolve);
    extractor.gate = Completer<List<double>>();
    final pending = shared.loadForStory(_story(), resolve);
    final rejected = expectLater(pending, throwsStateError);
    while (extractor.calls < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    await shared.invalidate();
    extractor.gate!.complete(extractor.samples);
    await rejected;
    expect(extractor.disposed, isTrue);
    expect(shared.cachedForStory(_story(id: 'cached')), isNull);
    final next = _Extractor();
    await cache(native: next).loadForStory(_story(id: 'cached'), resolve);
    expect(next.calls, 1);
  });

  test(
    'real auth account changes bind new scope and clear previous account disk',
    () async {
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await _login(client, 'ivan');
      final ivan = StoryWaveforms.forClient(
        client,
        diskCache: disk,
        extractorFactory: () => extractor,
      );
      await ivan.loadForStory(_story(), resolve);
      await _login(client, 'pepe');
      final pepe = StoryWaveforms.forClient(client);
      expect(ivan.cachedForStory(_story()), isNull);
      await expectLater(ivan.loadForStory(_story(), resolve), throwsStateError);
      await pepe.loadForStory(_story(), resolve);
      expect(extractor.calls, 2);
      // Return to Ivan: old disk entries must already have been removed.
      await _login(client, 'ivan');
      await StoryWaveforms.forClient(client).loadForStory(_story(), resolve);
      expect(extractor.calls, 3);
      await (StoryWaveforms.forClient(client) as PersistentStoryWaveformService)
          .invalidate();
      await client.dispose();
    },
  );

  test('local save returns before background extraction; deletion cleans its waveform', () async {
    extractor.gate = Completer<List<double>>();
    final shared = cache(remote: false, backend: 'local', account: 'device');
    final storage = LocalFamilyStoryStorage(
      preferences: _Preferences(),
      documentsProvider: () async => directory,
      supportProvider: () async => directory,
      waveformService: shared,
    );
    final saved = await storage.saveRecording(
      familyMemberId: 'family',
      question: 'Un recuerdo',
      temporaryAudioPath: audio.path,
      duration: const Duration(seconds: 4),
    );
    expect(await File(saved.audioPath).exists(), isTrue);
    await extractor.entered.future;
    expect(extractor.gate!.isCompleted, isFalse);
    extractor.gate!.complete(extractor.samples);
    expect(
      await shared.loadForStory(saved, () async => saved.audioPath),
      extractor.samples,
    );
    await storage.deleteFamily('family', fixtures.MemoryFamilyMemberStorage());
    expect(await File(saved.audioPath).exists(), isFalse);
    await expectLater(
      shared.loadForStory(saved, () async => saved.audioPath),
      throwsStateError,
    );
  });
}
