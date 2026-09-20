import 'package:flutter/material.dart';

import '../models/family_member.dart';
import 'questions_screen.dart';

class FamilyMemberScreen extends StatelessWidget {
  const FamilyMemberScreen({required this.familyMember, super.key});

  final FamilyMember familyMember;

  void _openQuestions(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuestionsScreen(familyMember: familyMember),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(familyMember.name)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    size: 44,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  familyMember.name,
                  textAlign: TextAlign.center,
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  familyMember.relationship,
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'Conoce su historia',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _openQuestions(context),
                  icon: const Icon(Icons.question_answer_outlined),
                  label: const Text('Responder una pregunta'),
                ),
                const SizedBox(height: 40),
                Text(
                  'Sus historias',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.auto_stories_outlined,
                          size: 40,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Aquí aparecerán sus historias cuando guarde sus respuestas.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
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
