import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

abstract class AudioAnswerService {
  Stream<void> get onPlaybackComplete;

  Future<bool> requestPermission();
  Future<void> startRecording();
  Future<String?> stopRecording();
  Future<void> play(String path);
  Future<void> pause();
  Future<void> resume();
  Future<void> discard(String path);
  Future<void> dispose();
}

class DeviceAudioAnswerService implements AudioAnswerService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  String? _recordingPath;
  bool _isRecording = false;

  @override
  Stream<void> get onPlaybackComplete => _player.onPlayerComplete;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<void> startRecording() async {
    final temporaryDirectory = await getTemporaryDirectory();
    final path =
        '${temporaryDirectory.path}${Platform.pathSeparator}'
        'family_story_${DateTime.now().microsecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        numChannels: 1,
        autoGain: true,
        noiseSuppress: true,
      ),
      path: path,
    );

    _recordingPath = path;
    _isRecording = true;
  }

  @override
  Future<String?> stopRecording() async {
    final path = await _recorder.stop();
    _isRecording = false;
    _recordingPath = path;
    return path;
  }

  @override
  Future<void> play(String path) async {
    if (kDebugMode) {
      debugPrint(
        '[FamilyStoriesRemoteAudio][audioplayers] play path=$path',
      );
    }
    try {
      await _player.play(DeviceFileSource(path));
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[FamilyStoriesRemoteAudio][audioplayers] '
          'Failure type=${error.runtimeType} message=$error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> discard(String path) async {
    await _player.stop();
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    if (_recordingPath == path) {
      _recordingPath = null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_isRecording) {
      await _recorder.cancel();
      _isRecording = false;
    }

    await _player.stop();
    await _player.dispose();
    await _recorder.dispose();

    final path = _recordingPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
