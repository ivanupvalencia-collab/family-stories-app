import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/family_story.dart';
import '../services/audio_answer_service.dart';
import '../services/family_story_service.dart';

class StoryScreen extends StatefulWidget {
  const StoryScreen({
    required this.story,
    this.audioService,
    this.remoteStoryService,
    super.key,
  });

  final FamilyStory story;
  final AudioAnswerService? audioService;
  final FamilyStoryService? remoteStoryService;

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  late final AudioAnswerService _audioService;
  late final StreamSubscription<void> _playbackCompleteSubscription;
  bool _isPlaying = false;
  bool _isPaused = false;
  bool _isBusy = false;
  bool _isLoadingAudio = false;
  String? _resolvedAudioPath;

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
  void initState() {
    super.initState();
    _audioService = widget.audioService ?? DeviceAudioAnswerService();
    _playbackCompleteSubscription = _audioService.onPlaybackComplete.listen((
      _,
    ) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _isPaused = false;
        });
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_isBusy) {
      return;
    }
    setState(() => _isBusy = true);
    var phase = 'playback_state';
    try {
      if (_isPlaying) {
        phase = 'audioplayers_pause';
        await _audioService.pause();
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _isPaused = true;
          });
        }
      } else {
        if (_isPaused) {
          phase = 'audioplayers_resume';
          await _audioService.resume();
        } else {
          var audioPath = _resolvedAudioPath;
          if (audioPath == null) {
            setState(() => _isLoadingAudio = true);
            phase = 'resolve_audio';
            audioPath = widget.remoteStoryService == null
                ? widget.story.audioPath
                : await widget.remoteStoryService!.localAudioPathFor(
                    widget.story,
                  );
            _resolvedAudioPath = audioPath;
          }
          final file = File(audioPath);
          final exists = await file.exists();
          final size = exists ? await file.length() : 0;
          _debugLog(
            'playback',
            'Delivering to audioplayers path=$audioPath '
                'exists=$exists bytes=$size',
          );
          phase = 'audioplayers_play';
          await _audioService.play(audioPath);
          _debugLog('playback', 'audioplayers accepted the file');
        }
        if (mounted) {
          setState(() => _isPlaying = true);
        }
      }
    } catch (error, stackTrace) {
      _debugLog(
        phase,
        'Failure type=${error.runtimeType} message=$error',
        stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo reproducir esta historia.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _isLoadingAudio = false;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    unawaited(_playbackCompleteSubscription.cancel());
    unawaited(_audioService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Historia')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.story.question,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Duración: ${_formatDuration(widget.story.duration)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _isBusy ? null : _togglePlayback,
                    icon: _isLoadingAudio
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(
                      _isLoadingAudio
                          ? 'Cargando audio...'
                          : _isPlaying
                          ? 'Pausar'
                          : 'Reproducir historia',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
