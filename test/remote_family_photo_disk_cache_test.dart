import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_stories_app/services/remote_family_photo_disk_cache.dart';
import 'package:flutter_test/flutter_test.dart';

// C-9: the disk cache must order operations per file, not globally. A read
// (or a write to another path) may only wait for operations that can touch
// its own file, never for the rest of the write backlog.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late RemoteFamilyPhotoDiskCache cache;

  // Gated directoryProvider: while the gate is armed, the first call blocks
  // (it belongs to the write we want to hold open); later calls pass through
  // so reads and other writes keep running.
  var blockFirstProviderCall = false;
  var providerGate = Completer<void>();

  Future<Directory> provider() async {
    if (blockFirstProviderCall) {
      blockFirstProviderCall = false;
      await providerGate.future;
    }
    return support;
  }

  // A valid 1x1 PNG so `validate` accepts the bytes on read.
  final png = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    ),
  );

  bool stillValid() => true;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('photo_disk_cache_');
    cache = RemoteFamilyPhotoDiskCache(directoryProvider: provider);
    blockFirstProviderCall = false;
    providerGate = Completer<void>();
  });

  tearDown(() async {
    // Release any write still held by the gate and drain the queue.
    blockFirstProviderCall = false;
    if (!providerGate.isCompleted) providerGate.complete();
    await cache.clearOwner('backend', 'owner');
    await cache.clearOwner('backend', 'other');
    await support.delete(recursive: true);
  });

  test('a read does not wait for another file\'s write backlog (C-9)',
      () async {
    // Seed file B before arming the gate.
    await cache.write('backend', 'owner', 'owner/m/b.png', png,
        stillValid: stillValid);

    // Enqueue write A and hold it open inside its directory lookup.
    blockFirstProviderCall = true;
    final writeA = cache.write('backend', 'owner', 'owner/m/a.png', png,
        stillValid: stillValid);
    // Let write A reach the gate.
    await Future<void>.delayed(Duration.zero);

    // Reading B must complete while A is still blocked: under the old
    // global queue this awaited every pending write and hung.
    final bytes = await cache
        .read('backend', 'owner', 'owner/m/b.png')
        .timeout(const Duration(seconds: 2));
    expect(bytes, png,
        reason: 'C-9: a read waited for another file\'s write backlog.');
    expect(providerGate.isCompleted, isFalse,
        reason: 'C-9: write A should still be held by the gate.');

    providerGate.complete();
    await writeA;
  });

  test('writes to different paths do not serialize (C-9)', () async {
    // Enqueue write A and hold it open inside its directory lookup.
    blockFirstProviderCall = true;
    final writeA = cache.write('backend', 'owner', 'owner/m/a.png', png,
        stillValid: stillValid);
    await Future<void>.delayed(Duration.zero);

    // Write B targets another file: it must finish while A is still blocked.
    await cache
        .write('backend', 'owner', 'owner/m/b.png', png,
            stillValid: stillValid)
        .timeout(const Duration(seconds: 2));
    expect(providerGate.isCompleted, isFalse,
        reason: 'C-9: write B was serialized behind write A.');
    expect(
      File('${support.path}/remote_family_photos_v1/'
              '${base64Url.encode(utf8.encode('backend'))}/owner/m/b.png')
          .existsSync(),
      isTrue,
      reason: 'C-9: write B never reached the disk.',
    );

    providerGate.complete();
    await writeA;
    expect(
      File('${support.path}/remote_family_photos_v1/'
              '${base64Url.encode(utf8.encode('backend'))}/owner/m/a.png')
          .existsSync(),
      isTrue,
    );
  });

  test(
    'the disk cache evicts the oldest files when a tree exceeds its byte budget (C-11)',
    () async {
      final budgeted = RemoteFamilyPhotoDiskCache(
        directoryProvider: provider,
        maxBytes: 2500,
      );
      final namespace = base64Url.encode(utf8.encode('backend'));
      String filePath(String owner, String name) =>
          '${support.path}/remote_family_photos_v1/$namespace/$owner/m/$name';

      await budgeted.write(
        'backend',
        'owner',
        'owner/m/a.png',
        Uint8List(1000),
        stillValid: stillValid,
      );
      await File(filePath('owner', 'a.png')).setLastModified(
        DateTime.now().subtract(const Duration(minutes: 1)),
      );
      await budgeted.write(
        'backend',
        'owner',
        'owner/m/b.png',
        Uint8List(1000),
        stillValid: stillValid,
      );
      await File(filePath('owner', 'b.png')).setLastModified(
        DateTime.now().subtract(const Duration(minutes: 1)),
      );
      // An old file of another owner is outside this owner's budget.
      final foreign = File(filePath('other', 'old.png'));
      await foreign.parent.create(recursive: true);
      await foreign.writeAsBytes(Uint8List(1000));
      await foreign.setLastModified(
        DateTime.now().subtract(const Duration(minutes: 2)),
      );

      await budgeted.write(
        'backend',
        'owner',
        'owner/m/c.png',
        Uint8List(1000),
        stillValid: stillValid,
      );

      expect(
        File(filePath('owner', 'a.png')).existsSync(),
        isFalse,
        reason: 'C-11: the oldest file was not evicted over the budget.',
      );
      expect(File(filePath('owner', 'b.png')).existsSync(), isTrue);
      expect(File(filePath('owner', 'c.png')).existsSync(), isTrue);
      expect(
        foreign.existsSync(),
        isTrue,
        reason: 'C-11: eviction must be scoped to the owner tree.',
      );
      await budgeted.clearOwner('backend', 'owner');
      await budgeted.clearOwner('backend', 'other');
    },
  );
}
