import 'dart:async';

import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';
import '../widgets/story_detail_view.dart';

import '../models/family_story.dart';
import '../services/audio_answer_service.dart';
import '../services/family_story_service.dart';
import '../services/story_photo_service.dart';
import '../services/story_waveform_service.dart';
import '../services/persistent_story_waveform_service.dart';
import '../services/profile_image_picker.dart';
import '../widgets/story_photo_view.dart';

class StoryScreen extends StatefulWidget {
  const StoryScreen({
    required this.story,
    this.audioService,
    this.remoteStoryService,
    this.photoService,
    this.imagePicker,
    this.authorName,
    this.recipientName,
    this.waveformService,
    super.key,
  });

  final FamilyStory story;
  final AudioAnswerService? audioService;
  final FamilyStoryService? remoteStoryService;
  final StoryPhotoService? photoService;
  final ProfileImagePicker? imagePicker;
  final String? authorName, recipientName;
  final StoryWaveformService? waveformService;

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  late final AudioAnswerService _audioService;
  late final StreamSubscription<void> _playbackCompleteSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration> _durationSubscription;
  Duration _position = Duration.zero;
  late Duration _duration;
  double? _scrubFraction;
  bool _isSeeking = false;
  int _completions = 0;
  bool _isPlaying = false;
  bool _isPaused = false;
  bool _isBusy = false;
  bool _isLoadingAudio = false;
  String? _resolvedAudioPath;
  late FamilyStory _story;
  late final StoryPhotoService _photos;
  bool _canEditPhoto = false;
  bool _photoBusy = false;
  late final StoryWaveformService _waveforms;
  late final StreamSubscription<String?> _waveformInvalidation;
  List<double>? _waveform;
  Future<String>? _audioResolution;
  bool _extractingWaveform = false;
  bool _waveformLoading = true;

  @override
  void initState() {
    super.initState();
    _story = widget.story;
    final remote = widget.remoteStoryService;
    _waveforms =
        widget.waveformService ??
        (remote == null
            ? StoryWaveforms.local
            : remote is StoryWaveformProvider
            ? (remote as StoryWaveformProvider).waveforms
            : DeviceStoryWaveformService());
    _waveform = _waveforms.cachedForStory(_story);
    _waveformInvalidation = _waveforms.invalidations.listen((family) {
      if (mounted && (family == null || family == _story.familyMemberId)) {
        setState(() {
          _waveform = null;
          _waveformLoading = false;
        });
      }
    });
    _waveformLoading = _waveform == null;
    if (_waveform == null) unawaited(_loadWaveform());
    _duration = _story.duration;
    _photos =
        widget.photoService ??
        (widget.remoteStoryService == null
            ? LocalStoryPhotoService()
            : SupabaseStoryPhotoService());
    unawaited(_loadPhotoPermissions());
    _audioService = widget.audioService ?? DeviceAudioAnswerService();
    _positionSubscription = _audioService.onPositionChanged.listen((position) {
      if (mounted && !_isSeeking) {
        setState(
          () => _position = position < Duration.zero
              ? Duration.zero
              : position > _duration
              ? _duration
              : position,
        );
      }
    });
    _durationSubscription = _audioService.onDurationChanged.listen((duration) {
      if (mounted && duration > Duration.zero) {
        setState(() => _duration = duration);
      }
    });
    _playbackCompleteSubscription = _audioService.onPlaybackComplete.listen((
      _,
    ) {
      if (mounted) {
        _completions++;
        setState(() {
          _isPlaying = false;
          _isPaused = false;
          _position = _duration;
        });
      }
    });
  }

  Future<String> _localAudioPath() async {
    if (_audioResolution != null) return _audioResolution!;
    final future = widget.remoteStoryService == null
        ? Future.value(_story.audioPath)
        : widget.remoteStoryService!.localAudioPathFor(_story);
    _audioResolution = future;
    try {
      final path = await future;
      if (mounted) _resolvedAudioPath = path;
      return path;
    } finally {
      if (identical(_audioResolution, future)) _audioResolution = null;
    }
  }

  Future<void> _loadWaveform({String? path}) async {
    if (_extractingWaveform || _waveform != null) return;
    _extractingWaveform = true;
    if (!_waveformLoading) setState(() => _waveformLoading = true);
    try {
      final samples = await _waveforms.loadForStory(_story, () async {
        if (!mounted) throw StateError('Story closed');
        return path ?? await _localAudioPath();
      });
      if (mounted) setState(() => _waveform = samples.isEmpty ? null : samples);
    } catch (_) {
      // Waveform is optional. Keep playback and the original slider available.
    } finally {
      _extractingWaveform = false;
      if (mounted) setState(() => _waveformLoading = false);
    }
  }

  Future<void> _loadPhotoPermissions() async {
    try {
      final allowed = await _photos.canEdit(_story);
      if (mounted) setState(() => _canEditPhoto = allowed);
    } catch (_) {
      // Playback remains available when photo permissions cannot be loaded.
    }
  }

  Future<void> _managePhoto(bool remove) async {
    if (!_canEditPhoto || _photoBusy) return;
    setState(() => _photoBusy = true);
    try {
      final image = remove
          ? null
          : await (widget.imagePicker ?? DeviceProfileImagePicker())
                .pickFromGallery();
      if (!mounted || (!remove && image == null)) return;
      final updated = await _photos.save(_story, image);
      if (mounted) setState(() => _story = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo guardar la foto. La historia y su audio siguen disponibles.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _togglePlayback() async {
    if (_isBusy) {
      return;
    }
    setState(() => _isBusy = true);
    try {
      if (_isPlaying) {
        await _audioService.pause();
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _isPaused = true;
          });
        }
      } else {
        if (_isPaused) {
          await _audioService.resume();
        } else {
          var audioPath = _resolvedAudioPath;
          // Revalidate remote cache entries on every fresh playback. Temporary
          // files may have been removed or truncated since the previous play.
          if (audioPath == null || widget.remoteStoryService != null) {
            setState(() => _isLoadingAudio = true);
            audioPath = await _localAudioPath();
            if (!mounted) return;
            _resolvedAudioPath = audioPath;
          }
          unawaited(_loadWaveform(path: audioPath));
          await _audioService.play(audioPath);
          if (mounted) setState(() => _position = Duration.zero);
        }
        if (mounted) {
          setState(() => _isPlaying = true);
        }
      }
    } catch (_) {
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

  Future<void> _seekTo(double fraction) async {
    if (_isBusy || !fraction.isFinite) return;
    setState(() {
      _isBusy = true;
      _isSeeking = true;
    });
    final completions = _completions;
    try {
      var path = _resolvedAudioPath;
      if (path == null || (!_isPlaying && !_isPaused)) {
        setState(() => _isLoadingAudio = widget.remoteStoryService != null);
        path = await _localAudioPath();
        if (!mounted) return;
        _resolvedAudioPath = path;
      }
      await _audioService.seek(path, fraction);
      if (mounted && completions == _completions) {
        setState(() {
          _position = Duration(
            microseconds: (_duration.inMicroseconds * fraction.clamp(0.0, 1.0))
                .round(),
          );
          if (!_isPlaying) _isPaused = true;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo cambiar la posición del audio. Inténtalo de nuevo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _isSeeking = false;
          _isLoadingAudio = false;
          _scrubFraction = null;
        });
      }
    }
  }

  String get _date {
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final date = _story.createdAt.toLocal();
    return '${date.day} de ${months[date.month - 1]} de ${date.year}';
  }

  @override
  void dispose() {
    unawaited(_playbackCompleteSubscription.cancel());
    unawaited(_positionSubscription.cancel());
    unawaited(_durationSubscription.cancel());
    unawaited(_audioService.dispose());
    unawaited(_waveforms.dispose());
    unawaited(_waveformInvalidation.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AritoriaDesign.theme(),
    child: StoryDetailView(
      question: _story.question,
      authorName: widget.authorName,
      recipientName: widget.recipientName,
      date: _date,
      position: _scrubFraction == null
          ? _position
          : Duration(
              microseconds: (_duration.inMicroseconds * _scrubFraction!)
                  .round(),
            ),
      duration: _duration,
      playing: _isPlaying,
      waveform: _waveform,
      waveformLoading: _waveformLoading,
      loading: _isLoadingAudio,
      onPlay: _isBusy ? null : _togglePlayback,
      onSeekChanged: _isBusy || _duration <= Duration.zero
          ? null
          : (value) => setState(() => _scrubFraction = value),
      onSeekEnd: _isBusy || _duration <= Duration.zero ? null : _seekTo,
      onSeekCancel: () {
        if (_scrubFraction != null) setState(() => _scrubFraction = null);
      },
      photo: _story.photoPath == null
          ? null
          : LayoutBuilder(
              builder: (context, constraints) => StoryPhotoView(
                story: _story,
                service: _photos,
                width: constraints.maxWidth,
                height: constraints.maxWidth * .72,
              ),
            ),
      photoMenu: PopupMenuButton<bool>(
        tooltip: 'Foto de la historia',
        enabled: _canEditPhoto && !_photoBusy,
        onSelected: _managePhoto,
        icon: const Icon(Icons.more_horiz),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: false,
            child: Text(
              _story.photoPath == null ? 'A\u00f1adir foto' : 'Cambiar foto',
            ),
          ),
          if (_story.photoPath != null)
            const PopupMenuItem(value: true, child: Text('Eliminar foto')),
        ],
      ),
    ),
  );
}
