import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/question_text.dart';

import '../models/family_story.dart';
import '../services/audio_answer_service.dart';
import '../services/family_story_service.dart';
import '../services/story_photo_service.dart';
import '../services/profile_image_picker.dart';
import '../widgets/story_photo_view.dart';

class StoryScreen extends StatefulWidget {
  const StoryScreen({
    required this.story,
    this.audioService,
    this.remoteStoryService,
    this.photoService,
    this.imagePicker,
    super.key,
  });

  final FamilyStory story;
  final AudioAnswerService? audioService;
  final FamilyStoryService? remoteStoryService;
  final StoryPhotoService? photoService;
  final ProfileImagePicker? imagePicker;

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
  late FamilyStory _story;
  late final StoryPhotoService _photos;
  bool _canEditPhoto = false;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    _story = widget.story;
    _photos =
        widget.photoService ??
        (widget.remoteStoryService == null
            ? LocalStoryPhotoService()
            : SupabaseStoryPhotoService());
    unawaited(_loadPhotoPermissions());
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

  Future<void> _loadPhotoPermissions() async {
    final allowed = await _photos.canEdit(_story);
    if (mounted) setState(() => _canEditPhoto = allowed);
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
            audioPath = widget.remoteStoryService == null
                ? widget.story.audioPath
                : await widget.remoteStoryService!.localAudioPathFor(
                    widget.story,
                  );
            if (!mounted) return;
            _resolvedAudioPath = audioPath;
          }
          await _audioService.play(audioPath);
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
      appBar: AppBar(
        title: const Text('Historia'),
        actions: [
          PopupMenuButton<bool>(
            tooltip: 'Foto de la historia',
            enabled: _canEditPhoto && !_photoBusy,
            onSelected: _managePhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: false,
                child: Text(
                  _story.photoPath == null ? 'Añadir foto' : 'Cambiar foto',
                ),
              ),
              if (_story.photoPath != null)
                const PopupMenuItem(value: true, child: Text('Eliminar foto')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            QuestionText(
                              _story.question,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_story.photoPath != null) ...[
                              StoryPhotoView(
                                story: _story,
                                service: _photos,
                                width: double.infinity,
                                height:
                                    (MediaQuery.sizeOf(context).height * .25)
                                        .clamp(120, 240),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Text(
                              'Duraci\u00f3n: ${_formatDuration(_story.duration)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 32),
                          child: FilledButton.icon(
                            onPressed: _isBusy ? null : _togglePlayback,
                            icon: _isLoadingAudio
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _isPlaying ? Icons.pause : Icons.play_arrow,
                                  ),
                            label: Text(
                              _isLoadingAudio
                                  ? 'Cargando audio...'
                                  : _isPlaying
                                  ? 'Pausar'
                                  : 'Reproducir historia',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
