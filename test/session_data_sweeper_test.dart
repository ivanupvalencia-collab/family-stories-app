import 'dart:convert';
import 'dart:io';

import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/services/remote_family_member_cache.dart';
import 'package:family_stories_app/services/remote_family_photo_disk_cache.dart';
import 'package:family_stories_app/services/session_data_sweeper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Preferences implements SharedPreferencesAsync {
  final values = <String, List<String>>{};

  @override
  Future<List<String>?> getStringList(String key) async => values[key]?.toList();

  @override
  Future<void> setStringList(String key, List<String> value) async {
    values[key] = value.toList();
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _owner = '11111111-1111-4111-8111-111111111111';
const _other = '22222222-2222-4222-8222-222222222222';
const _memberId = '33333333-3333-4333-8333-333333333333';
const _storyId = '44444444-4444-4444-8444-444444444444';
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

Future<void> _login(SupabaseClient client, String id) => client.auth
    .recoverSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': id,
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-11-12T10:00:00Z',
        },
      }),
    )
    .then((_) {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalHttpOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = null);
  tearDown(() => HttpOverrides.global = originalHttpOverrides);

  late HttpServer server;
  late SupabaseClient client;
  late Directory support;
  late Directory temporary;
  late _Preferences prefs;
  late RemoteFamilyMemberCache members;
  late RemoteFamilyPhotoDiskCache photos;
  late RemoteFamilyPhotoDiskCache storyPhotos;
  late SessionDataSweeper sweeper;
  late String backend;

  Future<void> waitFor(Future<bool> Function() condition) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (!await condition()) {
      if (DateTime.now().isAfter(end)) {
        fail('Expected asynchronous purge event');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync
        .empty();
    support = await Directory.systemTemp.createTemp('sweeper_support_');
    temporary = await Directory.systemTemp.createTemp('sweeper_temp_');
    prefs = _Preferences();
    members = RemoteFamilyMemberCache(preferences: prefs);
    photos = RemoteFamilyPhotoDiskCache(directoryProvider: () async => support);
    storyPhotos = RemoteFamilyPhotoDiskCache(
      directoryProvider: () async => support,
      directoryName: 'remote_story_photos_v1',
      allowForeignUploader: true,
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{}');
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await _login(client, _owner);
    backend = client.storage.url;
    sweeper = SessionDataSweeper(
      client: client,
      memberCache: members,
      photosCache: photos,
      storyPhotosCache: storyPhotos,
      temporaryDirectoryProvider: () async => temporary,
    );
  });

  tearDown(() async {
    sweeper.dispose();
    await client.dispose();
    await server.close(force: true);
    await support.delete(recursive: true);
    await temporary.delete(recursive: true);
  });

  Future<void> seed(String owner) async {
    final bytes = base64Decode(_png);
    await photos.write(
      backend,
      owner,
      '$owner/$_memberId/portrait.png',
      bytes,
      stillValid: () => true,
    );
    await storyPhotos.write(
      backend,
      owner,
      '$owner/$_storyId/photo.png',
      bytes,
      stillValid: () => true,
    );
    await members.replace(backend, owner, const [
      FamilyMember(
        id: _memberId,
        name: 'Pepe',
        relationship: 'Padre/Madre',
      ),
    ]);
    final audio = Directory('${temporary.path}/remote_story_audio');
    await audio.create(recursive: true);
    await File('${audio.path}/$owner.m4a').writeAsString('audio');
  }

  /// Everything the purge scopes to the owner: both photo stores and the
  /// remote member list.
  Future<bool> presentScoped(String owner) async {
    final onDisk =
        await photos.read(
              backend,
              owner,
              '$owner/$_memberId/portrait.png',
            ) !=
            null;
    final storyOnDisk =
        await storyPhotos.read(
              backend,
              owner,
              '$owner/$_storyId/photo.png',
            ) !=
            null;
    final listed = await members.read(backend, owner) != null;
    return onDisk && storyOnDisk && listed;
  }

  /// Downloaded audio has no owner partition (files are named by story), so
  /// the sweeper removes the whole directory for every sign-out.
  Future<bool> audioPresent(String owner) =>
      File('${temporary.path}/remote_story_audio/$owner.m4a').exists();

  test(
    'la purga elimina fotos, audio y lista remota de la cuenta que se va, y solo suya',
    () async {
      await seed(_owner);
      await seed(_other);
      expect(await presentScoped(_owner), isTrue);
      expect(await presentScoped(_other), isTrue);
      expect(await audioPresent(_owner), isTrue);
      expect(await audioPresent(_other), isTrue);
      // The guest/offline keys never belong to a session.
      prefs.values['family_members'] = ['{"id":"guest"}'];

      await sweeper.purge(_owner);

      expect(await presentScoped(_owner), isFalse);
      expect(await presentScoped(_other), isTrue);
      // Audio is not owner-scoped: the whole cache directory goes away.
      expect(
        await Directory(
          '${temporary.path}/remote_story_audio',
        ).exists(),
        isFalse,
      );
      // Guest data must survive a purge, and the purged list must be gone.
      expect(prefs.values['family_members'], isNotEmpty);
      expect(await members.read(backend, _owner), isNull);
    },
  );

  test('la purga espera a las escrituras que aún se están committing', () async {
    final bytes = base64Decode(_png);
    final path = '$_owner/$_memberId/portrait.png';
    final pendingWrite = photos.write(
      backend,
      _owner,
      path,
      bytes,
      stillValid: () => true,
    );
    await sweeper.purge(_owner);
    await pendingWrite;
    expect(await photos.read(backend, _owner, path), isNull);
  });

  test('signedOut purga la sesión; un cambio de cuenta no purga nada', () async {
    await seed(_owner);
    expect(await presentScoped(_owner), isTrue);

    // Another account signs in without a signedOut event: nothing is purged.
    await _login(client, _other);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await presentScoped(_owner), isTrue);

    await seed(_other);
    await client.auth.signOut(scope: SignOutScope.local);
    await waitFor(() async => !(await presentScoped(_other)));
    // Only the session that actually ended is purged.
    expect(await presentScoped(_other), isFalse);
    expect(await presentScoped(_owner), isTrue);
    expect(await audioPresent(_other), isFalse);
  });

  test('forClient reutiliza la instancia por cliente y configuración', () {
    final otherClient = SupabaseClient(
      'https://another.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    expect(
      identical(
        RemoteFamilyPhotoDiskCache.forClient(client),
        RemoteFamilyPhotoDiskCache.forClient(client),
      ),
      isTrue,
    );
    expect(
      identical(
        RemoteFamilyPhotoDiskCache.forClient(client),
        RemoteFamilyPhotoDiskCache.forClient(
          client,
          directoryName: 'remote_story_photos_v1',
          allowForeignUploader: true,
        ),
      ),
      isFalse,
    );
    expect(
      identical(
        RemoteFamilyPhotoDiskCache.forClient(client),
        RemoteFamilyPhotoDiskCache.forClient(otherClient),
      ),
      isFalse,
    );
    expect(
      identical(
        RemoteFamilyMemberCache.forClient(client),
        RemoteFamilyMemberCache.forClient(client),
      ),
      isTrue,
    );
  });
}
