import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/question_answer_view.dart';

import '../models/family_member.dart';
import '../models/question.dart';
import '../services/audio_answer_service.dart';
import '../services/family_story_storage.dart';
import '../services/story_photo_service.dart';
import '../services/profile_image_picker.dart';

enum _RecordingStatus { ready, recording, recorded }

typedef RecordingSubmission = Future<void> Function({
  required String audioPath,
  required Duration duration,
  PickedProfileImage? photo,
});

class QuestionScreen extends StatefulWidget {
  const QuestionScreen({
    required this.familyMember,
    required this.question,
    this.audioService,
    this.familyStoryStorage,
    this.photoService,
    this.imagePicker,
    this.startImmediately = false,
    super.key,
  }) : onSubmit = null,
       senderName = null,
       submitLabel = 'Guardar historia',
       submittingLabel = 'Guardando historia...',
       submitErrorMessage =
           'No se pudo guardar la historia. Inténtalo de nuevo.',
       submitIcon = Icons.save_outlined;

  const QuestionScreen.forQuestionRequest({
    required this.question,
    required this.onSubmit,
    this.audioService,
    this.photoService,
    this.imagePicker,
    this.senderName,
    super.key,
  }) : familyMember = null,
       familyStoryStorage = null,
       startImmediately = true,
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
  final bool startImmediately;
  final String? senderName;
  final String submitLabel;
  final String submittingLabel;
  final String submitErrorMessage;
  final IconData submitIcon;
  final StoryPhotoService? photoService;
  final ProfileImagePicker? imagePicker;

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  late final AudioAnswerService _audioService;
  late final FamilyStoryStorage? _familyStoryStorage;
  late final StreamSubscription<void> _playbackCompleteSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration> _durationSubscription;
  Duration _playbackDuration = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  double _playbackProgress = 0;

  _RecordingStatus _status = _RecordingStatus.ready;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  String? _recordingPath;
  bool _isPlaying = false;
  bool _isPlaybackPaused = false;
  bool _isBusy = false;
  bool _isSubmitting = false;
  bool _isSeeking = false;
  double? _pendingSeek;
  int _playbackCompletions = 0;
  PickedProfileImage? _photo;

  @override
  void initState() {
    super.initState();
    _audioService = widget.audioService ?? DeviceAudioAnswerService();
    _positionSubscription = _audioService.onPositionChanged.listen((position) {
      if (!mounted || _isSeeking || _status != _RecordingStatus.recorded) {
        return;
      }
      setState(() {
        _playbackPosition = position;
        _updatePlaybackProgress();
      });
    });
    _durationSubscription = _audioService.onDurationChanged.listen((duration) {
      if (!mounted || duration <= Duration.zero) return;
      setState(() {
        _playbackDuration = duration;
        if (!_isSeeking) _updatePlaybackProgress();
      });
    });
    _familyStoryStorage = widget.onSubmit == null
        ? widget.familyStoryStorage ?? LocalFamilyStoryStorage()
        : widget.familyStoryStorage;
    _playbackCompleteSubscription = _audioService.onPlaybackComplete.listen((
      _,
    ) {
      if (!mounted) {
        return;
      }
      _playbackCompletions++;
      setState(() {
        _isPlaying = false;
        _isPlaybackPaused = false;
        _playbackProgress = 1;
        _playbackPosition = _playbackDuration;
      });
    });
    if (widget.startImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startRecording());
      });
    }
  }

  void _updatePlaybackProgress() {
    if (_playbackDuration > Duration.zero) {
      _playbackProgress =
          (_playbackPosition.inMicroseconds / _playbackDuration.inMicroseconds)
              .clamp(0.0, 1.0);
    }
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
      if (!mounted) return;
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
          setState(() {
            _playbackPosition = Duration.zero;
            _playbackProgress = 0;
          });
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
          _playbackDuration = Duration.zero;
          _playbackPosition = Duration.zero;
          _playbackProgress = 0;
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

  Future<void> _seekTo(double fraction) async {
    if ((_isBusy && !_isSeeking) ||
        _recordingPath == null ||
        _status != _RecordingStatus.recorded ||
        !fraction.isFinite) {
      return;
    }
    _pendingSeek = fraction.clamp(0.0, 1.0);
    if (_isSeeking) return;
    _isSeeking = true;
    setState(() => _isBusy = true);
    try {
      // Coalesce drag updates; the last position wins without concurrent seeks.
      while (mounted && _pendingSeek != null) {
        final target = _pendingSeek!;
        _pendingSeek = null;
        final completionsBeforeSeek = _playbackCompletions;
        await _audioService.seek(_recordingPath!, target);
        if (mounted && completionsBeforeSeek == _playbackCompletions) {
          setState(() {
            _playbackProgress = target;
            _playbackPosition = Duration(
              microseconds: (_playbackDuration.inMicroseconds * target).round(),
            );
          });
        }
        if (mounted &&
            !_isPlaying &&
            completionsBeforeSeek == _playbackCompletions) {
          _isPlaybackPaused = true;
        }
      }
    } catch (_) {
      _pendingSeek = null;
      _showMessage(
        'No se pudo cambiar la posición del audio. Inténtalo de nuevo.',
      );
    } finally {
      _isSeeking = false;
      if (mounted) setState(() => _isBusy = false);
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
        final story = await _familyStoryStorage!.saveRecording(
          familyMemberId: widget.familyMember!.id,
          question: widget.question.text,
          temporaryAudioPath: _recordingPath!,
          duration: _recordingDuration,
        );
        if (_photo != null) {
          try {
            await (widget.photoService ??
                    LocalStoryPhotoService(storage: _familyStoryStorage))
                .save(story, _photo);
          } catch (_) {
            _showMessage(
              'La historia se ha guardado sin foto. Puedes añadirla desde la historia.',
            );
          }
        }
      } else {
        await customSubmission(
          audioPath: _recordingPath!,
          duration: _recordingDuration,
          photo: _photo,
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
    _pendingSeek = null;
    _recordingTimer?.cancel();
    unawaited(_playbackCompleteSubscription.cancel());
    unawaited(_positionSubscription.cancel());
    unawaited(_durationSubscription.cancel());
    unawaited(_audioService.dispose());
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final image = await (widget.imagePicker ?? DeviceProfileImagePicker())
          .pickFromGallery();
      if (mounted && image != null) setState(() => _photo = image);
    } catch (_) {
      _showMessage('No se pudo seleccionar la foto. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return QuestionAnswerView(
      question: widget.question,
      familyMemberName: widget.familyMember?.name,
      submitLabel: widget.submitLabel,
      submittingLabel: widget.submittingLabel,
      submitIcon: widget.submitIcon,
      senderName: widget.senderName,
      stage: switch (_status) {
        _RecordingStatus.ready => QuestionAnswerStage.initial,
        _RecordingStatus.recording => QuestionAnswerStage.recording,
        _RecordingStatus.recorded => QuestionAnswerStage.review,
      },
      duration: _recordingDuration,
      playing: _isPlaying,
      playbackProgress: _playbackProgress,
      busy: _isBusy,
      submitting: _isSubmitting,
      onStart: _startRecording,
      onStop: _stopRecording,
      onCancel: () => Navigator.of(context).maybePop(),
      onPlay: _togglePlayback,
      onSeek: !_isBusy || _isSeeking ? _seekTo : null,
      photoBytes: _photo?.bytes,
      onSend: _submitRecording,
      onRecordAgain: _recordAgain,
      photoControls: Column(
        children: [
          TextButton.icon(
            onPressed: _isBusy ? null : _pickPhoto,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              _photo == null
                  ? 'Añadir una foto (opcional)'
                  : 'Cambiar foto seleccionada',
            ),
          ),
          if (_photo != null)
            TextButton(
              onPressed: _isBusy ? null : () => setState(() => _photo = null),
              child: const Text('Quitar foto seleccionada'),
            ),
        ],
      ),
    );
  }
}
