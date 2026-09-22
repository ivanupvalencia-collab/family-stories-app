import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/family_story.dart';

abstract class FamilyStoryStorage {
  Future<List<FamilyStory>> loadForFamily(String familyMemberId);

  Future<FamilyStory> saveRecording({
    required String familyMemberId,
    required String question,
    required String temporaryAudioPath,
    required Duration duration,
  });
}

class LocalFamilyStoryStorage implements FamilyStoryStorage {
  static const _storageKey = 'family_stories';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

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
    final documentsDirectory = await getApplicationDocumentsDirectory();
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
      return story;
    } catch (_) {
      if (await persistentFile.exists()) {
        await persistentFile.delete();
      }
      rethrow;
    }
  }
}
