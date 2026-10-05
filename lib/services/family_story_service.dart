import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family_story.dart';

abstract class FamilyStoryService {
  Future<List<FamilyStory>> loadForFamily(String familyMemberId);

  Future<String> localAudioPathFor(FamilyStory story);

  Future<void> clearAudioCache();
}

class SupabaseFamilyStoryService implements FamilyStoryService {
  SupabaseFamilyStoryService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const audioBucketName = 'story-audio';

  final SupabaseClient _client;
  final Map<String, ({String path, int size})> _audioCache = {};

  @override
  Future<List<FamilyStory>> loadForFamily(String familyMemberId) async {
    final data = await _client
        .from('stories')
        .select(
          'id, family_member_id, question, audio_path, duration_seconds, created_at, question_request_id, recorded_by',
        )
        .eq('family_member_id', familyMemberId)
        .order('created_at', ascending: false);

    return data.map(FamilyStory.fromSupabaseJson).toList();
  }

  @override
  Future<String> localAudioPathFor(FamilyStory story) async {
    final cached = _audioCache[story.audioPath];
    if (cached != null) {
      try {
        final file = File(cached.path);
        final size = await file.exists() ? await file.length() : 0;
        if (size > 0 && size == cached.size) {
          return cached.path;
        }
      } on FileSystemException {
        // An unreadable cache entry must be downloaded again.
      }
      _audioCache.remove(story.audioPath);
    }

    final bytes = await _client.storage
        .from(audioBucketName)
        .download(story.audioPath);
    if (bytes.isEmpty) {
      throw StateError('Storage returned an empty audio file.');
    }

    final temporaryDirectory = await getTemporaryDirectory();
    final cacheDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}remote_story_audio',
    );
    await cacheDirectory.create(recursive: true);
    final file = File(
      '${cacheDirectory.path}${Platform.pathSeparator}${story.id}.m4a',
    );
    await file.writeAsBytes(bytes, flush: true);
    final fileSize = await file.length();
    if (fileSize != bytes.length) {
      throw StateError('Temporary audio size differs from downloaded bytes.');
    }
    _audioCache[story.audioPath] = (path: file.path, size: fileSize);
    return file.path;
  }

  @override
  Future<void> clearAudioCache() async {
    final cachedPaths = _audioCache.values.map((entry) => entry.path).toSet();
    _audioCache.clear();
    for (final path in cachedPaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Cache cleanup is best effort and must not affect authentication.
      }
    }
  }
}
