import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

// App-private cache, never the guest's original photos. Object paths are
// validated by the photo service before reaching this class.
class RemoteFamilyPhotoDiskCache {
  RemoteFamilyPhotoDiskCache({
    Future<Directory> Function()? directoryProvider,
    this.directoryName = 'remote_family_photos_v1',
    this.allowForeignUploader = false,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  // One instance per client and configuration: every reader shares the same
  // ordering (per file + per-owner barrier, see _run), so a logout purge
  // (S-6) can never race a download that is still committing its file.
  static final _shared = Expando<Map<String, RemoteFamilyPhotoDiskCache>>();

  static RemoteFamilyPhotoDiskCache forClient(
    Object client, {
    String directoryName = 'remote_family_photos_v1',
    bool allowForeignUploader = false,
  }) {
    final byConfiguration =
        _shared[client] ??= <String, RemoteFamilyPhotoDiskCache>{};
    final key = '$directoryName:$allowForeignUploader';
    return byConfiguration[key] ??= RemoteFamilyPhotoDiskCache(
      directoryName: directoryName,
      allowForeignUploader: allowForeignUploader,
    );
  }

  final Future<Directory> Function() _directoryProvider;
  final String directoryName;
  final bool allowForeignUploader;

  // C-9: operations are ordered per logical file, plus one barrier per owner
  // for tree-wide ops (clearOwner/retain). A read only waits for the write of
  // its own file and for a purge/cleanup of its owner — never for the rest of
  // the backlog. Dependencies always point from older to newer registrations
  // (an op only chains onto barriers that already existed when it was
  // enqueued), so no cycle is possible.
  final _pendingFiles = <String, Future<void>>{};
  final _ownerQueues = <String, Future<void>>{};
  final _inFlightFiles = <String, Set<Future<void>>>{};

  String _fileKey(String backend, String owner, String path) =>
      'file:$backend|$owner|$path';
  String _entryKey(String backend, String owner, String key) =>
      'entry:$backend|$owner|$key';
  String _ownerKey(String backend, String owner) => 'owner:$backend|$owner';

  // Wait only for operations that can touch this file: its own pending write
  // or removal, and a tree-wide purge/cleanup of the same owner.
  Future<void> _settle(String ownerKey, String fileKey) {
    final waiting = <Future<void>>[];
    final pending = _pendingFiles[fileKey];
    if (pending != null) waiting.add(pending);
    final barrier = _ownerQueues[ownerKey];
    if (barrier != null) waiting.add(barrier);
    return waiting.isEmpty ? Future.value() : Future.wait(waiting);
  }

  Future<void> _run(
    String ownerKey,
    String? fileKey, // null → tree-wide op over the owner's directory
    Future<void> Function() action,
  ) {
    final deps = <Future<void>>[];
    if (fileKey == null) {
      final previous = _ownerQueues[ownerKey];
      if (previous != null) deps.add(previous);
      deps.addAll(_inFlightFiles[ownerKey] ?? const <Future<void>>[]);
    } else {
      final sameFile = _pendingFiles[fileKey];
      if (sameFile != null) deps.add(sameFile);
      final barrier = _ownerQueues[ownerKey];
      if (barrier != null) deps.add(barrier);
    }
    final next = Future.wait(deps)
        .then((_) => action())
        // Same contract as the old global queue: failures stay internal and
        // never block the operations queued behind them.
        .catchError((Object _) {});
    if (fileKey == null) {
      _ownerQueues[ownerKey] = next;
    } else {
      _pendingFiles[fileKey] = next;
      (_inFlightFiles[ownerKey] ??= <Future<void>>{}).add(next);
    }
    unawaited(
      next.whenComplete(() {
        if (fileKey == null) {
          if (identical(_ownerQueues[ownerKey], next)) {
            _ownerQueues.remove(ownerKey);
          }
          return;
        }
        if (identical(_pendingFiles[fileKey], next)) {
          _pendingFiles.remove(fileKey);
        }
        final inFlight = _inFlightFiles[ownerKey];
        inFlight?.remove(next);
        if (inFlight != null && inFlight.isEmpty) {
          _inFlightFiles.remove(ownerKey);
        }
      }),
    );
    return next;
  }

  Future<Directory> _root(String backend, String owner) async {
    final support = await _directoryProvider();
    final namespace = base64Url.encode(utf8.encode(backend));
    return Directory(
      [
        support.path,
        directoryName,
        namespace,
        owner,
      ].join(Platform.pathSeparator),
    );
  }

  Future<File> _file(String backend, String owner, String path) async {
    final parts = path.split('/');
    if (parts.length != 3 ||
        (!allowForeignUploader && parts.first != owner) ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(parts.first) ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(owner) ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(parts[1]) ||
        !RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$')
            .hasMatch(parts[2])) {
      throw const FormatException('Invalid cache path.');
    }
    final root = await _root(backend, owner);
    return File(
      [
        root.path,
        if (allowForeignUploader) parts.first,
        parts[1],
        parts[2],
      ].join(Platform.pathSeparator),
    );
  }

  static Future<void> validate(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('Invalid photo bytes.');
    }
    // Decode a tiny frame to detect broken files without retaining a full
    // resolution bitmap. The UI separately decodes to its display size.
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 1,
      targetHeight: 1,
    );
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  }

  Future<Uint8List?> read(String backend, String owner, String path) async {
    await _settle(_ownerKey(backend, owner), _fileKey(backend, owner, path));
    try {
      final file = await _file(backend, owner, path);
      final bytes = await file.readAsBytes();
      await validate(bytes);
      return bytes;
    } catch (_) {
      await remove(backend, owner, path);
      return null;
    }
  }

  Future<void> write(
    String backend,
    String owner,
    String path,
    Uint8List bytes, {
    required bool Function() stillValid,
  }) => _run(_ownerKey(backend, owner), _fileKey(backend, owner, path), () async {
    await _writeFile(await _file(backend, owner, path), bytes, stillValid);
  });

  Future<void> _writeFile(
    File file,
    Uint8List bytes,
    bool Function() stillValid,
  ) async {
    if (!stillValid()) return;
    await file.parent.create(recursive: true);
    final staged = File('${file.path}.pending');
    try {
      await staged.writeAsBytes(bytes, flush: true);
      if (await staged.length() != bytes.length || !stillValid()) return;
      if (await file.exists()) await file.delete();
      await staged.rename(file.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  // Opaque image references (avatar URLs/revisions and their metadata) reuse
  // the same private, atomic store without pretending to be Storage paths.
  Future<File> _named(String backend, String owner, String key) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(owner) || key.isEmpty) {
      throw const FormatException('Invalid cache identity.');
    }
    final encoded = base64Url.encode(utf8.encode(key));
    final chunks = <String>[
      for (var offset = 0; offset < encoded.length; offset += 80)
        encoded.substring(offset, (offset + 80).clamp(0, encoded.length)),
    ];
    return File(
      '${(await _root(backend, owner)).path}/entries/${chunks.join('/')}.cache',
    );
  }

  Future<Uint8List?> readEntry(
    String backend,
    String owner,
    String key, {
    bool image = true,
  }) async {
    await _settle(_ownerKey(backend, owner), _entryKey(backend, owner, key));
    try {
      final bytes = await (await _named(backend, owner, key)).readAsBytes();
      if (image) {
        await validate(bytes);
      } else if (bytes.isEmpty || bytes.length > 64 * 1024) {
        throw const FormatException('Invalid metadata size.');
      }
      return bytes;
    } catch (_) {
      await removeEntry(backend, owner, key);
      return null;
    }
  }

  Future<void> writeEntry(
    String backend,
    String owner,
    String key,
    Uint8List bytes, {
    required bool Function() stillValid,
  }) => _run(_ownerKey(backend, owner), _entryKey(backend, owner, key), () async {
    await _writeFile(await _named(backend, owner, key), bytes, stillValid);
  });

  Future<void> removeEntry(String backend, String owner, String key) =>
      _run(_ownerKey(backend, owner), _entryKey(backend, owner, key), () async {
        final file = await _named(backend, owner, key);
        if (await file.exists()) await file.delete();
      });

  Future<void> clearOwner(String backend, String owner) => _run(
    _ownerKey(backend, owner),
    null,
    () async {
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(owner)) return;
      final root = await _root(backend, owner);
      if (await root.exists()) await root.delete(recursive: true);
    },
  );

  Future<void> remove(String backend, String owner, String path) =>
      _run(_ownerKey(backend, owner), _fileKey(backend, owner, path), () async {
        final file = await _file(backend, owner, path);
        if (await file.exists()) await file.delete();
      });

  Future<void> retain(String backend, String owner, Set<String> paths) =>
      _run(_ownerKey(backend, owner), null, () async {
        final root = await _root(backend, owner);
        if (!await root.exists()) return;
        final keep = <String>{};
        for (final path in paths) {
          keep.add((await _file(backend, owner, path)).path);
        }
        await for (final file in root.list(
          recursive: true,
          followLinks: false,
        )) {
          if (file is File && !keep.contains(file.path)) await file.delete();
        }
      });
}
