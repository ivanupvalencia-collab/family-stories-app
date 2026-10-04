import 'dart:io';

import 'package:flutter/foundation.dart';
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
  final Map<String, String> _audioCache = {};

  void _debugLog(String phase, String message, [StackTrace? stackTrace]) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[FamilyStoriesRemoteAudio][$phase] $message');
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }

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
    _debugLog('request', 'audio_path=${story.audioPath}');
    final cachedPath = _audioCache[story.audioPath];
    if (cachedPath != null && await File(cachedPath).exists()) {
      final cachedSize = await File(cachedPath).length();
      _debugLog(
        'cache',
        'Reusing temporary file path=$cachedPath bytes=$cachedSize',
      );
      return cachedPath;
    }

    late final List<int> bytes;
    _debugLog(
      'storage_download',
      'Starting bucket=$audioBucketName path=${story.audioPath}',
    );
    try {
      bytes = await _client.storage
          .from(audioBucketName)
          .download(story.audioPath);
      _debugLog(
        'storage_download',
        'Success path=${story.audioPath} bytes=${bytes.length}',
      );
    } catch (error, stackTrace) {
      _debugLog(
        'storage_download',
        'Failure type=${error.runtimeType} message=$error',
        stackTrace,
      );
      rethrow;
    }

    try {
      final temporaryDirectory = await getTemporaryDirectory();
      final cacheDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}remote_story_audio',
      );
      await cacheDirectory.create(recursive: true);
      final file = File(
        '${cacheDirectory.path}${Platform.pathSeparator}${story.id}.m4a',
      );
      _debugLog('temporary_file', 'Writing path=${file.path}');
      await file.writeAsBytes(bytes, flush: true);
      final fileSize = await file.length();
      _debugLog(
        'temporary_file',
        'Ready path=${file.path} bytes=$fileSize',
      );
      _audioCache[story.audioPath] = file.path;
      return file.path;
    } catch (error, stackTrace) {
      _debugLog(
        'temporary_file',
        'Failure type=${error.runtimeType} message=$error',
        stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> clearAudioCache() async {
    final cachedPaths = _audioCache.values.toSet();
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
