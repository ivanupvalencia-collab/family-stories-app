import 'package:flutter/material.dart';

import '../widgets/question_text.dart';

import '../models/question.dart';
import '../models/question_request.dart';
import '../services/audio_answer_service.dart';
import '../services/question_request_service.dart';
import 'question_screen.dart';

class QuestionRequestScreen extends StatefulWidget {
  const QuestionRequestScreen({
    required this.questionRequest,
    required this.questionRequestService,
    this.audioService,
    super.key,
  });

  final QuestionRequest questionRequest;
  final QuestionRequestService questionRequestService;
  final AudioAnswerService? audioService;

  @override
  State<QuestionRequestScreen> createState() => _QuestionRequestScreenState();
}

class _QuestionRequestScreenState extends State<QuestionRequestScreen> {
  Future<void> _submitAnswer({
    required String audioPath,
    required Duration duration,
  }) async {
    final objectPath = createQuestionAnswerObjectPath(
      widget.questionRequest.id,
    );
    var uploaded = false;

    try {
      await widget.questionRequestService.uploadAnswerAudio(
        localAudioPath: audioPath,
        objectPath: objectPath,
      );
      uploaded = true;
      await widget.questionRequestService.completeQuestionRequest(
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
  }

  Future<void> _openRecorder() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => QuestionScreen.forQuestionRequest(
          question: Question(widget.questionRequest.questionText),
          onSubmit: _submitAnswer,
          audioService: widget.audioService,
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
