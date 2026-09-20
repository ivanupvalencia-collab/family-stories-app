import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/question.dart';

class QuestionScreen extends StatelessWidget {
  const QuestionScreen({
    required this.familyMember,
    required this.question,
    super.key,
  });

  final FamilyMember familyMember;
  final Question question;

  void _showAudioMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Grabación de audio próximamente')),
    );
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
                    'Para ${familyMember.name}',
                    style: textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    question.text,
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => _showAudioMessage(context),
                    icon: const Icon(Icons.mic_outlined),
                    label: const Text('Grabar respuesta'),
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
