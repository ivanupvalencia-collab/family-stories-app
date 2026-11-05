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

  final Future<Directory> Function() _directoryProvider;
  final String directoryName;
  final bool allowForeignUploader;
  Future<void> _writes = Future.value();

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
    await _writes;
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

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.catchError((Object _) {});
    return _writes;
  }

  Future<void> write(
    String backend,
    String owner,
    String path,
    Uint8List bytes, {
    required bool Function() stillValid,
  }) => _enqueue(() async {
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
    await _writes;
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
  }) => _enqueue(() async {
    await _writeFile(await _named(backend, owner, key), bytes, stillValid);
  });

  Future<void> removeEntry(String backend, String owner, String key) =>
      _enqueue(() async {
        final file = await _named(backend, owner, key);
        if (await file.exists()) await file.delete();
      });

  Future<void> clearOwner(String backend, String owner) => _enqueue(() async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(owner)) return;
    final root = await _root(backend, owner);
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> remove(String backend, String owner, String path) =>
      _enqueue(() async {
        final file = await _file(backend, owner, path);
        if (await file.exists()) await file.delete();
      });

  Future<void> retain(String backend, String owner, Set<String> paths) =>
      _enqueue(() async {
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
