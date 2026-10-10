import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

// App-private cache, never the guest's original photos. Object paths are
// validated by the photo service before reaching this class.
class RemoteFamilyPhotoDiskCache {
  RemoteFamilyPhotoDiskCache({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;
  Future<void> _writes = Future.value();

  Future<Directory> _root(String backend, String owner) async {
    final support = await _directoryProvider();
    final namespace = base64Url.encode(utf8.encode(backend));
    return Directory(
      [
        support.path,
        'remote_family_photos_v1',
        namespace,
        owner,
      ].join(Platform.pathSeparator),
    );
  }

  Future<File> _file(String backend, String owner, String path) async {
    final parts = path.split('/');
    if (parts.length != 3 ||
        parts.first != owner ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(owner) ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(parts[1]) ||
        !RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$')
            .hasMatch(parts[2])) {
      throw const FormatException('Invalid cache path.');
    }
    final root = await _root(backend, owner);
    return File([root.path, parts[1], parts[2]].join(Platform.pathSeparator));
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
    if (!stillValid()) return;
    final file = await _file(backend, owner, path);
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
