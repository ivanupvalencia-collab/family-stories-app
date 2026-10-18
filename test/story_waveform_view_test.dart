import 'dart:async';
import 'dart:io';

import 'package:family_stories_app/design/aritoria_design.dart';
import 'package:family_stories_app/models/family_story.dart';
import 'package:family_stories_app/screens/story_screen.dart';
import 'package:family_stories_app/services/story_waveform_service.dart';
import 'package:family_stories_app/services/persistent_story_waveform_service.dart';
import 'package:family_stories_app/widgets/story_waveform_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

class _Waveforms extends StoryWaveformService {
  final paths = <String>[];
  bool fail = false, disposed = false;
  Completer<List<double>>? gate;
  @override
  Future<List<double>> extract(String localAudioPath) async {
    paths.add(localAudioPath);
    if (fail) throw StateError('Native decoder failed');
    return gate?.future ?? [0, .5, 1, .25];
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _Canvas extends Fake implements Canvas {
  final lengths = <double>[];
  final colors = <int>[];
  @override
  void drawLine(Offset a, Offset b, Paint paint) {
    lengths.add((b - a).distance);
    colors.add(paint.color.toARGB32());
  }
}

Widget _app(
  StoryWaveformService waveforms,
  fixtures.FakeAudioAnswerService audio, {
  fixtures.FakeFamilyStoryService? remote,
}) => MaterialApp(
  home: StoryScreen(
    story: FamilyStory(
      id: 'wave-story',
      familyMemberId: 'member',
      question: 'Un recuerdo',
      audioPath: '/local/answer.m4a',
      duration: const Duration(seconds: 20),
      createdAt: DateTime(2026),
    ),
    audioService: audio,
    waveformService: waveforms,
    remoteStoryService: remote,
  ),
);

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'loading uses a spinner, never a temporary slider; extraction failure=$fail',
      (tester) async {
        final waveforms = _Waveforms()..gate = Completer<List<double>>();
        await tester.pumpWidget(
          _app(waveforms, fixtures.FakeAudioAnswerService()),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('story-waveform-loading')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('story-seek')), findsNothing);
        if (fail) {
          waveforms.gate!.completeError(StateError('Native error'));
        } else {
          waveforms.gate!.complete([0, .5, 1]);
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('story-waveform-loading')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('story-seek')),
          fail ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(StoryWaveformView),
          fail ? findsNothing : findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'persisted samples restore without resolving audio and display immediately',
    (tester) async {
      late Directory directory;
      late PersistentStoryWaveformService first, reopened;
      final waveforms = _Waveforms();
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'waveform_screen_cache_',
        );
        final disk = StoryWaveformDiskCache(
          directoryProvider: () async => directory,
        );
        final story = FamilyStory(
          id: 'wave-story',
          familyMemberId: 'member',
          question: 'Un recuerdo',
          audioPath: '/local/answer.m4a',
          duration: const Duration(seconds: 20),
          createdAt: DateTime(2026),
        );
        PersistentStoryWaveformService scope() =>
            PersistentStoryWaveformService(
              backend: 'test',
              account: 'user',
              remote: true,
              disk: disk,
              extractorFactory: () => waveforms,
            );
        first = scope();
        await first.loadForStory(story, () async => '/test/audio.m4a');
        reopened = scope();
        await reopened.loadForStory(
          story,
          () => throw StateError('Cache must avoid audio resolution'),
        );
      });
      await tester.pumpWidget(_app(first, fixtures.FakeAudioAnswerService()));
      expect(find.byType(StoryWaveformView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('story-waveform-loading')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(reopened, fixtures.FakeAudioAnswerService()),
      );
      expect(find.byType(StoryWaveformView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('story-waveform-loading')),
        findsNothing,
      );
      expect(waveforms.paths, ['/test/audio.m4a']);
      await tester.runAsync(() => reopened.invalidate());
      await tester.pumpAndSettle();
      expect(find.byType(StoryWaveformView), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );

  testWidgets(
    'bars represent supplied amplitudes and color only actual progress',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryWaveformView(
              samples: const [0, .5, 1, .25],
              progress: .5,
              onChanged: (_) {},
              onChangeEnd: (_) {},
            ),
          ),
        ),
      );
      final painter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(StoryWaveformView),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;
      final canvas = _Canvas();
      painter.paint(canvas, const Size(100, 48));
      expect(canvas.lengths, [2, 22, 44, 11]);
      expect(
        canvas.colors.take(2),
        everyElement(AritoriaColors.olive.toARGB32()),
      );
      expect(
        canvas.colors.skip(2),
        everyElement(AritoriaColors.sage.withValues(alpha: .55).toARGB32()),
      );
    },
  );

  testWidgets(
    'waveform replaces slider, follows audioplayers and supports tap/drag seek',
    (tester) async {
      final waveforms = _Waveforms();
      final audio = fixtures.FakeAudioAnswerService();
      await tester.pumpWidget(_app(waveforms, audio));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-seek')), findsNothing);
      final wave = find.byKey(const ValueKey('story-waveform'));
      expect(wave, findsOneWidget);
      expect(audio.playedPaths, isEmpty);
      final bounds = tester.getRect(wave);
      await tester.tapAt(
        Offset(bounds.left + bounds.width * .25, bounds.center.dy),
      );
      await tester.pumpAndSettle();
      expect(audio.seeks.single.fraction, closeTo(.25, .01));
      expect(audio.playedPaths, isEmpty);
      expect(
        tester
            .widget<StoryWaveformView>(find.byType(StoryWaveformView))
            .progress,
        closeTo(.25, .01),
      );
      await tester.tap(find.byTooltip('Reproducir historia'));
      await tester.pumpAndSettle();
      expect(audio.resumeCalls, 1);
      audio.updatePlayback(
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StoryWaveformView>(find.byType(StoryWaveformView))
            .progress,
        .5,
      );
      final drag = await tester.startGesture(
        Offset(bounds.left + 3, bounds.center.dy),
      );
      await drag.moveTo(
        Offset(bounds.left + bounds.width * .75, bounds.center.dy),
      );
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(audio.seeks.last.fraction, closeTo(.75, .01));
      expect(audio.pauseCalls, 0);
      expect(waveforms.paths, ['/local/answer.m4a']);
      await tester.pumpWidget(const SizedBox());
      expect(waveforms.disposed, isTrue);
    },
  );

  testWidgets('native extraction failure retains usable slider and playback', (
    tester,
  ) async {
    final waveforms = _Waveforms()..fail = true;
    final audio = fixtures.FakeAudioAnswerService();
    await tester.pumpWidget(_app(waveforms, audio));
    await tester.pumpAndSettle();
    expect(find.byType(StoryWaveformView), findsNothing);
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('story-seek')),
    );
    slider.onChangeEnd!(.5);
    await tester.pumpAndSettle();
    expect(audio.seeks.single.fraction, .5);
    await tester.tap(find.byTooltip('Reproducir historia'));
    await tester.pumpAndSettle();
    expect(audio.resumeCalls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'late extraction after closing cannot update UI; remote uses existing download resolver',
    (tester) async {
      final waveforms = _Waveforms()..gate = Completer<List<double>>();
      final remote = fixtures.FakeFamilyStoryService();
      final audio = fixtures.FakeAudioAnswerService();
      await tester.pumpWidget(_app(waveforms, audio, remote: remote));
      await tester.pump();
      await tester.pump();
      expect(waveforms.paths, [remote.resolvedAudioPath]);
      expect(remote.requestedAudioStoryIds, ['wave-story']);
      expect(audio.playedPaths, isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(waveforms.disposed, isTrue);
      waveforms.gate!.complete([1, .5]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
