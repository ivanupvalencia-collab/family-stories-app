import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_stories_app/models/user_profile.dart';
import 'package:family_stories_app/services/profile_avatar_image_cache.dart';
import 'package:family_stories_app/services/profile_service.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These are real asynchronous IO/decode tests, without widget-test fake HTTP.
  HttpOverrides.global = null;
  late HttpServer server;
  late ProfileAvatarImageCache cache;
  var downloads = 0;
  var fail = false;
  var revision = 1;
  Completer<void>? gate;

  UserProfile profile({String id = 'owner', int version = 1}) => UserProfile(
    id: id,
    name: 'Pepe',
    avatarUrl: 'http://127.0.0.1:${server.port}/avatar?v=$version',
  );

  Future<bool> resolve(ImageProvider provider) {
    final done = Completer<bool>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, synchronous) {
        image.dispose();
        stream.removeListener(listener);
        done.complete(synchronous);
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        done.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return done.future.timeout(const Duration(seconds: 5));
  }

  setUp(() async {
    downloads = 0;
    fail = false;
    revision = 1;
    gate = null;
    cache = ProfileAvatarImageCache();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/avatar') {
        downloads++;
        await gate?.future;
        request.response.headers.contentType = ContentType('image', 'png');
        if (fail) {
          request.response.statusCode = 500;
        } else {
          request.response.add(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
          );
        }
      } else if (request.uri.path.startsWith('/auth/')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'owner',
            'name': 'Pepe',
            'avatar_url': profile(version: revision).avatarUrl,
          }),
        );
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    if (gate != null && !gate!.isCompleted) gate!.complete();
    cache.clear();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await server.close(force: true);
  });

  test(
    'preload and simultaneous views share one download; reopen is synchronous',
    () async {
      cache.preload(profile());
      final image = cache.imageFor(profile())!;
      await Future.wait([resolve(image), resolve(cache.imageFor(profile())!)]);
      expect(downloads, 1);
      expect(await resolve(cache.imageFor(profile())!), isTrue);
      expect(downloads, 1);
    },
  );

  test('revision change and removing a photo evict the former image', () async {
    final first = cache.imageFor(profile())!;
    await resolve(first);
    cache.preload(profile(version: 2));
    await resolve(cache.imageFor(profile(version: 2))!);
    expect(downloads, 2);
    expect(PaintingBinding.instance.imageCache.containsKey(first), isFalse);
    final second = cache.imageFor(profile(version: 2))!;
    expect(
      cache.imageFor(
        const UserProfile(id: 'owner', name: 'Pepe', avatarKey: 'avatar_01'),
      ),
      isNull,
    );
    expect(PaintingBinding.instance.imageCache.containsKey(second), isFalse);
  });

  test(
    'accounts, service/backends and cleared sessions have different keys',
    () async {
      final first = cache.imageFor(profile())!;
      await resolve(first);
      final otherAccount = cache.imageFor(profile(id: 'other'))!;
      expect(otherAccount, isNot(first));
      final otherBackend = ProfileAvatarImageCache();
      expect(otherBackend.imageFor(profile()), isNot(first));
      otherBackend.clear();
      cache.clear();
      expect(PaintingBinding.instance.imageCache.containsKey(first), isFalse);
      final newSession = cache.imageFor(profile())!;
      expect(newSession, isNot(first));
      await resolve(newSession);
      expect(downloads, 2);
    },
  );

  test(
    'clear during preload prevents a late result being reused by a new session',
    () async {
      gate = Completer<void>();
      cache.preload(profile());
      final first = cache.imageFor(profile())!;
      cache.clear();
      final next = cache.imageFor(profile())!;
      expect(next, isNot(first));
      final loaded = resolve(next);
      gate!.complete();
      await loaded;
      expect(PaintingBinding.instance.imageCache.containsKey(first), isFalse);
      expect(await resolve(next), isTrue);
      expect(downloads, 2);
    },
  );

  test(
    'failed download is retryable and never fails profile metadata',
    () async {
      fail = true;
      cache.preload(profile());
      await expectLater(
        resolve(cache.imageFor(profile())!),
        throwsA(isA<NetworkImageLoadException>()),
      );
      fail = false;
      cache.preload(profile());
      await resolve(cache.imageFor(profile())!);
      expect(downloads, 2);
    },
  );

  test('profile service clears images on account switch and logout', () async {
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    Future<void> signIn(String id) async {
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
            'user_metadata': {'picture': 'https://google.test/photo'},
            'created_at': '2026-10-18T12:00:00Z',
          },
        }),
      );
    }

    final service = SupabaseProfileService(client: client);
    try {
      await signIn('owner');
      final loaded = await service.loadForUser('owner');
      final first = service.avatarImages.imageFor(loaded)!;
      await resolve(first);
      expect(downloads, 1);
      await signIn('other');
      expect(service.cachedForUser('owner'), isNull);
      expect(PaintingBinding.instance.imageCache.containsKey(first), isFalse);
      final second = service.avatarImages.imageFor(profile(id: 'other'))!;
      await resolve(second);
      await client.auth.signOut();
      expect(service.cachedForUser('other'), isNull);
      expect(PaintingBinding.instance.imageCache.containsKey(second), isFalse);
      expect(
        service.avatarImages.imageFor(profile(id: 'other')),
        isNot(second),
      );
    } finally {
      service.clearCache();
      await client.dispose();
    }
  });

  test('existing profile preload warms the image; refresh reuses it and update invalidates', () async {
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final service = SupabaseProfileService(client: client);
    try {
      final loaded = await service.loadForUser('owner');
      final image = service.avatarImages.imageFor(loaded)!;
      await resolve(image);
      expect(downloads, 1);
      final refreshed = await service.loadForUser('owner', forceRefresh: true);
      expect(await resolve(service.avatarImages.imageFor(refreshed)!), isTrue);
      expect(downloads, 1);
      revision = 2;
      final updated = await service.updateProfile(
        userId: 'owner',
        name: 'Pepe',
        avatarKey: null,
        avatarUrl: profile(version: 2).avatarUrl,
      );
      await resolve(service.avatarImages.imageFor(updated)!);
      expect(downloads, 2);
      expect(PaintingBinding.instance.imageCache.containsKey(image), isFalse);
      service.clearCache();
      expect(service.cachedForUser('owner'), isNull);
    } finally {
      service.clearCache();
      await client.dispose();
    }
  });
}
