import 'package:flutter/material.dart';

import '../data/question_answer_hints.dart';
import '../widgets/question_answer_view.dart';
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
    this.senderName,
    super.key,
  });

  final QuestionRequest questionRequest;
  final QuestionRequestService questionRequestService;
  final AudioAnswerService? audioService;
  final StoryPhotoService? photoService;
  final ProfileImagePicker? imagePicker;
  final String? senderName;

  @override
  State<QuestionRequestScreen> createState() => _QuestionRequestScreenState();
}

class _QuestionRequestScreenState extends State<QuestionRequestScreen> {
  DateTime? _sentAt;
  bool _openingRecorder = false;
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
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.fromLTRB(16, 0, 16, 96),
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
    if (_openingRecorder) return;
    setState(() => _openingRecorder = true);
    try {
      final sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => QuestionScreen.forQuestionRequest(
            question: questionForReceivedRequest(
              widget.questionRequest.questionText,
            ),
            onSubmit: _submitAnswer,
            audioService: widget.audioService,
            imagePicker: widget.imagePicker,
            photoService: widget.photoService,
            senderName: widget.senderName,
          ),
        ),
      );

      if (sent == true && mounted) {
        setState(() => _sentAt = DateTime.now());
      }
    } finally {
      if (mounted) setState(() => _openingRecorder = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _sentAt == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _sentAt != null) Navigator.of(context).pop(true);
    },
    child: QuestionAnswerView(
      question: questionForReceivedRequest(widget.questionRequest.questionText),
      stage: _sentAt == null
          ? QuestionAnswerStage.initial
          : QuestionAnswerStage.sent,
      startLabel: 'Grabar respuesta',
      senderName: widget.senderName,
      onStart: _openingRecorder ? null : _openRecorder,
      sentAt: _sentAt,
      onReturn: () => Navigator.of(context).pop(true),
    ),
  );
}
