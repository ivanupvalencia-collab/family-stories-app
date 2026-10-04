import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/question.dart';
import '../services/auth_service.dart';
import '../services/family_member_service.dart';
import '../services/family_story_storage.dart';
import '../services/invitation_service.dart';
import '../services/invitation_share_service.dart';
import 'invitation_details_screen.dart';
import 'question_screen.dart';

class AnswerOptionsScreen extends StatefulWidget {
  const AnswerOptionsScreen({
    required this.familyMember,
    required this.question,
    required this.familyStoryStorage,
    required this.authService,
    required this.invitationService,
    required this.invitationShareService,
    required this.familyMemberService,
    required this.isRemoteFamilyMember,
    super.key,
  });

  final FamilyMember familyMember;
  final Question question;
  final FamilyStoryStorage familyStoryStorage;
  final AuthService authService;
  final InvitationService invitationService;
  final InvitationShareService invitationShareService;
  final FamilyMemberService familyMemberService;
  final bool isRemoteFamilyMember;

  @override
  State<AnswerOptionsScreen> createState() => _AnswerOptionsScreenState();
}

class _AnswerOptionsScreenState extends State<AnswerOptionsScreen> {
  bool _isCreatingInvitation = false;
  bool _isRefreshingFamilyMember = false;

  Future<void> _answerNow(BuildContext context) async {
    final storySaved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => QuestionScreen(
          familyMember: widget.familyMember,
          question: widget.question,
          familyStoryStorage: widget.familyStoryStorage,
        ),
      ),
    );
    if (storySaved == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _showSendInformation() async {
    if (_isCreatingInvitation || _isRefreshingFamilyMember) {
      return;
    }

    final user = widget.authService.currentUser;
    FamilyMember familyMember = widget.familyMember;
    if (widget.isRemoteFamilyMember && user != null) {
      setState(() => _isRefreshingFamilyMember = true);
      try {
        final refreshedMember = await widget.familyMemberService
            .loadMemberForOwner(
              ownerId: user.id,
              familyMemberId: widget.familyMember.id,
            );
        if (!mounted) {
          return;
        }
        if (refreshedMember == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo actualizar el familiar. Inténtalo de nuevo.',
              ),
            ),
          );
          return;
        }
        familyMember = refreshedMember;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo actualizar el familiar. Inténtalo de nuevo.',
              ),
            ),
          );
        }
        return;
      } finally {
        if (mounted) {
          setState(() => _isRefreshingFamilyMember = false);
        }
      }
    }

    if (familyMember.linkedAccountId != null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.link),
          title: const Text('Familiar vinculado'),
          content: Text(
            '${familyMember.name} ya está vinculado a una cuenta de Family Stories.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    if (!widget.isRemoteFamilyMember || user == null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.account_circle_outlined),
          title: const Text('Necesitas iniciar sesión'),
          content: const Text(
            'Inicia sesión para invitar y conectar con otras personas en Family Stories.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

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

    if (inviteRequested == true && mounted) {
      await _createInvitation(familyMember);
    }
  }

  Future<void> _createInvitation(FamilyMember familyMember) async {
    if (_isCreatingInvitation) {
      return;
    }

    setState(() => _isCreatingInvitation = true);
    try {
      final invitation = await widget.invitationService.createInvitation(
        familyMember.id,
      );
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => InvitationDetailsScreen(
            familyMemberName: familyMember.name,
            invitation: invitation,
            shareService: widget.invitationShareService,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo crear la invitación. Inténtalo de nuevo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingInvitation = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final familyMember = widget.familyMember;

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
                  widget.question.text,
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
                    subtitle: Text(
                      _isCreatingInvitation
                          ? 'Creando invitación...'
                          : _isRefreshingFamilyMember
                          ? 'Actualizando familiar...'
                          : 'Para que responda desde su dispositivo',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _isCreatingInvitation || _isRefreshingFamilyMember
                        ? null
                        : _showSendInformation,
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
