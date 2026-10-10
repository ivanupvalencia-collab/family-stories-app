import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family_story.dart';
import '../models/local_id.dart';
import 'family_story_storage.dart';
import 'private_photo_service.dart';
import 'profile_image_picker.dart';
import 'remote_family_photo_disk_cache.dart';

abstract class StoryPhotoService extends PrivatePhotoService<FamilyStory> {
  @override
  Uint8List? cachedPhoto(FamilyStory story) => null;
  Future<FamilyStory> refresh(FamilyStory story) async => story;
  Future<bool> canEdit(FamilyStory story);
  Future<void> forgetPhotos(String account, Iterable<String> paths) async {}
}

class LocalStoryPhotoService extends StoryPhotoService {
  LocalStoryPhotoService({
    FamilyStoryStorage? storage,
    Future<Directory> Function()? directoryProvider,
  }) : storage = storage ?? LocalFamilyStoryStorage(),
       _directory = directoryProvider ?? getApplicationSupportDirectory;
  final FamilyStoryStorage storage;
  final Future<Directory> Function() _directory;
  Future<File> _file(FamilyStory story, String path) async {
    final parts = path.split('/');
    if (parts.length != 3 ||
        parts[0] != 'story_photos' ||
        parts[1] != story.id ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(story.id) ||
        !RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$')
            .hasMatch(parts[2])) {
      throw const FormatException('Invalid story photo path');
    }
    return File('${(await _directory()).path}/${parts.join('/')}');
  }

  @override
  Future<bool> canEdit(FamilyStory story) async =>
      storage is EditableFamilyStoryStorage;
  @override
  Future<Uint8List> load(FamilyStory story) async =>
      (await _file(story, story.photoPath!)).readAsBytes();
  @override
  Future<FamilyStory> refresh(FamilyStory story) async =>
      (await storage.loadForFamily(story.familyMemberId))
          .firstWhere((s) => s.id == story.id);
  Future<void> _remove(FamilyStory story, String? path) async {
    if (path == null) return;
    try {
      final file = await _file(story, path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  @override
  Future<FamilyStory> save(FamilyStory story, PickedProfileImage? image) async {
    if (storage is! EditableFamilyStoryStorage) {
      throw StateError('Story editing unavailable');
    }
    final current = await refresh(story);
    String? path;
    if (image != null) {
      path =
          'story_photos/${story.id}/${generateLocalId()}.${privatePhotoExtension(image)}';
      final file = await _file(story, path);
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(image.bytes, flush: true);
        if (await file.length() != image.bytes.length) {
          throw StateError('Incomplete photo write');
        }
      } catch (_) {
        await _remove(story, path);
        rethrow;
      }
    }
    late FamilyStory updated;
    try {
      updated = await (storage as EditableFamilyStoryStorage).updatePhoto(
        current,
        path,
      );
    } catch (_) {
      await _remove(story, path);
      rethrow;
    }
    await _remove(story, current.photoPath);
    return updated;
  }
}

class _Entry {
  Uint8List? bytes;
  Future<Uint8List>? pending;
}

class _Cache extends ChangeNotifier {
  _Cache(this.client) : account = client.auth.currentUser?.id {
    client.auth.onAuthStateChange.listen((state) {
      final next = state.session?.user.id;
      if (next != account || state.event == AuthChangeEvent.signedOut) {
        reset(next);
      }
      // Also notify if an eager cachedPhoto call already synchronized account.
      notifyListeners();
    });
  }
  final SupabaseClient client;
  String? account;
  int generation = 0;
  final entries = <String, _Entry>{};
  void reset(String? next) {
    account = next;
    generation++;
    entries.clear();
  }

  void sync() {
    if (account != client.auth.currentUser?.id) {
      reset(client.auth.currentUser?.id);
    }
  }

  void changed() => notifyListeners();
}

class SupabaseStoryPhotoService extends StoryPhotoService {
  SupabaseStoryPhotoService({
    SupabaseClient? client,
    RemoteFamilyPhotoDiskCache? diskCache,
  }) : _override = client,
       _diskOverride = diskCache;
  static const bucket = 'story-photos';
  final SupabaseClient? _override;
  final RemoteFamilyPhotoDiskCache? _diskOverride;
  SupabaseClient get _client => _override ?? Supabase.instance.client;
  static final _caches = Expando<_Cache>();
  static final _disks = Expando<RemoteFamilyPhotoDiskCache>();
  _Cache get _cache {
    final cache = _caches[_client] ??= _Cache(_client);
    cache.sync();
    return cache;
  }

  RemoteFamilyPhotoDiskCache get _disk =>
      _diskOverride ??
      (_disks[_client] ??= RemoteFamilyPhotoDiskCache(
        directoryName: 'remote_story_photos_v1',
        allowForeignUploader: true,
      ));
  String get _backend => _client.storage.url;
  bool _belongs(FamilyStory story, String path) {
    final parts = path.split('/');
    return parts.length == 3 &&
        parts[1] == story.id &&
        RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(parts[0]) &&
        RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(parts[1]) &&
        RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$')
            .hasMatch(parts[2]);
  }

  String _account() =>
      _client.auth.currentUser?.id ??
      (throw StateError('Authentication required'));
  void _require(String account, int generation) {
    if (_account() != account || _cache.generation != generation) {
      throw StateError('Photo session changed');
    }
  }

  @override
  Listenable get cacheChanges => _cache;
  @override
  Future<void> forgetPhotos(String account, Iterable<String> paths) async {
    final cache = _cache;
    for (final path in paths) {
      if (_client.auth.currentUser?.id == account) cache.entries.remove(path);
      await _disk.remove(_backend, account, path);
    }
    cache.changed();
  }

  @override
  Uint8List? cachedPhoto(FamilyStory story) {
    if (_client.auth.currentUser == null ||
        story.photoPath == null ||
        !_belongs(story, story.photoPath!)) {
      return null;
    }
    return _cache.entries[story.photoPath]?.bytes;
  }

  Future<Map<String, dynamic>> _metadata(FamilyStory story) async {
    final account = _account();
    final generation = _cache.generation;
    final result = await _client.rpc(
      'get_story_photo_metadata',
      params: {'p_story_id': story.id},
    );
    _require(account, generation);
    if (result is! Map) throw StateError('Story unavailable');
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<FamilyStory> refresh(FamilyStory story) async =>
      FamilyStory.fromSupabaseJson(await _metadata(story));
  @override
  Future<bool> canEdit(FamilyStory story) async {
    try {
      return (await _metadata(story))['can_edit'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List> load(FamilyStory story) async {
    final account = _account();
    final cache = _cache;
    final generation = cache.generation;
    final path = story.photoPath;
    if (path == null || !_belongs(story, path)) {
      throw const FormatException('Invalid story photo path');
    }
    final old = cache.entries[path];
    if (old?.bytes != null) return old!.bytes!;
    if (old?.pending != null) return old!.pending!;
    final entry = _Entry();
    cache.entries[path] = entry;
    bool valid() =>
        _client.auth.currentUser?.id == account &&
        cache.generation == generation &&
        cache.entries[path] == entry;
    final future = () async {
      try {
        var bytes = await _disk.read(_backend, account, path);
        _require(account, generation);
        if (!valid()) throw StateError('Photo invalidated');
        if (bytes == null) {
          bytes = await _client.storage.from(bucket).download(path);
          await RemoteFamilyPhotoDiskCache.validate(bytes);
          _require(account, generation);
          await _disk.write(_backend, account, path, bytes, stillValid: valid);
        }
        _require(account, generation);
        if (!valid()) throw StateError('Photo invalidated');
        entry.bytes = bytes;
        entry.pending = null;
        cache.changed();
        return bytes;
      } catch (_) {
        if (cache.entries[path] == entry) cache.entries.remove(path);
        rethrow;
      }
    }();
    entry.pending = future;
    return future;
  }

  Future<void> _remove(String? path) async {
    if (path == null) return;
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {}
  }

  @override
  Future<FamilyStory> save(FamilyStory story, PickedProfileImage? image) async {
    final account = _account();
    final cache = _cache;
    final generation = cache.generation;
    final metadata = await _metadata(story);
    if (metadata['can_edit'] != true) {
      throw StateError('Story editing forbidden');
    }
    final current = FamilyStory.fromSupabaseJson(metadata);
    String? path;
    if (image != null) {
      path =
          '$account/${story.id}/${generateLocalId()}.${privatePhotoExtension(image)}';
      _require(account, generation);
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(
              contentType: image.contentType,
              upsert: false,
            ),
          );
    }
    late FamilyStory updated;
    try {
      _require(account, generation);
      final result = await _client.rpc(
        'set_story_photo',
        params: {
          'p_story_id': story.id,
          'p_photo_path': path,
          'p_expected_photo_path': current.photoPath,
        },
      );
      _require(account, generation);
      updated = FamilyStory.fromSupabaseJson(
        Map<String, dynamic>.from(result as Map),
      );
    } catch (error, stack) {
      // Confirm a lost response before deleting a potentially committed upload.
      FamilyStory? confirmed;
      try {
        _require(account, generation);
        confirmed = await refresh(story);
      } catch (_) {}
      if (confirmed != null && confirmed.photoPath == path) {
        updated = confirmed;
      } else {
        if (error is PostgrestException &&
            _client.auth.currentUser?.id == account) {
          await _remove(path);
        }
        Error.throwWithStackTrace(error, stack);
      }
    }
    _require(account, generation);
    cache.entries.remove(current.photoPath);
    if (path != null && image != null) {
      cache.entries[path] = _Entry()..bytes = image.bytes;
    }
    cache.changed();
    if (current.photoPath != null) {
      await _disk.remove(_backend, account, current.photoPath!);
    }
    if (path != null && image != null) {
      await _disk.write(
        _backend,
        account,
        path,
        image.bytes,
        stillValid: () =>
            _client.auth.currentUser?.id == account &&
            cache.generation == generation &&
            cache.entries[path]?.bytes == image.bytes,
      );
    }
    if (_client.auth.currentUser?.id == account) {
      await _remove(current.photoPath);
    }
    return updated;
  }
}
