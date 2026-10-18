import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/family_story.dart';
import 'family_member_storage.dart';
import 'story_waveform_service.dart';
import 'persistent_story_waveform_service.dart';

abstract interface class EditableFamilyStoryStorage {
  Future<FamilyStory> updatePhoto(FamilyStory story, String? path);
}

abstract class FamilyStoryStorage {
  Future<List<FamilyStory>> loadForFamily(String familyMemberId);

  Future<FamilyStory> saveRecording({
    required String familyMemberId,
    required String question,
    required String temporaryAudioPath,
    required Duration duration,
  });
}

class LocalFamilyStoryStorage
    implements FamilyStoryStorage, EditableFamilyStoryStorage {
  LocalFamilyStoryStorage({
    SharedPreferencesAsync? preferences,
    Future<Directory> Function()? documentsProvider,
    Future<Directory> Function()? supportProvider,
    StoryWaveformService? waveformService,
  }) : _preferencesOverride = preferences,
       documentsProvider =
           documentsProvider ?? getApplicationDocumentsDirectory,
       supportProvider = supportProvider ?? getApplicationSupportDirectory,
       waveforms = waveformService ?? StoryWaveforms.local;
  static const _storageKey = 'family_stories';

  final SharedPreferencesAsync? _preferencesOverride;
  SharedPreferencesAsync? _defaultPreferences;
  SharedPreferencesAsync get _preferences =>
      _preferencesOverride ??
      (_defaultPreferences ??= SharedPreferencesAsync());
  final Future<Directory> Function() documentsProvider, supportProvider;
  final StoryWaveformService waveforms;

  Future<void> _persist(List<FamilyStory> stories) =>
      _preferences.setStringList(
        _storageKey,
        stories.map((s) => jsonEncode(s.toJson())).toList(),
      );

  @override
  Future<FamilyStory> updatePhoto(FamilyStory story, String? path) async {
    final stories = await _loadAll();
    final index = stories.indexWhere((s) => s.id == story.id);
    if (index < 0) throw StateError('Story unavailable.');
    if (stories[index].photoPath != story.photoPath) {
      throw StateError('Photo changed; refresh.');
    }
    final updated = stories[index].withPhotoPath(path);
    stories[index] = updated;
    await _persist(stories);
    return updated;
  }

  Future<void> deleteFamily(String id, FamilyMemberStorage members) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid id');
    }
    final previousMembers = await members.load();
    final all = await _loadAll();
    final removed = all.where((s) => s.familyMemberId == id).toList();
    final documents = await documentsProvider();
    final support = await supportProvider();
    // Persist both references before removing any files. Compensate if the
    // second preferences write fails; never report partial deletion as success.
    await _persist(all.where((s) => s.familyMemberId != id).toList());
    try {
      await members.save(previousMembers.where((m) => m.id != id).toList());
    } catch (_) {
      await _persist(all);
      rethrow;
    }
    for (final story in removed) {
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(story.id)) continue;
      final audio = File('${documents.path}/stories/${story.id}.m4a');
      if (File(story.audioPath).absolute.uri == audio.absolute.uri) {
        try {
          if (await audio.exists()) await audio.delete();
        } catch (_) {}
      }
      final photoDirectory = Directory(
        '${support.path}/story_photos/${story.id}',
      );
      try {
        if (await photoDirectory.exists()) {
          await photoDirectory.delete(recursive: true);
        }
      } catch (_) {}
    }
    await waveforms.forgetFamily(id);
    final photoDirectory = Directory(
      '${support.path}/family_member_photos/$id',
    );
    try {
      if (await photoDirectory.exists()) {
        await photoDirectory.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<List<FamilyStory>> _loadAll() async {
    final storedStories = await _preferences.getStringList(_storageKey) ?? [];
    return storedStories
        .map(
          (story) =>
              FamilyStory.fromJson(jsonDecode(story) as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<List<FamilyStory>> loadForFamily(String familyMemberId) async {
    final stories = await _loadAll();
    return stories
        .where((story) => story.familyMemberId == familyMemberId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<FamilyStory> saveRecording({
    required String familyMemberId,
    required String question,
    required String temporaryAudioPath,
    required Duration duration,
  }) async {
    final id = FamilyStory.createId();
    final documentsDirectory = await documentsProvider();
    final storiesDirectory = Directory(
      '${documentsDirectory.path}${Platform.pathSeparator}stories',
    );
    await storiesDirectory.create(recursive: true);

    final persistentPath =
        '${storiesDirectory.path}${Platform.pathSeparator}$id.m4a';
    final persistentFile = await File(temporaryAudioPath).copy(persistentPath);
    final story = FamilyStory(
      id: id,
      familyMemberId: familyMemberId,
      question: question,
      audioPath: persistentFile.path,
      duration: duration,
      createdAt: DateTime.now(),
    );

    try {
      final stories = await _loadAll()
        ..add(story);
      await _preferences.setStringList(
        _storageKey,
        stories.map((item) => jsonEncode(item.toJson())).toList(),
      );
      final temporaryFile = File(temporaryAudioPath);
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      unawaited(waveforms.warm(story, () async => persistentFile.path));
      return story;
    } catch (_) {
      if (await persistentFile.exists()) {
        await persistentFile.delete();
      }
      rethrow;
    }
  }
}
