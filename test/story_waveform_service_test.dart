import 'dart:async';
import 'dart:io';

import 'package:family_stories_app/services/story_waveform_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('simform_audio_waveforms_plugin/methods');
  late Directory directory;
  late File audio;
  late DeviceStoryWaveformService service;
  final calls = <MethodCall>[];
  List<double> samples = [];
  Completer<List<double>>? gate;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aritoria_waveform_');
    audio = await File('${directory.path}/answer with spaces.m4a')
        .writeAsBytes([1, 2, 3]);
    service = DeviceStoryWaveformService();
    calls.clear();
    samples = [.1, .5, .25, 0];
    gate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'extractWaveformData') {
            return gate?.future ?? samples;
          }
          if (call.method == 'stopExtraction') return null;
          fail('Extractor must not prepare, play or record: ${call.method}');
        });
  });

  tearDown(() async {
    await service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test(
    'extracts local .m4a independently and normalizes real RMS samples',
    () async {
      expect(await service.extract(audio.path), [.2, 1, .5, 0]);
      expect(calls.single.method, 'extractWaveformData');
      expect(calls.single.arguments['path'], audio.absolute.path);
      expect(calls.single.arguments['noOfSamples'], 256);
    },
  );

  test('silent audio stays flat', () async {
    samples = [0, 0, 0];
    expect(await service.extract(audio.path), [0, 0, 0]);
  });

  test('missing/empty files do not enter native extraction', () async {
    await expectLater(
      service.extract('${directory.path}/missing.m4a'),
      throwsStateError,
    );
    await audio.writeAsBytes([]);
    await expectLater(service.extract(audio.path), throwsStateError);
    expect(calls, isEmpty);
  });

  test(
    'empty or invalid native results are rejected for slider fallback',
    () async {
      for (final values in <List<double>>[
        [],
        [double.nan],
        [double.infinity],
        [-.2],
      ]) {
        samples = values;
        await expectLater(service.extract(audio.path), throwsFormatException);
      }
    },
  );

  test('dispose cancels native work and rejects late results; no concurrent extraction', () async {
    gate = Completer<List<double>>();
    final extracting = service.extract(audio.path);
    final rejected = expectLater(extracting, throwsStateError);
    await expectLater(service.extract(audio.path), throwsStateError);
    // Wait for file checks to reach the mocked native extractor.
    while (calls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await service.dispose();
    await rejected;
    gate!.complete([1, 2]);
    expect(calls.map((call) => call.method), [
      'extractWaveformData',
      'stopExtraction',
    ]);
    await expectLater(service.extract(audio.path), throwsStateError);
  });
}
