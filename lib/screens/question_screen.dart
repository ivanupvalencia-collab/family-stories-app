import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/question_text.dart';

import '../models/family_member.dart';
import '../models/question.dart';
import '../services/audio_answer_service.dart';
import '../services/family_story_storage.dart';

enum _RecordingStatus { ready, recording, recorded }

typedef RecordingSubmission = Future<void> Function({
  required String audioPath,
  required Duration duration,
});

class QuestionScreen extends StatefulWidget {
  const QuestionScreen({
    required this.familyMember,
    required this.question,
    this.audioService,
    this.familyStoryStorage,
    super.key,
  }) : onSubmit = null,
       contextLabel = null,
       submitLabel = 'Guardar historia',
       submittingLabel = 'Guardando historia...',
       submitErrorMessage =
           'No se pudo guardar la historia. Inténtalo de nuevo.',
       submitIcon = Icons.save_outlined;

  const QuestionScreen.forQuestionRequest({
    required this.question,
    required this.onSubmit,
    this.audioService,
    super.key,
  }) : familyMember = null,
       familyStoryStorage = null,
       contextLabel = 'Tu respuesta',
       submitLabel = 'Enviar respuesta',
       submittingLabel = 'Enviando respuesta...',
       submitErrorMessage =
           'No se pudo enviar la respuesta. Inténtalo de nuevo.',
       submitIcon = Icons.send_outlined;

  final FamilyMember? familyMember;
  final Question question;
  final AudioAnswerService? audioService;
  final FamilyStoryStorage? familyStoryStorage;
  final RecordingSubmission? onSubmit;
  final String? contextLabel;
  final String submitLabel;
  final String submittingLabel;
  final String submitErrorMessage;
  final IconData submitIcon;

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  late final AudioAnswerService _audioService;
  late final FamilyStoryStorage? _familyStoryStorage;
  late final StreamSubscription<void> _playbackCompleteSubscription;

  _RecordingStatus _status = _RecordingStatus.ready;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  String? _recordingPath;
  bool _isPlaying = false;
  bool _isPlaybackPaused = false;
  bool _isBusy = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _audioService = widget.audioService ?? DeviceAudioAnswerService();
    _familyStoryStorage = widget.onSubmit == null
        ? widget.familyStoryStorage ?? LocalFamilyStoryStorage()
        : widget.familyStoryStorage;
    _playbackCompleteSubscription = _audioService.onPlaybackComplete.listen((
      _,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = false;
        _isPlaybackPaused = false;
      });
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startRecording() async {
    if (_isBusy) {
      return;
    }

    setState(() => _isBusy = true);
    try {
      final hasPermission = await _audioService.requestPermission();
      if (!hasPermission) {
        _showMessage('Se necesita acceso al micrófono para grabar respuestas.');
        return;
      }

      await _audioService.startRecording();
      if (!mounted) {
        return;
      }

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _recordingDuration += const Duration(seconds: 1);
          });
        }
      });
      setState(() {
        _recordingDuration = Duration.zero;
        _status = _RecordingStatus.recording;
      });
    } catch (_) {
      _showMessage('No se pudo iniciar la grabación. Inténtalo de nuevo.');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_isBusy) {
      return;
    }

    setState(() => _isBusy = true);
    _recordingTimer?.cancel();

    try {
      final path = await _audioService.stopRecording();
      if (!mounted) {
        return;
      }
      if (path == null) {
        setState(() => _status = _RecordingStatus.ready);
        _showMessage('No se pudo completar la grabación. Inténtalo de nuevo.');
        return;
      }

      setState(() {
        _recordingPath = path;
        _status = _RecordingStatus.recorded;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _status = _RecordingStatus.ready);
      }
      _showMessage('No se pudo detener la grabación. Inténtalo de nuevo.');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_isBusy || _recordingPath == null) {
      return;
    }

    setState(() => _isBusy = true);
    try {
      if (_isPlaying) {
        await _audioService.pause();
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _isPlaybackPaused = true;
          });
        }
      } else {
        if (_isPlaybackPaused) {
          await _audioService.resume();
        } else {
          await _audioService.play(_recordingPath!);
        }
        if (mounted) {
          setState(() => _isPlaying = true);
        }
      }
    } catch (_) {
      _showMessage('No se pudo reproducir el audio. Inténtalo de nuevo.');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _recordAgain() async {
    if (_isBusy || _recordingPath == null) {
      return;
    }

    setState(() => _isBusy = true);
    try {
      await _audioService.discard(_recordingPath!);
      if (mounted) {
        setState(() {
          _recordingPath = null;
          _recordingDuration = Duration.zero;
          _isPlaying = false;
          _isPlaybackPaused = false;
          _status = _RecordingStatus.ready;
        });
      }
    } catch (_) {
      _showMessage('No se pudo descartar la grabación. Inténtalo de nuevo.');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _submitRecording() async {
    if (_isBusy || _recordingPath == null) {
      return;
    }

    setState(() {
      _isBusy = true;
      _isSubmitting = true;
    });
    try {
      if (_isPlaying) {
        await _audioService.pause();
      }
      final customSubmission = widget.onSubmit;
      if (customSubmission == null) {
        await _familyStoryStorage!.saveRecording(
          familyMemberId: widget.familyMember!.id,
          question: widget.question.text,
          temporaryAudioPath: _recordingPath!,
          duration: _recordingDuration,
        );
      } else {
        await customSubmission(
          audioPath: _recordingPath!,
          duration: _recordingDuration,
        );
        try {
          await _audioService.discard(_recordingPath!);
        } catch (_) {
          // The remote answer is complete; temporary cleanup is best effort.
        }
      }
      _recordingPath = null;
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      _showMessage(widget.submitErrorMessage);
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _isPlaybackPaused = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    unawaited(_playbackCompleteSubscription.cancel());
    unawaited(_audioService.dispose());
    super.dispose();
  }

  Widget _buildRecordingControls(ThemeData theme) {
    switch (_status) {
      case _RecordingStatus.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(
              icon: Icons.mic_none,
              title: 'Preparado para grabar',
              message:
                  'Busca un lugar tranquilo y pulsa el botón cuando quieras.',
              color: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isBusy ? null : _startRecording,
              icon: const Icon(Icons.mic_outlined),
              label: const Text('Grabar respuesta'),
            ),
          ],
        );
      case _RecordingStatus.recording:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(
              icon: Icons.fiber_manual_record,
              title: 'Grabando',
              message: _formatDuration(_recordingDuration),
              color: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isBusy ? null : _stopRecording,
              icon: const Icon(Icons.stop),
              label: const Text('Detener grabación'),
            ),
          ],
        );
      case _RecordingStatus.recorded:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(
              icon: _isPlaying ? Icons.graphic_eq : Icons.check_circle_outline,
              title: _isPlaying ? 'Reproduciendo' : 'Grabación terminada',
              message: 'Duración: ${_formatDuration(_recordingDuration)}',
              color: theme.colorScheme.tertiaryContainer,
              foregroundColor: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isBusy ? null : _submitRecording,
              icon: _isSubmitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(widget.submitIcon),
              label: Text(
                _isSubmitting ? widget.submittingLabel : widget.submitLabel,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _togglePlayback,
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(_isPlaying ? 'Pausar' : 'Reproducir'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _isBusy ? null : _recordAgain,
              icon: const Icon(Icons.refresh),
              label: const Text('Volver a grabar'),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Pregunta')),
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
                    widget.contextLabel ?? 'Para ${widget.familyMember!.name}',
                    style: textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  QuestionText(
                    widget.question.text,
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  _buildRecordingControls(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
    required this.foregroundColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 36, color: foregroundColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(message, style: TextStyle(color: foregroundColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
