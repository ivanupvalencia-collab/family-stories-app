import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

abstract class AudioAnswerService {
  Stream<void> get onPlaybackComplete;
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;

  Future<bool> requestPermission();
  Future<void> startRecording();
  Future<String?> stopRecording();
  Future<void> play(String path);
  Future<void> pause();
  Future<void> resume();

  /// Seek proportionally to the real local audio duration, without autoplay.
  Future<void> seek(String path, double fraction);
  Future<void> discard(String path);
  Future<void> dispose();
}

class DeviceAudioAnswerService implements AudioAnswerService {
  DeviceAudioAnswerService({AudioRecorder? recorder, AudioPlayer? player})
    : _recorder = recorder ?? AudioRecorder(),
      _player = player ?? AudioPlayer();

  final AudioRecorder _recorder;
  final AudioPlayer _player;

  String? _recordingPath;
  bool _isRecording = false;

  @override
  Stream<void> get onPlaybackComplete => _player.onPlayerComplete;

  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;

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
  Future<void> play(String path) => _player.play(DeviceFileSource(path));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> seek(String path, double fraction) async {
    if (!fraction.isFinite) throw ArgumentError.value(fraction, 'fraction');
    final source = _player.source;
    if (source is! DeviceFileSource || source.path != path) {
      await _player.setSource(DeviceFileSource(path));
    }
    final duration = await _player.getDuration();
    if (duration == null || duration <= Duration.zero) {
      throw StateError('Audio duration unavailable');
    }
    await _player.seek(
      Duration(
        microseconds: (duration.inMicroseconds * fraction.clamp(0.0, 1.0))
            .round(),
      ),
    );
  }

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
