import 'package:flutter/material.dart';

import '../widgets/question_text.dart';

import '../models/question.dart';
import '../models/question_request.dart';
import '../services/audio_answer_service.dart';
import '../services/question_request_service.dart';
import '../services/story_photo_service.dart';
import '../services/profile_image_picker.dart';
import 'question_screen.dart';

class QuestionRequestScreen extends StatefulWidget {
  const QuestionRequestScreen({
    required this.questionRequest,
    required this.questionRequestService,
    this.audioService,
    this.photoService,
    this.imagePicker,
    super.key,
  });

  final QuestionRequest questionRequest;
  final QuestionRequestService questionRequestService;
  final AudioAnswerService? audioService;
  final StoryPhotoService? photoService;
  final ProfileImagePicker? imagePicker;

  @override
  State<QuestionRequestScreen> createState() => _QuestionRequestScreenState();
}

class _QuestionRequestScreenState extends State<QuestionRequestScreen> {
  Future<void> _submitAnswer({
    required String audioPath,
    required Duration duration,
    PickedProfileImage? photo,
  }) async {
    final objectPath = createQuestionAnswerObjectPath(
      widget.questionRequest.id,
    );
    var uploaded = false;
    late String storyId;

    try {
      await widget.questionRequestService.uploadAnswerAudio(
        localAudioPath: audioPath,
        objectPath: objectPath,
      );
      uploaded = true;
      storyId = await widget.questionRequestService.completeQuestionRequest(
        questionRequestId: widget.questionRequest.id,
        audioPath: objectPath,
        durationSeconds: duration.inSeconds,
      );
    } catch (_) {
      if (uploaded) {
        try {
          await widget.questionRequestService.deleteAnswerAudio(objectPath);
        } catch (_) {
          // Storage cleanup depends on the authenticated user's DELETE policy.
        }
      }
      rethrow;
    }
    if (photo != null) {
      try {
        final service = widget.photoService ?? SupabaseStoryPhotoService();
        // The existing completion RPC's returned ID is authoritative. A
        // separate photo failure never enters the audio rollback above.
        final seed = await widget.questionRequestService.loadAnswerStory(
          widget.questionRequest.id,
        );
        if (seed == null || seed.id != storyId) {
          throw StateError('Answer metadata unavailable');
        }
        await service.save(seed, photo);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'La respuesta se ha enviado sin foto. Puedes añadirla desde Historias contadas.',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _openRecorder() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => QuestionScreen.forQuestionRequest(
          question: Question(widget.questionRequest.questionText),
          onSubmit: _submitAnswer,
          audioService: widget.audioService,
          imagePicker: widget.imagePicker,
          photoService: widget.photoService,
        ),
      ),
    );

    if (sent == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pregunta para ti')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  QuestionText(
                    widget.questionRequest.questionText,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Enviada por otro familiar · Pendiente',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _openRecorder,
                    icon: const Icon(Icons.mic_outlined),
                    label: const Text('Responder'),
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
