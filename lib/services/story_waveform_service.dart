import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_waveforms/audio_waveforms.dart';

import '../models/family_story.dart';

/// Only this adapter knows audio_waveforms. Playback stays in AudioAnswerService.
abstract class StoryWaveformService {
  Stream<String?> get invalidations => const Stream.empty();
  Future<List<double>> extract(String localAudioPath);
  List<double>? cachedForStory(FamilyStory story) => null;
  Future<List<double>> loadForStory(
    FamilyStory story,
    Future<String> Function() localAudio,
  ) async => extract(await localAudio());
  Future<void> warm(
    FamilyStory story,
    Future<String> Function() localAudio,
  ) async {
    try {
      await loadForStory(story, localAudio);
    } catch (_) {
      // Optional background work must never affect saving or downloading audio.
    }
  }

  Future<void> forgetFamily(String familyMemberId) async {}
  Future<void> dispose();
}

abstract interface class StoryWaveformProvider {
  StoryWaveformService get waveforms;
}

class DeviceStoryWaveformService extends StoryWaveformService {
  final _extractor = WaveformExtractionController();
  final _cancelled = Completer<void>();
  bool _disposed = false;
  bool _extracting = false;

  @override
  Future<List<double>> extract(String localAudioPath) async {
    if (_disposed || _extracting) throw StateError('Extractor unavailable');
    _extracting = true;
    try {
      final file = File(localAudioPath);
      if (!await file.exists() || await file.length() == 0) {
        throw StateError('Audio file unavailable');
      }
      if (_disposed) throw StateError('Extractor disposed');
      final samples = await Future.any([
        _extractor.extractWaveformData(
          path: file.absolute.path,
          noOfSamples: 256,
        ),
        _cancelled.future.then<List<double>>(
          (_) => throw StateError('Extraction cancelled'),
        ),
      ]);
      if (_disposed) throw StateError('Extractor disposed');
      if (samples.isEmpty ||
          samples.any((sample) => !sample.isFinite || sample < 0)) {
        throw const FormatException('Invalid waveform samples');
      }
      final peak = samples.reduce(math.max);
      // Silence remains flat; no invented amplitudes or synthetic pattern.
      return List.unmodifiable(
        samples.map((sample) => peak == 0 ? 0.0 : sample / peak),
      );
    } finally {
      _extracting = false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelled.complete();
    if (_extracting) {
      try {
        await _extractor.stopWaveformExtraction();
      } catch (_) {
        // Leaving a story must remain safe even if native extraction failed.
      }
    }
  }
}
