import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/question.dart';
import '../services/auth_service.dart';
import '../services/family_story_storage.dart';
import '../services/family_member_service.dart';
import '../services/invitation_service.dart';
import '../services/invitation_share_service.dart';
import '../services/question_request_service.dart';
import 'answer_options_screen.dart';

class CategoryQuestionsScreen extends StatelessWidget {
  const CategoryQuestionsScreen({
    required this.familyMember,
    required this.category,
    required this.familyStoryStorage,
    required this.authService,
    required this.invitationService,
    required this.invitationShareService,
    required this.familyMemberService,
    required this.questionRequestService,
    required this.isRemoteFamilyMember,
    super.key,
  });

  final FamilyMember familyMember;
  final QuestionCategory category;
  final FamilyStoryStorage familyStoryStorage;
  final AuthService authService;
  final InvitationService invitationService;
  final InvitationShareService invitationShareService;
  final FamilyMemberService familyMemberService;
  final QuestionRequestService questionRequestService;
  final bool isRemoteFamilyMember;

  Future<void> _openQuestion(BuildContext context, Question question) async {
    final storySaved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AnswerOptionsScreen(
          familyMember: familyMember,
          question: question,
          familyStoryStorage: familyStoryStorage,
          authService: authService,
          invitationService: invitationService,
          invitationShareService: invitationShareService,
          familyMemberService: familyMemberService,
          questionRequestService: questionRequestService,
          isRemoteFamilyMember: isRemoteFamilyMember,
        ),
      ),
    );
    if (storySaved == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: category.questions.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      category.description,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                final question = category.questions[index - 1];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    title: Text(question.text),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openQuestion(context, question),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
