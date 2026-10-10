import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/services/family_member_service.dart';
import 'package:family_stories_app/services/remote_family_member_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _PreferenceState {
  final values = <String, List<String>>{};
  int writes = 0;
  bool fail = false;
}

class _Preferences implements SharedPreferencesAsync {
  final _state = _PreferenceState();
  Map<String, List<String>> get values => _state.values;
  int get writes => _state.writes;
  bool get fail => _state.fail;
  set fail(bool value) => _state.fail = value;
  @override
  Future<List<String>?> getStringList(String key) async =>
      values[key]?.toList();
  @override
  Future<void> setStringList(String key, List<String> value) async {
    if (fail) throw StateError('Disk unavailable');
    _state.writes++;
    values[key] = value.toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-10-10T12:00:00Z',
        },
      }),
    )
    .then((_) {});

void main() {
  const owner = 'owner-a';
  late HttpServer server;
  late SupabaseClient client;
  late _Preferences preferences;
  late SupabaseFamilyMemberService service;
  late List<Map<String, dynamic>> rows;
  Completer<void>? gate;
  int requests = 0;

  setUp(() async {
    rows = [
      {
        'id': 'member-a',
        'name': 'Pepe',
        'relationship': 'Padre/Madre',
        'linked_account_id': 'recipient',
        'photo_path': null,
      },
    ];
    gate = null;
    requests = 0;
    preferences = _Preferences();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final bodyBytes = await request.fold<List<int>>(
        [],
        (a, b) => a..addAll(b),
      );
      final body = bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(bodyBytes));
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/auth/v1/logout') {
        request.response.write('{}');
      } else if (request.uri.path.contains('/rpc/')) {
        rows.first['photo_path'] = body['p_photo_path'];
        request.response.write(jsonEncode(rows.first));
      } else if (request.method == 'POST') {
        final row = Map<String, dynamic>.from(body)..['id'] = 'created-id';
        rows.add(row);
        request.response.write(jsonEncode(row));
      } else {
        requests++;
        final result = jsonEncode(rows);
        await gate?.future;
        request.response.write(result);
      }
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await _login(client, owner);
    service = SupabaseFamilyMemberService(
      client: client,
      cache: RemoteFamilyMemberCache(preferences: preferences),
    );
  });
  tearDown(() async {
    gate?.complete();
    await client.dispose();
    await server.close(force: true);
  });

  test('server-confirmed members survive restart, cache hit makes no request, then refresh updates', () async {
    expect(await service.loadCachedForOwner(owner), isNull);
    final remote = await service.loadForOwner(owner);
    final restarted = SupabaseFamilyMemberService(
      client: client,
      cache: RemoteFamilyMemberCache(preferences: preferences),
    );
    expect(
      (await restarted.loadCachedForOwner(owner))!.single.toJson(),
      remote.single.toJson(),
    );
    expect(requests, 1);
    rows.first['name'] = 'Pepe actualizado';
    await restarted.loadForOwner(owner);
    expect(
      (await restarted.loadCachedForOwner(owner))!.single.name,
      'Pepe actualizado',
    );
    expect(requests, 2);
  });

  test('identical remote data does not rewrite preferences', () async {
    await service.loadForOwner(owner);
    await service.loadForOwner(owner);
    expect(preferences.writes, 1);
  });

  for (final single in [false, true]) {
    test(
      'deleted member cannot be restored by a late ${single ? 'profile' : 'list'} response',
      () async {
        await service.loadForOwner(owner);
        gate = Completer<void>();
        final Future<Object?> pending = single
            ? service.loadMemberForOwner(
                ownerId: owner,
                familyMemberId: 'member-a',
              )
            : service.loadForOwner(owner);
        while (requests < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await service.forgetMember(owner, 'member-a');
        gate!.complete();
        gate = null;
        expect(await pending, single ? isNull : isEmpty);
        expect(await service.loadCachedForOwner(owner), isEmpty);
      },
    );
  }

  test(
    'creation before the first complete snapshot persists the confirmed member',
    () async {
      final created = await service.create(
        ownerId: owner,
        name: 'Ana',
        relationship: 'Nieto/a',
      );
      expect((await service.loadCachedForOwner(owner))!.single.id, created.id);
      await service.loadForOwner(owner);
      expect(await service.loadCachedForOwner(owner), hasLength(2));
    },
  );

  test('a delayed old list cannot undo a committed photo change', () async {
    await service.loadForOwner(owner);
    gate = Completer<void>();
    final oldList = service.loadForOwner(owner);
    while (requests < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await service.updatePhoto(
      ownerId: owner,
      familyMemberId: 'member-a',
      photoPath: '$owner/member-a/new.png',
      expectedPhotoPath: null,
    );
    gate!.complete();
    gate = null;
    expect((await oldList).single.photoPath, '$owner/member-a/new.png');
    expect(
      (await service.loadCachedForOwner(owner))!.single.photoPath,
      '$owner/member-a/new.png',
    );
  });

  test('create, photo edits, photo removal and authoritative deletions update cached records', () async {
    await service.loadForOwner(owner);
    final created = await service.create(
      ownerId: owner,
      name: 'Ana',
      relationship: 'Nieto/a',
    );
    expect((await service.loadCachedForOwner(owner))!.last.id, created.id);
    await service.updatePhoto(
      ownerId: owner,
      familyMemberId: 'member-a',
      photoPath: '$owner/member-a/photo.png',
      expectedPhotoPath: null,
    );
    expect(
      (await service.loadCachedForOwner(owner))!.first.photoPath,
      '$owner/member-a/photo.png',
    );
    await service.updatePhoto(
      ownerId: owner,
      familyMemberId: 'member-a',
      photoPath: null,
      expectedPhotoPath: '$owner/member-a/photo.png',
    );
    expect((await service.loadCachedForOwner(owner))!.first.photoPath, isNull);
    rows.clear();
    await service.loadForOwner(owner);
    expect(await service.loadCachedForOwner(owner), isEmpty);
  });

  test('account switch/logout cannot read previous account cache, backend namespaces are separate', () async {
    await service.loadForOwner(owner);
    final cache = RemoteFamilyMemberCache(preferences: preferences);
    await cache.replace(client.storage.url, 'owner-b', [
      const FamilyMember(id: 'b', name: 'B', relationship: 'Otro'),
    ]);
    await _login(client, 'owner-b');
    await expectLater(service.loadCachedForOwner(owner), throwsStateError);
    expect((await service.loadCachedForOwner('owner-b'))!.single.name, 'B');
    expect(await cache.read('another-backend', 'owner-b'), isNull);
    await client.auth.signOut(scope: SignOutScope.local);
    await expectLater(service.loadCachedForOwner('owner-b'), throwsStateError);
    await _login(client, owner);
    expect((await service.loadCachedForOwner(owner))!.single.name, 'Pepe');
  });

  test(
    'late server results cannot cross logout/login to the same account',
    () async {
      gate = Completer<void>();
      final pending = service.loadForOwner(owner);
      final failure = expectLater(pending, throwsStateError);
      while (requests == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await client.auth.signOut(scope: SignOutScope.local);
      await _login(client, owner);
      gate!.complete();
      gate = null;
      await failure;
      expect(await service.loadCachedForOwner(owner), isNull);
    },
  );

  test('broken preferences and cache write failures do not block valid server data', () async {
    await service.loadForOwner(owner);
    preferences.values.updateAll((key, value) => ['broken json']);
    expect(await service.loadCachedForOwner(owner), isNull);
    preferences.fail = true;
    expect((await service.loadForOwner(owner)).single.name, 'Pepe');
  });
}
