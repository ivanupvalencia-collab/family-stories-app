import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/services/family_member_photo_service.dart';
import 'package:family_stories_app/services/family_member_service.dart';
import 'package:family_stories_app/services/family_member_storage.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/services/remote_family_photo_disk_cache.dart';
import 'package:family_stories_app/services/remote_family_member_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _image = PickedProfileImage(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
  contentType: 'image/png',
);
const _member = FamilyMember(
  id: 'member-id',
  name: 'Pepe',
  relationship: 'Padre/Madre',
  linkedAccountId: 'linked-user',
);

class _PreferenceState {
  List<String>? values;
  bool failSave = false;
}

class _Preferences implements SharedPreferencesAsync {
  final _state = _PreferenceState();
  List<String>? get values => _state.values;
  set values(List<String>? value) => _state.values = value;
  bool get failSave => _state.failSave;
  set failSave(bool value) => _state.failSave = value;

  @override
  Future<List<String>?> getStringList(String key) async =>
      values == null ? null : List.of(values!);
  @override
  Future<void> setStringList(String key, List<String> value) async {
    if (failSave) throw StateError('Persistence failed.');
    values = List.of(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('local photos and SharedPreferences', () {
    late Directory directory;
    late _Preferences preferences;
    late SharedPreferencesFamilyMemberStorage storage;
    late LocalFamilyMemberPhotoService photos;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('family_photos_test_');
      preferences = _Preferences();
      storage = SharedPreferencesFamilyMemberStorage(preferences: preferences);
      await storage.save([_member]);
      photos = LocalFamilyMemberPhotoService(
        storage: storage,
        directoryProvider: () async => directory,
      );
    });
    tearDown(() async => directory.delete(recursive: true));

    test('old local and remote members without photos remain compatible', () {
      expect(
        FamilyMember.fromJson({
          'id': 'old',
          'name': 'Pepe',
          'relationship': 'Otro',
        }).photoPath,
        isNull,
      );
      expect(
        FamilyMember.fromSupabaseJson({
          'id': 'old',
          'name': 'Pepe',
          'relationship': 'Otro',
          'linked_account_id': 'linked',
        }).photoPath,
        isNull,
      );
      final updated = _member.withPhotoPath('own.png');
      expect(FamilyMember.fromJson(updated.toJson()).photoPath, 'own.png');
      expect(updated.linkedAccountId, _member.linkedAccountId);
      expect(updated.name, _member.name);
      expect(updated.relationship, _member.relationship);
    });

    test(
      'legacy id migration survives a restart and preserves a photo reference',
      () async {
        preferences.values = [
          jsonEncode({'name': 'Legacy', 'relationship': 'Otro'}),
        ];
        final migrated = (await storage.load()).single;
        expect(migrated.id, isNotEmpty);
        expect(migrated.photoPath, isNull);
        expect(
          (await SharedPreferencesFamilyMemberStorage(
            preferences: preferences,
          ).load()).single.id,
          migrated.id,
        );
      },
    );

    test('copies bytes to private support storage and persists a portable reference', () async {
      final updated = await photos.save(_member, _image);
      expect(updated.photoPath, startsWith('family_member_photos/member-id/'));
      expect(File(updated.photoPath!).isAbsolute, isFalse);
      final restartedStorage = SharedPreferencesFamilyMemberStorage(
        preferences: preferences,
      );
      final restartedMember = (await restartedStorage.load()).single;
      final restartedPhotos = LocalFamilyMemberPhotoService(
        storage: restartedStorage,
        directoryProvider: () async => directory,
      );
      expect(await restartedPhotos.load(restartedMember), _image.bytes);
      expect(restartedMember.linkedAccountId, 'linked-user');
    });

    test('replacement and removal delete old files only after reference persistence', () async {
      final first = await photos.save(_member, _image);
      final second = await photos.save(first, _image);
      expect(second.photoPath, isNot(first.photoPath));
      expect(
        await File('${directory.path}/${first.photoPath}').exists(),
        isFalse,
      );
      expect(await photos.load(second), _image.bytes);
      final removed = await photos.save(second, null);
      expect(removed.photoPath, isNull);
      expect((await storage.load()).single.photoPath, isNull);
      expect(
        await File('${directory.path}/${second.photoPath}').exists(),
        isFalse,
      );
      expect(removed.linkedAccountId, 'linked-user');
    });

    test(
      'failed persistence preserves old photo and removes only staged bytes',
      () async {
        final original = await photos.save(_member, _image);
        preferences.failSave = true;
        await expectLater(photos.save(original, _image), throwsStateError);
        await expectLater(photos.save(original, null), throwsStateError);
        expect((await storage.load()).single.photoPath, original.photoPath);
        expect(await photos.load(original), _image.bytes);
        expect(
          await directory.list(recursive: true).where((e) => e is File).length,
          1,
        );
      },
    );

    test(
      'invalid and oversized photos leave existing references untouched',
      () async {
        final original = await photos.save(_member, _image);
        for (final image in [
          PickedProfileImage(bytes: Uint8List(0), contentType: 'image/png'),
          PickedProfileImage(
            bytes: Uint8List(10 * 1024 * 1024 + 1),
            contentType: 'image/png',
          ),
          PickedProfileImage(
            bytes: Uint8List.fromList([1]),
            contentType: 'text/html',
          ),
        ]) {
          await expectLater(
            photos.save(original, image),
            throwsFormatException,
          );
        }
        expect((await storage.load()).single.photoPath, original.photoPath);
        expect(await photos.load(original), _image.bytes);
      },
    );

    test('never reads or deletes paths outside the member directory', () async {
      final protected = File('${directory.path}/protected.txt');
      await protected.writeAsString('keep');
      final invalid = _member.withPhotoPath('../protected.txt');
      await storage.save([invalid]);
      await expectLater(photos.load(invalid), throwsFormatException);
      await photos.save(invalid, null);
      expect(await protected.readAsString(), 'keep');
    });
  });

  group('private remote photo contract', () {
    late HttpServer server;
    late SupabaseClient client;
    late SupabaseFamilyMemberService members;
    late SupabaseFamilyMemberPhotoService photos;
    late Map<String, dynamic> memberJson;
    late Set<String> objects;
    late List<({String method, Uri uri, String? auth, dynamic body})> requests;
    late bool failUpload;
    late bool failUpdate;
    late bool loseUpdateResponse;
    late bool failCleanup;
    bool emptyDownload = false;
    Completer<void>? downloadGate;
    late Directory remoteDirectory;
    late RemoteFamilyPhotoDiskCache disk;
    const owner = '11111111-1111-4111-8111-111111111111';
    const id = '22222222-2222-4222-8222-222222222222';
    const oldPath = '$owner/$id/old.png';

    setUp(() async {
      remoteDirectory = await Directory.systemTemp.createTemp(
        'remote_photos_test_',
      );
      disk = RemoteFamilyPhotoDiskCache(
        directoryProvider: () async => remoteDirectory,
      );
      memberJson = {
        'id': id,
        'name': 'Pepe',
        'relationship': 'Padre/Madre',
        'linked_account_id': 'linked-user',
        'photo_path': oldPath,
      };
      objects = {oldPath};
      requests = [];
      failUpload = false;
      failUpdate = false;
      loseUpdateResponse = false;
      failCleanup = false;
      emptyDownload = false;
      downloadGate = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final bytes = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        final isJson =
            request.headers.contentType?.mimeType == 'application/json';
        final body = isJson && bytes.isNotEmpty
            ? jsonDecode(utf8.decode(bytes))
            : null;
        requests.add((
          method: request.method,
          uri: request.uri,
          auth: request.headers.value('authorization'),
          body: body,
        ));
        final path = request.uri.path;
        request.response.headers.contentType = ContentType.json;
        if (path == '/rest/v1/family_members') {
          request.response.write(
            jsonEncode(
              request.headers.value('accept')?.contains('vnd.pgrst.object') ==
                      true
                  ? memberJson
                  : [memberJson],
            ),
          );
        } else if (path == '/rest/v1/rpc/set_family_member_photo') {
          if (!failUpdate) memberJson['photo_path'] = body['p_photo_path'];
          if (failUpdate || loseUpdateResponse) {
            request.response.statusCode = 409;
            request.response.write(
              jsonEncode({'code': '40001', 'message': 'Update failed'}),
            );
          } else {
            request.response.write(jsonEncode(memberJson));
          }
        } else if (path == '/auth/v1/logout') {
          request.response.write('{}');
        } else if (request.method == 'POST') {
          if (failUpload) {
            request.response.statusCode = 403;
            request.response.write(jsonEncode({'message': 'denied'}));
          } else {
            final objectPath = path.substring(
              '/storage/v1/object/family-member-photos/'.length,
            );
            objects.add(objectPath);
            request.response.write(
              jsonEncode({'Key': 'family-member-photos/$objectPath'}),
            );
          }
        } else if (request.method == 'DELETE') {
          if (failCleanup) {
            request.response.statusCode = 403;
            request.response.write(jsonEncode({'message': 'denied'}));
          } else {
            for (final name in body['prefixes'] as List) {
              objects.remove(name);
            }
            request.response.write('[]');
          }
        } else if (request.method == 'GET') {
          await downloadGate?.future;
          request.response.headers.contentType = ContentType('image', 'png');
          if (!emptyDownload) request.response.add(_image.bytes);
        }
        await request.response.close();
      });
      client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await client.auth.recoverSession(
        jsonEncode({
          'access_token': 'test-user-token',
          'refresh_token': 'test-refresh-token',
          'token_type': 'bearer',
          'expires_in': 3600,
          'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          'user': {
            'id': owner,
            'aud': 'authenticated',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-10-10T12:00:00Z',
          },
        }),
      );
      members = SupabaseFamilyMemberService(
        client: client,
        cache: RemoteFamilyMemberCache(preferences: _Preferences()),
      );
      photos = SupabaseFamilyMemberPhotoService(
        ownerId: owner,
        memberService: members,
        client: client,
        diskCache: disk,
      );
    });
    tearDown(() async {
      await client.dispose();
      await server.close(force: true);
      await remoteDirectory.delete(recursive: true);
    });

    test(
      'member deletion invalidates shared memory and persistent family photo',
      () async {
        final member = FamilyMember.fromSupabaseJson(memberJson);
        await photos.load(member);
        final other = SupabaseFamilyMemberPhotoService(
          ownerId: owner,
          memberService: members,
          client: client,
          diskCache: disk,
        );
        expect(other.cachedPhoto(member), isNotNull);
        await photos.forgetPhotos(owner, [oldPath]);
        expect(other.cachedPhoto(member), isNull);
        expect(await disk.read(client.storage.url, owner, oldPath), isNull);
      },
    );
    test(
      'shares cached bytes and concurrent downloads across screen services',
      () async {
        final member = FamilyMember.fromSupabaseJson(memberJson);
        final other = SupabaseFamilyMemberPhotoService(
          ownerId: owner,
          memberService: members,
          client: client,
        );
        final results = await Future.wait([
          photos.load(member),
          other.load(member),
        ]);
        expect(identical(results.first, results.last), isTrue);
        expect(identical(other.cachedPhoto(member), results.first), isTrue);
        expect(identical(await other.load(member), results.first), isTrue);
        expect(requests.where((r) => r.method == 'GET'), hasLength(1));
        expect(
          other.cachedPhoto(member.withPhotoPath('$owner/$id/other.png')),
          isNull,
        );
        final wrongOwner = SupabaseFamilyMemberPhotoService(
          ownerId: 'another-user',
          memberService: members,
          client: client,
        );
        expect(wrongOwner.cachedPhoto(member), isNull);
      },
    );

    test('empty downloads are not cached and can be retried', () async {
      final member = FamilyMember.fromSupabaseJson(memberJson);
      emptyDownload = true;
      await expectLater(photos.load(member), throwsStateError);
      expect(photos.cachedPhoto(member), isNull);
      emptyDownload = false;
      expect(await photos.load(member), _image.bytes);
      expect(requests.where((r) => r.method == 'GET'), hasLength(2));
    });

    Future<SupabaseClient> restartedClient() async {
      final restarted = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await restarted.auth.recoverSession(
        jsonEncode(client.auth.currentSession!.toJson()),
      );
      addTearDown(restarted.dispose);
      return restarted;
    }

    test('persistent photo survives restart and warms synchronously accessible memory', () async {
      final member = FamilyMember.fromSupabaseJson(memberJson);
      await photos.load(member);
      final restarted = await restartedClient();
      final service = SupabaseFamilyMemberPhotoService(
        ownerId: owner,
        memberService: members,
        client: restarted,
        diskCache: RemoteFamilyPhotoDiskCache(
          directoryProvider: () async => remoteDirectory,
        ),
      );
      expect(service.cachedPhoto(member), isNull);
      await service.warmCachedPhotos([member]);
      expect(service.cachedPhoto(member), _image.bytes);
      expect(await service.load(member), _image.bytes);
      expect(
        requests.where(
          (r) => r.uri.path.contains('/storage/') && r.method == 'GET',
        ),
        hasLength(1),
      );
    });

    test(
      'missing, empty and corrupt disk files are downloaded again',
      () async {
        final member = FamilyMember.fromSupabaseJson(memberJson);
        await photos.load(member);
        for (final content in [
          null,
          <int>[],
          <int>[1, 2, 3, 4],
        ]) {
          final file =
              (await remoteDirectory
                          .list(recursive: true)
                          .where((f) => f is File)
                          .toList())
                      .single
                  as File;
          if (content == null) {
            await file.delete();
          } else {
            await file.writeAsBytes(content, flush: true);
          }
          final restarted = await restartedClient();
          final service = SupabaseFamilyMemberPhotoService(
            ownerId: owner,
            memberService: members,
            client: restarted,
            diskCache: disk,
          );
          expect(await service.load(member), _image.bytes);
        }
        expect(
          requests.where(
            (r) => r.uri.path.contains('/storage/') && r.method == 'GET',
          ),
          hasLength(4),
        );
      },
    );

    test(
      'changed path and deleted member prune memory and persisted old photos',
      () async {
        final member = FamilyMember.fromSupabaseJson(memberJson);
        await photos.load(member);
        final changed = member.withPhotoPath('$owner/$id/changed.png');
        await photos.retainPhotos([changed]);
        expect(photos.cachedPhoto(member), isNull);
        expect(
          await remoteDirectory
              .list(recursive: true)
              .where((f) => f is File)
              .length,
          0,
        );
        await photos.load(changed);
        await photos.retainPhotos([]);
        expect(photos.cachedPhoto(changed), isNull);
        expect(
          await remoteDirectory
              .list(recursive: true)
              .where((f) => f is File)
              .length,
          0,
        );
      },
    );

    test(
      'replacement and deletion invalidate disk entries across restart',
      () async {
        final member = FamilyMember.fromSupabaseJson(memberJson);
        await photos.load(member);
        final updated = await photos.save(member, _image);
        expect(await disk.read(client.storage.url, owner, oldPath), isNull);
        expect(
          await disk.read(client.storage.url, owner, updated.photoPath!),
          _image.bytes,
        );
        final restarted = await restartedClient();
        final service = SupabaseFamilyMemberPhotoService(
          ownerId: owner,
          memberService: members,
          client: restarted,
          diskCache: disk,
        );
        await service.warmCachedPhotos([updated]);
        expect(service.cachedPhoto(updated), _image.bytes);
        await photos.save(updated, null);
        expect(
          await disk.read(client.storage.url, owner, updated.photoPath!),
          isNull,
        );
      },
    );

    test('account switch and logout discard previous session photos', () async {
      final member = FamilyMember.fromSupabaseJson(memberJson);
      final session = client.auth.currentSession!.toJson();
      await photos.load(member);
      final otherSession = Map<String, dynamic>.from(session);
      otherSession['user'] = {
        ...Map<String, dynamic>.from(session['user']),
        'id': 'another-user',
      };
      await client.auth.recoverSession(jsonEncode(otherSession));
      expect(photos.cachedPhoto(member), isNull);
      await expectLater(photos.load(member), throwsStateError);
      await client.auth.recoverSession(jsonEncode(session));
      expect(photos.cachedPhoto(member), isNull);
      await photos.load(member);
      await client.auth.signOut(scope: SignOutScope.local);
      expect(photos.cachedPhoto(member), isNull);
      await client.auth.recoverSession(jsonEncode(session));
      expect(photos.cachedPhoto(member), isNull);
      await photos.load(member);
      expect(
        requests.where(
          (r) => r.uri.path.contains('/storage/') && r.method == 'GET',
        ),
        hasLength(
          1,
        ), // Returning to the same account can use its private disk cache.
      );
    });

    test('a pending download cannot restore a removed photo', () async {
      final member = FamilyMember.fromSupabaseJson(memberJson);
      downloadGate = Completer<void>();
      final pending = photos.load(member);
      final failure = expectLater(pending, throwsStateError);
      // Wait until the real HTTP download has reached the test server.
      while (!requests.any((r) => r.method == 'GET')) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await photos.save(member, null);
      downloadGate!.complete();
      await failure;
      expect(photos.cachedPhoto(member), isNull);
    });

    test(
      'a pending download cannot cross logout and login to the same account',
      () async {
        final member = FamilyMember.fromSupabaseJson(memberJson);
        final session = jsonEncode(client.auth.currentSession!.toJson());
        downloadGate = Completer<void>();
        final pending = photos.load(member);
        final failure = expectLater(pending, throwsStateError);
        while (!requests.any((r) => r.method == 'GET')) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await client.auth.signOut(scope: SignOutScope.local);
        await client.auth.recoverSession(session);
        downloadGate!.complete();
        await failure;
        expect(photos.cachedPhoto(member), isNull);
        expect(await photos.load(member), _image.bytes);
      },
    );

    test(
      'replacement uses private authenticated Storage and narrowly scoped RPC',
      () async {
        final original = FamilyMember.fromSupabaseJson(memberJson);
        await photos.load(original);
        final updated = await photos.save(original, _image);
        expect(photos.cachedPhoto(original), isNull);
        expect(photos.cachedPhoto(updated), same(_image.bytes));
        expect(updated.photoPath, startsWith('$owner/$id/'));
        expect(updated.photoPath, isNot(oldPath));
        expect(updated.linkedAccountId, 'linked-user');
        expect(objects, {updated.photoPath});
        final rpc = requests.firstWhere((r) => r.uri.path.contains('/rpc/'));
        expect(rpc.body, {
          'p_family_member_id': id,
          'p_photo_path': updated.photoPath,
          'p_expected_photo_path': oldPath,
        });
        expect(
          requests.every((r) => r.auth == 'Bearer test-user-token'),
          isTrue,
        );
        expect(requests.any((r) => r.uri.path.contains('profiles')), isFalse);
        final count = requests.length;
        expect(await photos.load(updated), _image.bytes);
        expect(requests, hasLength(count));
        final removed = await photos.save(updated, null);
        expect(photos.cachedPhoto(updated), isNull);
        expect(removed.photoPath, isNull);
        expect(objects, isEmpty);
      },
    );

    test(
      'upload errors preserve the old database reference and object',
      () async {
        failUpload = true;
        await expectLater(
          photos.save(FamilyMember.fromSupabaseJson(memberJson), _image),
          throwsA(isA<StorageException>()),
        );
        expect(memberJson['photo_path'], oldPath);
        expect(objects, {oldPath});
        expect(requests.any((r) => r.uri.path.contains('/rpc/')), isFalse);
      },
    );

    test(
      'failed reference update rolls back staged photo, retaining old photo',
      () async {
        failUpdate = true;
        final original = FamilyMember.fromSupabaseJson(memberJson);
        final cached = await photos.load(original);
        await expectLater(
          photos.save(FamilyMember.fromSupabaseJson(memberJson), _image),
          throwsA(isA<PostgrestException>()),
        );
        expect(memberJson['photo_path'], oldPath);
        expect(objects, {oldPath});
        expect(photos.cachedPhoto(original), same(cached));
      },
    );

    test(
      'a committed update with a lost response never deletes the active image',
      () async {
        loseUpdateResponse = true;
        final updated = await photos.save(
          FamilyMember.fromSupabaseJson(memberJson),
          _image,
        );
        expect(memberJson['photo_path'], updated.photoPath);
        expect(objects, {updated.photoPath});
      },
    );

    test(
      'cleanup failure does not undo a successful photo replacement',
      () async {
        failCleanup = true;
        final updated = await photos.save(
          FamilyMember.fromSupabaseJson(memberJson),
          _image,
        );
        expect(memberJson['photo_path'], updated.photoPath);
        expect(objects, {oldPath, updated.photoPath});
      },
    );

    test(
      'a different owner session is rejected before any remote operation',
      () async {
        final wrongOwner = SupabaseFamilyMemberPhotoService(
          ownerId: 'different-user',
          memberService: members,
          client: client,
        );
        final original = FamilyMember.fromSupabaseJson(memberJson);
        await expectLater(wrongOwner.save(original, _image), throwsStateError);
        await expectLater(wrongOwner.load(original), throwsStateError);
        expect(requests, isEmpty);
      },
    );

    test('reads include nullable photo_path without replacing linked account metadata', () async {
      memberJson['photo_path'] = null;
      final loaded = (await members.loadForOwner(owner)).single;
      expect(loaded.photoPath, isNull);
      expect(loaded.linkedAccountId, 'linked-user');
      expect(
        requests.single.uri.queryParameters['select'],
        contains('photo_path'),
      );
      expect(requests.single.uri.queryParameters['owner_id'], 'eq.$owner');
    });
  });
}
