import 'package:audioplayers/audioplayers.dart';
import 'package:family_stories_app/services/audio_answer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

class _Player extends Fake implements AudioPlayer {
  Source? currentSource;
  Duration? duration = const Duration(milliseconds: 42500);
  final sources = <Source>[];
  final positions = <Duration>[];
  @override
  Source? get source => currentSource;
  @override
  Future<void> setSource(Source source) async {
    sources.add(source);
    currentSource = source;
  }

  @override
  Future<Duration?> getDuration() async => duration;
  @override
  Future<void> seek(Duration position) async {
    positions.add(position);
  }
}

class _Recorder extends Fake implements AudioRecorder {}

void main() {
  test('seek prepares a local file without playing and uses its real duration', () async {
    final player = _Player();
    final service = DeviceAudioAnswerService(
      player: player,
      recorder: _Recorder(),
    );
    await service.seek('/private/answer.m4a', .5);
    expect(player.sources.single, isA<DeviceFileSource>());
    expect(
      (player.sources.single as DeviceFileSource).path,
      '/private/answer.m4a',
    );
    expect(player.positions.single, const Duration(milliseconds: 21250));
    await service.seek('/private/answer.m4a', .75);
    expect(player.sources, hasLength(1));
    expect(player.positions.last, const Duration(milliseconds: 31875));
    // play/resume/pause are deliberately not implemented: any call would fail.
  });

  test('seek reloads a released source after playback completes', () async {
    final player = _Player();
    final service = DeviceAudioAnswerService(
      player: player,
      recorder: _Recorder(),
    );
    await service.seek('/private/answer.m4a', .2);
    player.currentSource = null;
    await service.seek('/private/answer.m4a', .4);
    expect(player.sources, hasLength(2));
    expect(player.positions.last, const Duration(seconds: 17));
  });

  test(
    'seek clamps gestures at both ends and rejects invalid duration/position',
    () async {
      final player = _Player();
      final service = DeviceAudioAnswerService(
        player: player,
        recorder: _Recorder(),
      );
      await service.seek('/private/answer.m4a', -1);
      await service.seek('/private/answer.m4a', 2);
      expect(player.positions, [Duration.zero, player.duration]);
      await expectLater(
        service.seek('/private/answer.m4a', double.nan),
        throwsArgumentError,
      );
      player.duration = null;
      await expectLater(
        service.seek('/private/answer.m4a', .5),
        throwsStateError,
      );
      player.duration = Duration.zero;
      await expectLater(
        service.seek('/private/answer.m4a', .5),
        throwsStateError,
      );
      expect(player.positions, hasLength(2));
    },
  );
}
