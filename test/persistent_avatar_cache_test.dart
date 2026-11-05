import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_stories_app/models/user_profile.dart';
import 'package:family_stories_app/services/profile_avatar_image_cache.dart';
import 'package:family_stories_app/services/profile_service.dart';
import 'package:family_stories_app/services/visible_account_avatar_service.dart';
import 'package:family_stories_app/services/remote_family_photo_disk_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory directory;
  late RemoteFamilyPhotoDiskCache disk;
  late HttpServer server;
  final clients = <SupabaseClient>[];
  final images = <ProfileAvatarImageCache>[];
  final visibleServices = <SupabaseVisibleAccountAvatarService>[];
  var downloads = 0, metadataRequests = 0, revision = 1, replies = 0;
  var revoked = false;
  Completer<void>? metadataGate, imageGate;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  String getUrl(int v) => 'http://127.0.0.1:${server.port}/avatar?v=$v';
  Map<String, dynamic> jsonProfile(String id) => {
    'id': id,
    'name': 'Pepe',
    'avatar_url': getUrl(revision),
  };

  Future<void> login(SupabaseClient client, [String id = 'owner']) async {
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': id,
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {'picture': 'https://google.test/never-use-this'},
          'created_at': '2026-11-05T12:00:00Z',
        },
      }),
    );
  }

  Future<SupabaseClient> newClient() async {
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    clients.add(client);
    await login(client);
    return client;
  }

  ProfileAvatarImageCache newImages(SupabaseClient client) {
    final cache = ProfileAvatarImageCache(client: client, diskCache: disk);
    images.add(cache);
    return cache;
  }

  Future<void> resolve(ImageProvider provider) {
    final ready = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, sync) {
        info.dispose();
        stream.removeListener(listener);
        ready.complete();
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        ready.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return ready.future.timeout(const Duration(seconds: 5));
  }

  Future<void> waitFor(bool Function() condition) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(end)) {
        fail('Expected asynchronous cache event');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  void release(Completer<void>? gate) {
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  setUp(() async {
    downloads = 0;
    replies = 0;
    metadataRequests = 0;
    revision = 1;
    revoked = false;
    metadataGate = null;
    imageGate = null;
    directory = await Directory.systemTemp.createTemp('aritoria_avatar_cache_');
    disk = RemoteFamilyPhotoDiskCache(
      directoryProvider: () async => directory,
      directoryName: 'avatars_test',
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/avatar') {
        downloads++;
        await imageGate?.future;
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
      } else if (request.uri.path.startsWith('/auth/')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
      } else {
        metadataRequests++;
        await metadataGate?.future;
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('get_visible_account_avatars')) {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          request.response.write(
            jsonEncode(
              revoked
                  ? []
                  : [
                      for (final id in body['p_account_ids'])
                        jsonProfile(id as String),
                    ],
            ),
          );
        } else {
          request.response.write(jsonEncode(jsonProfile('owner')));
        }
      }
      await request.response.close();
      if (!request.uri.path.startsWith('/auth/') &&
          request.uri.path != '/avatar') {
        replies++;
      }
    });
  });
  tearDown(() async {
    release(metadataGate);
    release(imageGate);
    for (final service in visibleServices) {
      service.dispose();
    }
    for (final cache in images) {
      cache.dispose();
    }
    for (final client in clients) {
      await client.dispose();
    }
    visibleServices.clear();
    images.clear();
    clients.clear();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await disk.clearOwner(
      'cleanup',
      'owner',
    ); // Drain queued writes before teardown.
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('own avatar and metadata survive cold restart before server validation completes', () async {
    final client = await newClient();
    final first = newImages(client);
    final service = SupabaseProfileService(client: client, avatarCache: first);
    final profile = await service.loadForUser('owner');
    await resolve(first.imageFor(profile)!);
    expect(downloads, 1);
    first.clear(); // Process memory disappears; its private disk remains.
    metadataGate = Completer<void>();
    final restarted = await newClient();
    final cache = newImages(restarted);
    final next = SupabaseProfileService(client: restarted, avatarCache: cache);
    final cached = await next
        .loadForUser('owner')
        .timeout(const Duration(seconds: 2));
    await resolve(cache.imageFor(cached)!);
    await waitFor(() => metadataRequests == 2);
    expect(metadataGate!.isCompleted, isFalse);
    expect(downloads, 1);
    release(metadataGate);
    await waitFor(() => replies == 2);
  });

  test('linked/sender avatar cold cache renders first and a new revision replaces it in background', () async {
    final firstClient = await newClient();
    final first = newImages(firstClient);
    final service = SupabaseVisibleAccountAvatarService(
      client: firstClient,
      avatarCache: first,
    );
    visibleServices.add(service);
    final original = (await service.load('sender'))!;
    await resolve(first.imageFor(original)!);
    first.clear();
    metadataGate = Completer<void>();
    revision = 2;
    final client = await newClient();
    final cache = newImages(client);
    final next = SupabaseVisibleAccountAvatarService(
      client: client,
      avatarCache: cache,
    );
    visibleServices.add(next);
    final cached = (await next.load('sender'))!;
    expect(cached.avatarUrl, getUrl(1));
    await resolve(cache.imageFor(cached)!);
    expect(downloads, 1);
    release(metadataGate);
    await waitFor(() => next.cached('sender')?.avatarUrl == getUrl(2));
    await resolve(cache.imageFor(next.cached('sender')!)!);
    expect(downloads, 2);
    expect(
      await disk.readEntry(
        client.storage.url,
        'owner',
        'avatar:sender:${getUrl(1)}',
      ),
      isNull,
    );
  });

  test(
    'same client shares own and visible cache without another download',
    () async {
      final client = await newClient();
      final cache = newImages(client);
      final own = SupabaseProfileService(client: client, avatarCache: cache);
      final visible = SupabaseVisibleAccountAvatarService(
        client: client,
        avatarCache: cache,
      );
      visibleServices.add(visible);
      final profile = await own.loadForUser('owner');
      await resolve(cache.imageFor(profile)!);
      final other = (await visible.load('owner'))!;
      await resolve(cache.imageFor(other)!);
      expect(downloads, 1);
      expect(
        ProfileAvatarImageCache.forClient(client),
        same(ProfileAvatarImageCache.forClient(client)),
      );
      await waitFor(() => replies == 2);
    },
  );

  test('corrupt bytes are discarded and refetched; backend and account namespaces never mix', () async {
    final client = await newClient();
    final first = newImages(client);
    final profile = UserProfile.fromJson(jsonProfile('owner'));
    await first.remember(profile);
    await resolve(first.imageFor(profile)!);
    first.clear();
    await disk.writeEntry(
      client.storage.url,
      'owner',
      'avatar:owner:${getUrl(1)}',
      Uint8List.fromList([0, 1, 2]),
      stillValid: () => true,
    );
    final restarted = newImages(client);
    final restored = (await restarted.readProfile('owner'))!;
    await resolve(restarted.imageFor(restored)!);
    expect(downloads, 2);
    final otherBackend = ProfileAvatarImageCache(
      diskCache: disk,
      backend: 'other-backend',
      owner: 'owner',
    );
    final otherAccount = ProfileAvatarImageCache(
      diskCache: disk,
      backend: client.storage.url,
      owner: 'someone-else',
    );
    images.addAll([otherBackend, otherAccount]);
    expect(await otherBackend.readProfile('owner'), isNull);
    expect(await otherAccount.readProfile('owner'), isNull);
  });

  test('removing an avatar persists and cannot revive its former bytes after restart', () async {
    final client = await newClient();
    final first = newImages(client);
    final profile = UserProfile.fromJson(jsonProfile('owner'));
    await first.remember(profile);
    await resolve(first.imageFor(profile)!);
    await first.remember(
      const UserProfile(id: 'owner', name: 'Pepe', avatarKey: 'avatar_01'),
    );
    first.clear();
    final next = newImages(client);
    final cached = (await next.readProfile('owner'))!;
    expect(cached.avatarUrl, isNull);
    expect(cached.avatarKey, 'avatar_01');
    expect(next.imageFor(cached), isNull);
    expect(
      await disk.readEntry(
        client.storage.url,
        'owner',
        'avatar:owner:${getUrl(1)}',
      ),
      isNull,
    );
    expect(downloads, 1);
  });

  test(
    'authorization revoked by the RPC removes cached metadata and bytes',
    () async {
      final client = await newClient();
      final first = newImages(client);
      final service = SupabaseVisibleAccountAvatarService(
        client: client,
        avatarCache: first,
      );
      visibleServices.add(service);
      final profile = (await service.load('sender'))!;
      await resolve(first.imageFor(profile)!);
      first.clear();
      revoked = true;
      final cache = newImages(client);
      final next = SupabaseVisibleAccountAvatarService(
        client: client,
        avatarCache: cache,
      );
      visibleServices.add(next);
      await next.load('sender');
      await waitFor(() => next.cached('sender') == null);
      expect(
        await disk.readEntry(
          client.storage.url,
          'owner',
          'profile:sender',
          image: false,
        ),
        isNull,
      );
      expect(
        await disk.readEntry(
          client.storage.url,
          'owner',
          'avatar:sender:${getUrl(1)}',
        ),
        isNull,
      );
    },
  );

  test('logout rejects a late download and purges persisted references for that session', () async {
    final client = await newClient();
    final cache = newImages(client);
    imageGate = Completer<void>();
    final profile = UserProfile.fromJson(jsonProfile('owner'));
    await cache.remember(profile);
    final loaded = resolve(cache.imageFor(profile)!);
    final failed = expectLater(loaded, throwsStateError);
    await waitFor(() => downloads == 1);
    await client.auth.signOut(scope: SignOutScope.local);
    release(imageGate);
    await failed;
    await login(client);
    expect(await cache.readProfile('owner'), isNull);
    expect(
      await disk.readEntry(
        client.storage.url,
        'owner',
        'avatar:owner:${getUrl(1)}',
      ),
      isNull,
    );
  });
}
