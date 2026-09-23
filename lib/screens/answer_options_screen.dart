import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/question.dart';
import '../services/family_story_storage.dart';
import 'question_screen.dart';

class AnswerOptionsScreen extends StatelessWidget {
  const AnswerOptionsScreen({
    required this.familyMember,
    required this.question,
    required this.familyStoryStorage,
    super.key,
  });

  final FamilyMember familyMember;
  final Question question;
  final FamilyStoryStorage familyStoryStorage;

  Future<void> _answerNow(BuildContext context) async {
    final storySaved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => QuestionScreen(
          familyMember: familyMember,
          question: question,
          familyStoryStorage: familyStoryStorage,
        ),
      ),
    );
    if (storySaved == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _showSendInformation(BuildContext context) async {
    final inviteRequested = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.person_add_alt_1_outlined),
        title: Text('Enviar a ${familyMember.name}'),
        content: Text(
          'Para enviar preguntas a ${familyMember.name}, primero tendrás que invitarle a Family Stories.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Invitar a ${familyMember.name}'),
          ),
        ],
      ),
    );

    if (inviteRequested == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Las invitaciones estarán disponibles próximamente.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Cómo responder')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  question.text,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(20),
                    leading: const CircleAvatar(
                      child: Icon(Icons.mic_outlined),
                    ),
                    title: const Text('Responder ahora'),
                    subtitle: const Text(
                      'Graba la respuesta en este dispositivo',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _answerNow(context),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(20),
                    leading: const CircleAvatar(
                      child: Icon(Icons.send_outlined),
                    ),
                    title: Text('Enviar a ${familyMember.name}'),
                    subtitle: const Text(
                      'Para que responda desde su dispositivo',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showSendInformation(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
