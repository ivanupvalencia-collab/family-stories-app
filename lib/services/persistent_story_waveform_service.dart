import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family_story.dart';
import 'story_waveform_service.dart';

const _format = 'audio_waveforms-2.0.2-rms256-peak-v1';
String _part(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');
String _key(FamilyStory story) =>
    jsonEncode([story.familyMemberId, story.id, story.audioPath]);

/// App-private, serialized disk operations prevent late writes after removal.
class StoryWaveformDiskCache {
  StoryWaveformDiskCache({Future<Directory> Function()? directoryProvider})
    : _directory = directoryProvider ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  Future<void> _operations = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _operations.then((_) => action());
    _operations = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<Directory> _root(String backend, String account) async => Directory(
    '${(await _directory()).path}/story_waveforms_v1/${_part(backend)}/${_part(account)}',
  );
  Future<Directory> _family(
    String backend,
    String account,
    String family,
  ) async =>
      Directory('${(await _root(backend, account)).path}/${_part(family)}');
  Future<File> _file(
    String backend,
    String account,
    FamilyStory story,
  ) async => File(
    '${(await _family(backend, account, story.familyMemberId)).path}/${_part(story.id)}.json',
  );

  Future<Map<String, dynamic>?> read(
    String backend,
    String account,
    FamilyStory story,
  ) => _serial(() async {
    final file = await _file(backend, account, story);
    try {
      if (await file.length() > 128 * 1024) {
        throw const FormatException('Oversized waveform cache');
      }
      return Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    }
  });

  Future<void> write(
    String backend,
    String account,
    FamilyStory story,
    Map<String, dynamic> data,
    bool Function() valid,
  ) => _serial(() async {
    if (!valid()) return;
    final file = await _file(backend, account, story);
    await file.parent.create(recursive: true);
    final staged = File('${file.path}.pending');
    try {
      final bytes = utf8.encode(jsonEncode(data));
      await staged.writeAsBytes(bytes, flush: true);
      if (!valid() || await staged.length() != bytes.length) return;
      if (await file.exists()) await file.delete();
      await staged.rename(file.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  });

  Future<void> removeFamily(String backend, String account, String family) =>
      _serial(() async {
        final directory = await _family(backend, account, family);
        if (await directory.exists()) await directory.delete(recursive: true);
      });
  Future<void> clear(String backend, String account) => _serial(() async {
    final directory = await _root(backend, account);
    if (await directory.exists()) await directory.delete(recursive: true);
  });
}

class _Job {
  _Job(this.story);
  final FamilyStory story;
  final done = Completer<List<double>>();
  StoryWaveformService? extractor;
}

/// One shared scope per backend/account. Closing a screen does not cancel work
/// shared by another screen or a background warm-up; scope invalidation does.
class PersistentStoryWaveformService extends StoryWaveformService {
  PersistentStoryWaveformService({
    required this.backend,
    required this.account,
    required this.remote,
    required this.disk,
    StoryWaveformService Function()? extractorFactory,
    bool Function()? stillCurrent,
  }) : _factory = extractorFactory ?? DeviceStoryWaveformService.new,
       _stillCurrent = stillCurrent ?? (() => true);
  final String backend, account;
  final bool remote;
  final StoryWaveformDiskCache disk;
  final StoryWaveformService Function() _factory;
  final bool Function() _stillCurrent;
  final _memory = <String, Map<String, dynamic>>{};
  final _jobs = <String, _Job>{};
  final _latest = <String, String>{};
  final _removedFamilies = <String>{};
  bool _invalid = false;
  final _invalidations = StreamController<String?>.broadcast();
  @override
  Stream<String?> get invalidations => _invalidations.stream;

  bool get _current => !_invalid && _stillCurrent();
  String _identity(FamilyStory story) =>
      jsonEncode([story.familyMemberId, story.id]);
  bool _valid(_Job job) =>
      _current &&
      !_removedFamilies.contains(job.story.familyMemberId) &&
      _latest[_identity(job.story)] == _key(job.story);

  Future<List<int>?> _stamp(FamilyStory story) async {
    if (remote) {
      return null; // Storage objects uploaded by the app are immutable.
    }
    final stat = await File(story.audioPath).stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw StateError('Local audio unavailable');
    }
    return [stat.size, stat.modified.microsecondsSinceEpoch];
  }

  List<double>? _samples(
    Map<String, dynamic>? entry,
    FamilyStory story,
    List<int>? stamp,
  ) {
    if (entry == null ||
        entry['format'] != _format ||
        entry['identity'] != _key(story) ||
        jsonEncode(entry['stamp']) != jsonEncode(stamp)) {
      return null;
    }
    final raw = entry['samples'];
    if (raw is! List ||
        raw.isEmpty ||
        raw.length > 4096 ||
        raw.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
      return null;
    }
    return List<double>.unmodifiable(raw.map((v) => (v as num).toDouble()));
  }

  @override
  List<double>? cachedForStory(FamilyStory story) =>
      remote && _current && !_removedFamilies.contains(story.familyMemberId)
      ? _samples(_memory[_key(story)], story, null)
      : null;

  @override
  Future<List<double>> loadForStory(
    FamilyStory story,
    Future<String> Function() localAudio,
  ) {
    if (!_current || _removedFamilies.contains(story.familyMemberId)) {
      return Future.error(StateError('Waveform scope unavailable'));
    }
    final key = _key(story);
    final previous = _latest[_identity(story)];
    if (previous != null && previous != key) {
      _memory.remove(previous);
      unawaited(_jobs[previous]?.extractor?.dispose());
    }
    _latest[_identity(story)] = key;
    final pending = _jobs[key];
    if (pending != null) return pending.done.future;
    final job = _Job(story);
    _jobs[key] =
        job; // Register before resolving audio: remote download also warms.
    unawaited(_load(job, localAudio));
    return job.done.future;
  }

  Future<void> _load(_Job job, Future<String> Function() localAudio) async {
    final story = job.story;
    final key = _key(story);
    try {
      final stamp = await _stamp(story);
      if (!_valid(job)) throw StateError('Waveform invalidated');
      final memory = _samples(_memory[key], story, stamp);
      Map<String, dynamic>? entry = _memory[key];
      if (memory == null) {
        try {
          entry = await disk.read(backend, account, story);
        } catch (_) {
          entry = null; // Cache I/O failure must not prevent native extraction.
        }
      }
      if (!_valid(job)) throw StateError('Waveform invalidated');
      var samples = _samples(entry, story, stamp);
      if (samples == null) {
        _memory.remove(key);
        final path = await localAudio();
        if (!_valid(job)) throw StateError('Waveform invalidated');
        job.extractor = _factory();
        final extracted = await job.extractor!.extract(path);
        entry = {
          'format': _format,
          'identity': key,
          'stamp': stamp,
          'samples': extracted,
        };
        samples = _samples(entry, story, stamp);
        if (samples == null ||
            jsonEncode(await _stamp(story)) != jsonEncode(stamp)) {
          throw StateError('Invalid or changed audio waveform');
        }
        if (!_valid(job)) throw StateError('Waveform invalidated');
        try {
          await disk.write(backend, account, story, entry, () => _valid(job));
        } catch (_) {
          // A full/unwritable disk must not discard valid in-memory samples.
        }
      }
      if (!_valid(job)) throw StateError('Waveform invalidated');
      _memory[key] = entry!;
      if (_memory.length > 64) _memory.remove(_memory.keys.first);
      if (identical(_jobs[key], job)) _jobs.remove(key);
      job.done.complete(samples);
    } catch (error, stack) {
      job.done.completeError(error, stack);
    } finally {
      try {
        await job.extractor?.dispose();
      } catch (_) {}
      if (identical(_jobs[key], job)) _jobs.remove(key);
    }
  }

  @override
  Future<List<double>> extract(String localAudioPath) async {
    final extractor = _factory();
    try {
      return await extractor.extract(localAudioPath);
    } finally {
      await extractor.dispose();
    }
  }

  @override
  Future<void> forgetFamily(String familyMemberId) async {
    _removedFamilies.add(familyMemberId);
    _invalidations.add(familyMemberId);
    _memory.removeWhere(
      (_, entry) =>
          (jsonDecode(entry['identity'] as String) as List).first ==
          familyMemberId,
    );
    for (final job in _jobs.values.toList()) {
      if (job.story.familyMemberId == familyMemberId) {
        unawaited(job.extractor?.dispose());
      }
    }
    try {
      await disk.removeFamily(backend, account, familyMemberId);
    } catch (_) {}
  }

  Future<void> invalidate() async {
    _invalid = true;
    _invalidations.add(null);
    _memory.clear();
    for (final job in _jobs.values.toList()) {
      unawaited(job.extractor?.dispose());
    }
    try {
      await disk.clear(backend, account);
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {} // Shared warm-ups survive navigation.
}

/// Session binding mirrors the account-scoped photo caches, including late work.
class _RemoteBinding {
  _RemoteBinding(this.client, this.disk, this.factory) {
    sync();
    client.auth.onAuthStateChange.listen((_) => sync());
  }
  final SupabaseClient client;
  final StoryWaveformDiskCache disk;
  final StoryWaveformService Function()? factory;
  String? account;
  PersistentStoryWaveformService? current;
  void sync() {
    final next = client.auth.currentUser?.id;
    if (account == next) return;
    final previous = current;
    account = next;
    current = null;
    if (previous != null) unawaited(previous.invalidate());
    if (next != null) {
      late PersistentStoryWaveformService scope;
      scope = PersistentStoryWaveformService(
        backend: client.storage.url,
        account: next,
        remote: true,
        disk: disk,
        extractorFactory: factory,
        stillCurrent: () =>
            identical(current, scope) && client.auth.currentUser?.id == next,
      );
      current = scope;
    }
  }
}

class StoryWaveforms {
  static final disk = StoryWaveformDiskCache();
  static final StoryWaveformService local = PersistentStoryWaveformService(
    backend: 'local',
    account: 'device',
    remote: false,
    disk: disk,
  );
  static final _remote = Expando<_RemoteBinding>();
  static StoryWaveformService forClient(
    SupabaseClient client, {
    StoryWaveformDiskCache? diskCache,
    StoryWaveformService Function()? extractorFactory,
  }) {
    final binding = _remote[client] ??= _RemoteBinding(
      client,
      diskCache ?? disk,
      extractorFactory,
    );
    binding.sync();
    return binding.current ?? _UnavailableWaveforms();
  }
}

class _UnavailableWaveforms extends StoryWaveformService {
  @override
  Future<List<double>> extract(String localAudioPath) =>
      Future.error(StateError('Authenticated waveform scope required'));
  @override
  Future<void> dispose() async {}
}
