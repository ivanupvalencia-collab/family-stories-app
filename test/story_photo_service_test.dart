import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_stories_app/models/family_member.dart';
import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/services/family_story_storage.dart';
import 'package:family_stories_app/services/story_photo_service.dart';
import 'package:family_stories_app/services/profile_image_picker.dart';
import 'package:family_stories_app/services/remote_family_photo_disk_cache.dart';
import 'package:family_stories_app/services/question_of_the_day.dart';
import 'package:family_stories_app/data/predefined_questions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'widget_test.dart' as fixtures;

class _Preferences implements SharedPreferencesAsync {
  final values = <String, List<String>>{};
  @override
  Future<List<String>?> getStringList(String key) async =>
      values[key]?.toList();
  @override
  Future<void> setStringList(String key, List<String> value) async {
    values[key] = value.toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingMembers extends fixtures.MemoryFamilyMemberStorage {
  _FailingMembers({required super.members});
  @override
  Future<void> save(List<FamilyMember> members) async =>
      throw StateError('Member write failed');
}

FamilyStory _story({
  String id = 'story',
  String question = 'Un recuerdo',
  String? path,
}) => FamilyStory(
  id: id,
  familyMemberId: 'member',
  question: question,
  audioPath: '/audio.m4a',
  duration: const Duration(seconds: 12),
  createdAt: DateTime(2026, 10, 10),
  photoPath: path,
);
Future<void> _login(SupabaseClient client, String id) async {
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': 'token-$id',
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
  );
}

void main() {
  test('old stories without photo and photo JSON round trip retain every audio field', () {
    final json = _story().toJson()..remove('photoPath');
    expect(FamilyStory.fromJson(json).photoPath, isNull);
    final updated = _story(path: 'story_photos/story/p.png');
    expect(FamilyStory.fromJson(updated.toJson()).toJson(), updated.toJson());
    expect(updated.audioPath, '/audio.m4a');
    expect(updated.duration.inSeconds, 12);
  });
  test('daily question is stable, excludes answered, keeps selection after other answers, and has full catalog fallback', () {
    final day = DateTime(2026, 10, 10);
    final selected = questionOfTheDay('member', day, []);
    expect(questionOfTheDay('member', day, []).text, selected.text);
    final catalog = predefinedQuestionCategories
        .expand((c) => c.questions)
        .toList();
    final other = catalog.firstWhere((q) => q.text != selected.text);
    expect(
      questionOfTheDay('member', day, [_story(question: other.text)]).text,
      selected.text,
    );
    expect(
      questionOfTheDay('member', day, [_story(question: selected.text)]).text,
      isNot(selected.text),
    );
    expect(
      catalog.map((q) => q.text),
      contains(
        questionOfTheDay(
          'member',
          day,
          catalog.map((q) => _story(question: q.text)).toList(),
        ).text,
      ),
    );
  });
  group('local story photographs and safe member deletion', () {
    late Directory directory;
    late _Preferences preferences;
    late LocalFamilyStoryStorage storage;
    late LocalStoryPhotoService photos;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('local_story_photos_');
      preferences = _Preferences();
      storage = LocalFamilyStoryStorage(
        preferences: preferences,
        documentsProvider: () async => directory,
        supportProvider: () async => directory,
      );
      photos = LocalStoryPhotoService(
        storage: storage,
        directoryProvider: () async => directory,
      );
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });
    Future<FamilyStory> recording() async {
      final audio = File('${directory.path}/recording.m4a');
      await audio.writeAsBytes([1, 2, 3]);
      return storage.saveRecording(
        familyMemberId: 'member',
        question: 'Un recuerdo',
        temporaryAudioPath: audio.path,
        duration: const Duration(seconds: 12),
      );
    }

    test('optional photo persists across restart, replaces then removes without changing audio', () async {
      final original = await recording();
      expect(original.photoPath, isNull);
      final first = await photos.save(original, fixtures.testPickedImage);
      final restarted = LocalStoryPhotoService(
        storage: LocalFamilyStoryStorage(preferences: preferences),
        directoryProvider: () async => directory,
      );
      expect(
        await restarted.load((await storage.loadForFamily('member')).single),
        fixtures.testPickedImage.bytes,
      );
      final second = await photos.save(first, fixtures.testPickedImage);
      expect(
        await File('${directory.path}/${first.photoPath}').exists(),
        isFalse,
      );
      expect(second.audioPath, original.audioPath);
      final removed = await photos.save(second, null);
      expect(removed.photoPath, isNull);
      expect(
        await File('${directory.path}/${second.photoPath}').exists(),
        isFalse,
      );
      expect(await File(original.audioPath).readAsBytes(), [1, 2, 3]);
    });
    test('invalid photo leaves recording and previous photo valid', () async {
      final first = await photos.save(
        await recording(),
        fixtures.testPickedImage,
      );
      await expectLater(
        photos.save(
          first,
          PickedProfileImage(bytes: Uint8List(0), contentType: 'image/png'),
        ),
        throwsFormatException,
      );
      expect(
        (await storage.loadForFamily('member')).single.photoPath,
        first.photoPath,
      );
      expect(await photos.load(first), fixtures.testPickedImage.bytes);
    });
    test(
      'failed member deletion restores story references and keeps files',
      () async {
        final story = await photos.save(
          await recording(),
          fixtures.testPickedImage,
        );
        final members = _FailingMembers(
          members: [
            const FamilyMember(
              id: 'member',
              name: 'Pepe',
              relationship: 'Otro',
            ),
          ],
        );
        await expectLater(
          storage.deleteFamily('member', members),
          throwsStateError,
        );
        expect(members.members, hasLength(1));
        expect(
          (await storage.loadForFamily('member')).single.photoPath,
          story.photoPath,
        );
        expect(await File(story.audioPath).exists(), isTrue);
        expect(await photos.load(story), fixtures.testPickedImage.bytes);
      },
    );
    test('deleting local member removes its stories/audio/photos and preserves other members', () async {
      final story = await photos.save(
        await recording(),
        fixtures.testPickedImage,
      );
      final memberPhotos = Directory(
        '${directory.path}/family_member_photos/member',
      );
      await memberPhotos.create(recursive: true);
      await File('${memberPhotos.path}/photo.png').writeAsBytes([1]);
      final members = fixtures.MemoryFamilyMemberStorage(
        members: [
          const FamilyMember(id: 'member', name: 'Pepe', relationship: 'Otro'),
          const FamilyMember(id: 'other', name: 'Ana', relationship: 'Otro'),
        ],
      );
      await storage.deleteFamily('member', members);
      expect(members.members.single.id, 'other');
      expect(await storage.loadForFamily('member'), isEmpty);
      expect(await File(story.audioPath).exists(), isFalse);
      expect(
        await File('${directory.path}/${story.photoPath}').exists(),
        isFalse,
      );
      expect(await memberPhotos.exists(), isFalse);
    });
  });
  group('private remote story photo contract', () {
    const owner = '11111111-1111-4111-8111-111111111111';
    const id = '22222222-2222-4222-8222-222222222222';
    const oldPath = '$owner/$id/old.png';
    late Directory directory;
    late HttpServer server;
    late SupabaseClient client;
    late Map<String, dynamic> row;
    late SupabaseStoryPhotoService photos;
    late RemoteFamilyPhotoDiskCache disk;
    final requests = <({String method, String path, dynamic body})>[];
    bool forbidden = false, lostCommit = false, failCommit = false;
    Completer<void>? gate;
    setUp(() async {
      forbidden = false;
      lostCommit = false;
      failCommit = false;
      gate = null;
      requests.clear();
      directory = await Directory.systemTemp.createTemp('remote_story_photos_');
      disk = RemoteFamilyPhotoDiskCache(
        directoryProvider: () async => directory,
        directoryName: 'remote_story_photos_v1',
        allowForeignUploader: true,
      );
      row = {
        'id': id,
        'family_member_id': 'member',
        'question': 'Un recuerdo',
        'audio_path': 'request/audio.m4a',
        'duration_seconds': 12,
        'created_at': '2026-10-10T12:00:00Z',
        'recorded_by': owner,
        'photo_path': oldPath,
        'can_edit': true,
      };
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        final body =
            request.headers.contentType?.mimeType == 'application/json' &&
                bytes.isNotEmpty
            ? jsonDecode(utf8.decode(bytes))
            : null;
        requests.add((
          method: request.method,
          path: request.uri.path,
          body: body,
        ));
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/auth/v1/logout') {
          request.response.write('{}');
        } else if (forbidden) {
          request.response.statusCode = 403;
          request.response.write('{"message":"denied","code":"42501"}');
        } else if (request.uri.path.endsWith('/get_story_photo_metadata')) {
          request.response.write(jsonEncode(row));
        } else if (request.uri.path.endsWith('/set_story_photo')) {
          if (!failCommit) {
            row['photo_path'] = body['p_photo_path'];
          }
          if (lostCommit || failCommit) {
            request.response.statusCode = 409;
            request.response.write(
              '{"message":"lost response","code":"40001"}',
            );
          } else {
            request.response.write(jsonEncode(row));
          }
        } else if (request.method == 'GET') {
          await gate?.future;
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(fixtures.testPickedImage.bytes);
        } else {
          request.response.write(
            request.method == 'DELETE' ? '[]' : '{"Key":"uploaded"}',
          );
        }
        await request.response.close();
      });
      client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await _login(client, owner);
      photos = SupabaseStoryPhotoService(client: client, diskCache: disk);
    });
    tearDown(() async {
      await client.dispose();
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    FamilyStory story() => FamilyStory.fromSupabaseJson(row);
    int downloads() => requests
        .where((r) => r.method == 'GET' && r.path.contains('/storage/'))
        .length;
    test(
      'member deletion invalidates shared photo memory and persistent bytes',
      () async {
        final item = story();
        await photos.load(item);
        final other = SupabaseStoryPhotoService(
          client: client,
          diskCache: disk,
        );
        expect(other.cachedPhoto(item), isNotNull);
        await photos.forgetPhotos(owner, [oldPath]);
        expect(other.cachedPhoto(item), isNull);
        expect(await disk.read(client.storage.url, owner, oldPath), isNull);
      },
    );
    test('concurrent downloads deduplicate, memory is shared, persistent photo survives restart', () async {
      final item = story();
      final other = SupabaseStoryPhotoService(client: client, diskCache: disk);
      final loaded = await Future.wait([photos.load(item), other.load(item)]);
      expect(loaded.first, same(loaded.last));
      expect(downloads(), 1);
      expect(other.cachedPhoto(item), same(loaded.first));
      final restarted = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await _login(restarted, owner);
      try {
        expect(
          await SupabaseStoryPhotoService(
            client: restarted,
            diskCache: disk,
          ).load(item),
          loaded.first,
        );
      } finally {
        await restarted.dispose();
      }
      expect(downloads(), 1);
    });
    test('replacement/removal commits reference first, clears old caches and retains audio', () async {
      final original = story();
      await photos.load(original);
      final updated = await photos.save(original, fixtures.testPickedImage);
      expect(updated.audioPath, original.audioPath);
      expect(updated.photoPath, isNot(oldPath));
      expect(photos.cachedPhoto(original), isNull);
      expect(photos.cachedPhoto(updated), fixtures.testPickedImage.bytes);
      expect(await disk.read(client.storage.url, owner, oldPath), isNull);
      final commit = requests.indexWhere(
        (r) => r.path.endsWith('/set_story_photo'),
      );
      final cleanup = requests.indexWhere((r) => r.method == 'DELETE');
      expect(commit, lessThan(cleanup));
      final removed = await photos.save(updated, null);
      expect(removed.photoPath, isNull);
      expect(
        await disk.read(client.storage.url, owner, updated.photoPath!),
        isNull,
      );
    });
    test('lost commit response confirms metadata and never deletes the active upload', () async {
      lostCommit = true;
      final updated = await photos.save(story(), fixtures.testPickedImage);
      expect(updated.photoPath, row['photo_path']);
      final deletions = requests
          .where((r) => r.method == 'DELETE')
          .map((r) => r.body['prefixes']);
      expect(deletions, [
        [oldPath],
      ]);
    });
    test('failed reference update removes staged object and preserves old photo/audio', () async {
      final original = story();
      final cached = await photos.load(original);
      failCommit = true;
      await expectLater(
        photos.save(original, fixtures.testPickedImage),
        throwsA(isA<PostgrestException>()),
      );
      expect(row['photo_path'], oldPath);
      expect(photos.cachedPhoto(original), same(cached));
      expect(await disk.read(client.storage.url, owner, oldPath), cached);
      final deletion = requests.singleWhere((r) => r.method == 'DELETE');
      expect((deletion.body['prefixes'] as List).single, isNot(oldPath));
    });
    test('empty/corrupt/missing persisted files redownload without modifying Storage originals', () async {
      final item = story();
      await photos.load(item);
      for (final content in [
        null,
        <int>[],
        <int>[1, 2, 3],
      ]) {
        final file =
            (await directory
                        .list(recursive: true)
                        .where((f) => f is File)
                        .toList())
                    .single
                as File;
        if (content == null) {
          await file.delete();
        } else {
          await file.writeAsBytes(content);
        }
        // Session reset empties memory, but keeps this account's disk namespace.
        await client.auth.signOut(scope: SignOutScope.local);
        await _login(client, owner);
        expect(await photos.load(item), fixtures.testPickedImage.bytes);
      }
      expect(downloads(), 4);
      expect(
        requests.any((r) => r.method == 'POST' && r.path.contains('/storage/')),
        isFalse,
      );
    });
    test('authorization failure and account/logout cannot expose another account memory', () async {
      final item = story();
      await photos.load(item);
      await _login(client, 'other-account');
      expect(photos.cachedPhoto(item), isNull);
      forbidden = true;
      expect(await photos.canEdit(item), isFalse);
      await expectLater(
        photos.save(item, fixtures.testPickedImage),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(photos.load(item), throwsA(isA<StorageException>()));
      await client.auth.signOut(scope: SignOutScope.local);
      expect(photos.cachedPhoto(item), isNull);
      await expectLater(photos.load(item), throwsStateError);
      expect(
        requests.any((r) => r.method == 'POST' && r.path.contains('/storage/')),
        isFalse,
      );
    });
    test('pending download cannot restore a removed photo', () async {
      final item = story();
      gate = Completer();
      final pending = photos.load(item);
      final error = expectLater(pending, throwsStateError);
      while (downloads() == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await photos.save(item, null);
      gate!.complete();
      await error;
      expect(photos.cachedPhoto(item), isNull);
    });
  });
}
