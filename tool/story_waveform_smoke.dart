// Native smoke test: flutter run -d emulator-5554 -t tool/story_waveform_smoke.dart
// Reads an existing app-private .m4a without changing it, or records a short
// AAC-LC mono clip with the app's existing recorder when no file is available.
// No Supabase initialization, credentials, backend requests or persisted stories.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/screens/story_screen.dart';
import 'package:family_stories_app/services/audio_answer_service.dart';
import 'package:family_stories_app/services/story_waveform_service.dart';
import 'package:family_stories_app/services/persistent_story_waveform_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: _Smoke()),
);

class _Probe extends StoryWaveformService {
  _Probe(this.started);
  final VoidCallback started;
  final delegate = DeviceStoryWaveformService();
  @override
  Future<List<double>> extract(String localAudioPath) {
    started();
    return delegate.extract(localAudioPath);
  }

  @override
  Future<void> dispose() => delegate.dispose();
}

class _Smoke extends StatefulWidget {
  const _Smoke();
  @override
  State<_Smoke> createState() => _SmokeState();
}

class _SmokeState extends State<_Smoke> {
  Widget? _result;
  DeviceAudioAnswerService? _recorder;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      final temp = await getTemporaryDirectory();
      final docs = await getApplicationDocumentsDirectory();
      File? audio;
      for (final directory in [
        Directory('${temp.path}/remote_story_audio'),
        Directory('${docs.path}/stories'),
      ]) {
        if (await directory.exists()) {
          await for (final entry in directory.list()) {
            if (entry is File &&
                entry.path.endsWith('.m4a') &&
                await entry.length() > 0) {
              audio = entry;
              break;
            }
          }
        }
        if (audio != null) break;
      }
      final source = audio == null
          ? 'recorded_aac_lc_mono_m4a'
          : 'existing_private_m4a';
      if (audio == null) {
        _recorder = DeviceAudioAnswerService();
        if (!await _recorder!.requestPermission()) {
          throw StateError('Microphone permission required');
        }
        await _recorder!.startRecording();
        await Future<void>.delayed(const Duration(seconds: 3));
        final path = await _recorder!.stopRecording();
        if (path == null) throw StateError('Recording failed');
        audio = File(path);
      }
      final reference = FamilyStory(
        id: 'smoke',
        familyMemberId: 'smoke',
        question: 'Una historia para comprobar su onda real',
        audioPath: audio.path,
        duration: const Duration(seconds: 3),
        createdAt: DateTime.now(),
      );
      var extractions = 0;
      final disk = StoryWaveformDiskCache();
      PersistentStoryWaveformService scope() => PersistentStoryWaveformService(
        backend: 'native-smoke',
        account: 'device',
        remote: false,
        disk: disk,
        extractorFactory: () => _Probe(() => extractions++),
      );
      await scope().forgetFamily(
        'smoke',
      ); // Only this tool's private namespace.
      final cold = scope();
      final results = await Future.wait([
        cold.loadForStory(reference, () async => audio!.path),
        cold.loadForStory(reference, () async => audio!.path),
      ]).timeout(const Duration(seconds: 45));
      final samples = results.first;
      final reopened = scope();
      final timer = Stopwatch()..start();
      final restored = await reopened.loadForStory(
        reference,
        () => throw StateError('Cache must avoid audio resolution'),
      );
      timer.stop();
      if (extractions != 1 || restored.length != samples.length) {
        throw StateError('Persistent cache validation failed');
      }
      if (samples.isEmpty ||
          samples.any(
            (sample) => !sample.isFinite || sample < 0 || sample > 1,
          )) {
        throw StateError('Invalid native samples');
      }
      debugPrint(
        'WAVEFORM_SMOKE_OK source=$source samples=${samples.length} min=${samples.reduce(math.min)} max=${samples.reduce(math.max)}',
      );
      debugPrint(
        'WAVEFORM_CACHE_SMOKE_OK extractions=$extractions reopened_ms=${timer.elapsedMilliseconds} samples=${restored.length}',
      );
      if (mounted) {
        setState(
          () => _result = StoryScreen(
            story: reference,
            authorName: 'Prueba de audio',
            waveformService: reopened,
          ),
        );
      }
    } catch (error) {
      debugPrint('WAVEFORM_SMOKE_FAIL ${error.runtimeType}');
      if (mounted) {
        setState(
          () => _result = const Scaffold(
            body: Center(child: Text('Native waveform test failed')),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(_recorder?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _result ??
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
