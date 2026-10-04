import 'package:flutter/material.dart';

import '../data/predefined_questions.dart';
import '../models/family_member.dart';
import '../models/question.dart';
import '../services/auth_service.dart';
import '../services/family_story_storage.dart';
import '../services/family_member_service.dart';
import '../services/invitation_service.dart';
import '../services/invitation_share_service.dart';
import 'category_questions_screen.dart';
import 'custom_question_screen.dart';

class QuestionsScreen extends StatelessWidget {
  const QuestionsScreen({
    required this.familyMember,
    required this.familyStoryStorage,
    required this.authService,
    required this.invitationService,
    required this.invitationShareService,
    required this.familyMemberService,
    required this.isRemoteFamilyMember,
    super.key,
  });

  final FamilyMember familyMember;
  final FamilyStoryStorage familyStoryStorage;
  final AuthService authService;
  final InvitationService invitationService;
  final InvitationShareService invitationShareService;
  final FamilyMemberService familyMemberService;
  final bool isRemoteFamilyMember;

  Future<void> _openCategory(
    BuildContext context,
    QuestionCategory category,
  ) async {
    final storySaved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CategoryQuestionsScreen(
          familyMember: familyMember,
          category: category,
          familyStoryStorage: familyStoryStorage,
          authService: authService,
          invitationService: invitationService,
          invitationShareService: invitationShareService,
          familyMemberService: familyMemberService,
          isRemoteFamilyMember: isRemoteFamilyMember,
        ),
      ),
    );
    if (storySaved == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openCustomQuestion(BuildContext context) async {
    final storySaved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CustomQuestionScreen(
          familyMember: familyMember,
          familyStoryStorage: familyStoryStorage,
          authService: authService,
          invitationService: invitationService,
          invitationShareService: invitationShareService,
          familyMemberService: familyMemberService,
          isRemoteFamilyMember: isRemoteFamilyMember,
        ),
      ),
    );
    if (storySaved == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  IconData _categoryIcon(String categoryName) {
    return switch (categoryName) {
      'Infancia' => Icons.child_care,
      'Familia' => Icons.family_restroom,
      'Juventud' => Icons.school_outlined,
      'Amor y relaciones' => Icons.favorite_outline,
      'Vida' => Icons.auto_stories_outlined,
      _ => Icons.question_answer_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Elige una categoría')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Card(
                  color: theme.colorScheme.secondaryContainer,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openCustomQuestion(context),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 32,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Escribir mi propia pregunta',
                              style: textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'O elige una categoría',
                        style: textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
                ...predefinedQuestionCategories.map(
                  (category) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _openCategory(context, category),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              child: Icon(
                                _categoryIcon(category.name),
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    category.name,
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    category.description,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
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
