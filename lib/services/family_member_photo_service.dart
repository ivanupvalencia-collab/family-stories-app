import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family_member.dart';
import '../models/local_id.dart';
import 'family_member_service.dart';
import 'family_member_storage.dart';
import 'profile_image_picker.dart';
import 'remote_family_photo_disk_cache.dart';
import 'private_photo_service.dart';

abstract class FamilyMemberPhotoService
    extends PrivatePhotoService<FamilyMember> {
  @override
  Uint8List? cachedPhoto(FamilyMember member) => null;
  @override
  Listenable? get cacheChanges => null;
  Future<void> warmCachedPhotos(List<FamilyMember> members) async {}
  Future<void> retainPhotos(List<FamilyMember> members) async {}
  Future<void> forgetPhotos(String account, Iterable<String> paths) async {}

  @override
  Future<Uint8List> load(FamilyMember member);

  // null removes the photo. Commit the reference before deleting the old file.
  @override
  Future<FamilyMember> save(FamilyMember member, PickedProfileImage? image);
}

String _extension(PickedProfileImage image) => privatePhotoExtension(image);

bool _safeSegment(String value) => RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value);

class LocalFamilyMemberPhotoService extends FamilyMemberPhotoService {
  LocalFamilyMemberPhotoService({
    required this.storage,
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final FamilyMemberStorage storage;
  final Future<Directory> Function() _directoryProvider;

  Future<File> _file(FamilyMember member, String path) async {
    final parts = path.split('/');
    if (parts.length != 3 ||
        parts[0] != 'family_member_photos' ||
        parts[1] != member.id ||
        !_safeSegment(member.id) ||
        !RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$')
            .hasMatch(parts[2])) {
      throw const FormatException('Invalid private photo path.');
    }
    final directory = await _directoryProvider();
    return File(
      '${directory.path}${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}',
    );
  }

  @override
  Future<Uint8List> load(FamilyMember member) async =>
      (await _file(member, member.photoPath!)).readAsBytes();

  Future<void> _remove(FamilyMember member, String? path) async {
    if (path == null) return;
    try {
      final file = await _file(member, path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Cleanup is best effort, scoped exclusively to this member's directory.
    }
  }

  @override
  Future<FamilyMember> save(
    FamilyMember member,
    PickedProfileImage? image,
  ) async {
    final members = await storage.load();
    final index = members.indexWhere((entry) => entry.id == member.id);
    if (index < 0) throw StateError('Family member no longer exists.');
    final current = members[index];
    String? newPath;
    if (image != null) {
      newPath =
          'family_member_photos/${member.id}/${generateLocalId()}.${_extension(image)}';
      final file = await _file(member, newPath);
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(image.bytes, flush: true);
        if (await file.length() != image.bytes.length) {
          throw StateError('Incomplete photo write.');
        }
      } catch (_) {
        await _remove(member, newPath);
        rethrow;
      }
    }
    final updated = current.withPhotoPath(newPath);
    members[index] = updated;
    try {
      await storage.save(members);
    } catch (_) {
      await _remove(member, newPath);
      rethrow;
    }
    await _remove(member, current.photoPath);
    return updated;
  }
}

// One cache per client (and therefore backend), shared by all screen services.
// Entries and pending downloads belong to a single authenticated session.
class _RemotePhotoCache extends ChangeNotifier {
  _RemotePhotoCache(this.client) : account = client.auth.currentUser?.id {
    client.auth.onAuthStateChange.listen((state) {
      final next = state.session?.user.id;
      if (next != account || state.event == AuthChangeEvent.signedOut) {
        reset(next);
      }
      notifyListeners();
    });
  }

  final SupabaseClient client;
  String? account;
  int generation = 0;
  final entries = <String, _PhotoEntry>{};

  void reset(String? next) {
    account = next;
    generation++;
    entries.clear();
  }

  void syncSession() {
    final next = client.auth.currentUser?.id;
    if (next != account) reset(next);
  }

  void changed() => notifyListeners();
}

class _PhotoEntry {
  Uint8List? bytes;
  Future<Uint8List>? pending;
}

class SupabaseFamilyMemberPhotoService extends FamilyMemberPhotoService {
  SupabaseFamilyMemberPhotoService({
    required this.ownerId,
    required this.memberService,
    SupabaseClient? client,
    RemoteFamilyPhotoDiskCache? diskCache,
  }) : _clientOverride = client,
       _diskOverride = diskCache;

  static const bucketName = 'family-member-photos';
  final String ownerId;
  final FamilyMemberService memberService;
  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;
  final RemoteFamilyPhotoDiskCache? _diskOverride;
  static final _disks = Expando<RemoteFamilyPhotoDiskCache>();
  RemoteFamilyPhotoDiskCache get _disk =>
      _diskOverride ?? (_disks[_client] ??= RemoteFamilyPhotoDiskCache());
  String get _backend => _client.storage.url;
  static final _caches = Expando<_RemotePhotoCache>();
  _RemotePhotoCache get _cache {
    final client = _client;
    final cache = _caches[client] ??= _RemotePhotoCache(client);
    cache.syncSession();
    return cache;
  }

  @override
  Listenable get cacheChanges => _cache;

  @override
  Future<void> forgetPhotos(String account, Iterable<String> paths) async {
    final cache = _cache;
    for (final path in paths) {
      if (cache.account == account) cache.entries.remove(path);
      await _disk.remove(_backend, account, path);
    }
    cache.changed();
  }

  @override
  Uint8List? cachedPhoto(FamilyMember member) {
    final path = member.photoPath;
    if (path == null || !_belongsTo(member, path)) return null;
    final cache = _cache;
    if (cache.account != ownerId) return null;
    return cache.entries[path]?.bytes;
  }

  void _requireOwnerSession() {
    if (_client.auth.currentUser?.id != ownerId) {
      throw StateError('The owner session is required.');
    }
  }

  bool _belongsTo(FamilyMember member, String path) {
    final parts = path.split('/');
    return parts.length == 3 &&
        parts[0] == ownerId &&
        parts[1] == member.id &&
        _safeSegment(ownerId) &&
        _safeSegment(member.id) &&
        RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$')
            .hasMatch(parts[2]);
  }

  @override
  Future<Uint8List> load(FamilyMember member) async {
    return _load(member, cacheOnly: false);
  }

  @override
  Future<void> warmCachedPhotos(List<FamilyMember> members) async {
    await Future.wait(
      members.where((m) => m.photoPath != null).map((member) async {
        try {
          await _load(member, cacheOnly: true);
        } catch (_) {
          // A missing disk entry is fetched normally when its view is displayed.
        }
      }),
    );
  }

  @override
  Future<void> retainPhotos(List<FamilyMember> members) async {
    _requireOwnerSession();
    final paths = members
        .where((m) => m.photoPath != null && _belongsTo(m, m.photoPath!))
        .map((m) => m.photoPath!)
        .toSet();
    final cache = _cache;
    final obsolete = cache.entries.keys
        .where((path) => !paths.contains(path))
        .toList();
    for (final path in obsolete) {
      cache.entries.remove(path);
    }
    if (obsolete.isNotEmpty) cache.changed();
    await _disk.retain(_backend, ownerId, paths);
  }

  Future<Uint8List> _load(
    FamilyMember member, {
    required bool cacheOnly,
  }) async {
    _requireOwnerSession();
    final path = member.photoPath;
    if (path == null || !_belongsTo(member, path)) {
      throw const FormatException('Invalid private photo path.');
    }
    final cache = _cache;
    final existing = cache.entries[path];
    if (existing?.bytes != null) return existing!.bytes!;
    if (existing?.pending != null) return existing!.pending!;
    final entry = _PhotoEntry();
    final generation = cache.generation;
    cache.entries[path] = entry;
    bool valid() =>
        _client.auth.currentUser?.id == ownerId &&
        cache.generation == generation &&
        cache.entries[path] == entry;
    final pending = () async {
      try {
        var bytes = await _disk.read(_backend, ownerId, path);
        _requireOwnerSession();
        if (!valid()) throw StateError('Photo load was invalidated.');
        if (bytes == null) {
          if (cacheOnly) throw StateError('Photo is not on disk.');
          bytes = await _client.storage.from(bucketName).download(path);
          if (bytes.isEmpty) throw StateError('Empty photo download.');
          await RemoteFamilyPhotoDiskCache.validate(bytes);
          await _disk.write(_backend, ownerId, path, bytes, stillValid: valid);
        }
        _requireOwnerSession();
        cache.syncSession();
        if (cache.generation != generation || cache.entries[path] != entry) {
          throw StateError('Photo download was invalidated.');
        }
        if (bytes.isEmpty) throw StateError('Empty photo download.');
        entry.bytes = bytes;
        entry.pending = null;
        cache.changed();
        return bytes;
      } catch (_) {
        if (cache.entries[path] == entry) cache.entries.remove(path);
        rethrow;
      }
    }();
    entry.pending = pending;
    return pending;
  }

  Future<void> _remove(FamilyMember member, String? path) async {
    if (path == null || !_belongsTo(member, path)) return;
    try {
      _requireOwnerSession();
      await _client.storage.from(bucketName).remove([path]);
    } catch (_) {
      // A committed photo change must remain successful if cleanup fails.
    }
  }

  @override
  Future<FamilyMember> save(
    FamilyMember member,
    PickedProfileImage? image,
  ) async {
    _requireOwnerSession();
    final cache = _cache;
    final generation = cache.generation;
    final current = await memberService.loadMemberForOwner(
      ownerId: ownerId,
      familyMemberId: member.id,
    );
    if (current == null) throw StateError('Family member no longer exists.');
    _requireOwnerSession();
    String? newPath;
    if (image != null) {
      if (!_safeSegment(member.id) || !_safeSegment(ownerId)) {
        throw const FormatException('Invalid member id.');
      }
      newPath =
          '$ownerId/${member.id}/${generateLocalId()}.${_extension(image)}';
      try {
        await _client.storage
            .from(bucketName)
            .uploadBinary(
              newPath,
              image.bytes,
              fileOptions: FileOptions(
                contentType: image.contentType,
                upsert: false,
              ),
            );
      } catch (_) {
        await _remove(member, newPath);
        rethrow;
      }
    }
    late final FamilyMember updated;
    try {
      _requireOwnerSession();
      updated = await memberService.updatePhoto(
        ownerId: ownerId,
        familyMemberId: member.id,
        photoPath: newPath,
        expectedPhotoPath: current.photoPath,
      );
    } catch (error, stackTrace) {
      // A lost HTTP response may follow a successful commit. Never delete a
      // potentially referenced object until the database state is confirmed.
      FamilyMember? confirmed;
      try {
        _requireOwnerSession();
        confirmed = await memberService.loadMemberForOwner(
          ownerId: ownerId,
          familyMemberId: member.id,
        );
      } catch (_) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (confirmed != null && confirmed.photoPath == newPath) {
        updated = confirmed;
      } else {
        // An explicit API database error confirms an aborted write. For a
        // transport/parse failure the server may still be committing: retain
        // the staged object rather than risking deletion of an active photo.
        if (error is PostgrestException) await _remove(member, newPath);
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    _requireOwnerSession();
    cache.syncSession();
    if (cache.generation != generation) {
      throw StateError('Photo save session changed.');
    }
    cache.entries.remove(current.photoPath);
    if (newPath != null && image != null) {
      cache.entries[newPath] = _PhotoEntry()..bytes = image.bytes;
    }
    cache.changed();
    if (current.photoPath != null) {
      await _disk.remove(_backend, ownerId, current.photoPath!);
    }
    if (newPath != null && image != null) {
      await _disk.write(
        _backend,
        ownerId,
        newPath,
        image.bytes,
        stillValid: () =>
            cache.account == ownerId &&
            cache.generation == generation &&
            cache.entries[newPath]?.bytes == image.bytes,
      );
    }
    await _remove(member, current.photoPath);
    return updated;
  }
}
