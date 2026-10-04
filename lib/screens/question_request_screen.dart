import 'package:flutter/material.dart';

import '../models/question_request.dart';

class QuestionRequestScreen extends StatelessWidget {
  const QuestionRequestScreen({required this.questionRequest, super.key});

  final QuestionRequest questionRequest;

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
                  Text(
                    questionRequest.questionText,
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
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Podrás responder esta pregunta próximamente.',
                          ),
                        ),
                      );
                    },
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
