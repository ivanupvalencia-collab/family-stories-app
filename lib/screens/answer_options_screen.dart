import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';

import '../widgets/question_text.dart';
import '../widgets/aritoria_footer_wave.dart';

import '../models/family_member.dart';
import '../models/question.dart';
import '../services/auth_service.dart';
import '../services/family_member_service.dart';
import '../services/family_story_storage.dart';
import '../services/invitation_service.dart';
import '../services/invitation_share_service.dart';
import '../services/question_request_service.dart';
import '../services/audio_answer_service.dart';
import '../services/story_photo_service.dart';
import '../services/profile_image_picker.dart';
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
    required this.questionRequestService,
    required this.isRemoteFamilyMember,
    this.audioService,
    this.photoService,
    this.imagePicker,
    super.key,
  });

  final FamilyMember familyMember;
  final Question question;
  final FamilyStoryStorage familyStoryStorage;
  final AuthService authService;
  final InvitationService invitationService;
  final InvitationShareService invitationShareService;
  final FamilyMemberService familyMemberService;
  final QuestionRequestService questionRequestService;
  final bool isRemoteFamilyMember;
  final AudioAnswerService? audioService;
  final StoryPhotoService? photoService;
  final ProfileImagePicker? imagePicker;

  @override
  State<AnswerOptionsScreen> createState() => _AnswerOptionsScreenState();
}

class _AnswerOptionsScreenState extends State<AnswerOptionsScreen> {
  bool _isCreatingInvitation = false;
  bool _isRefreshingFamilyMember = false;
  bool _isSendingQuestion = false;
  bool _openingRecorder = false;

  Future<void> _answerNow(BuildContext context) async {
    if (_openingRecorder) return;
    setState(() => _openingRecorder = true);
    try {
      final storySaved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => QuestionScreen(
            familyMember: widget.familyMember,
            question: widget.question,
            familyStoryStorage: widget.familyStoryStorage,
            audioService: widget.audioService,
            photoService: widget.photoService,
            imagePicker: widget.imagePicker,
          ),
        ),
      );
      if (storySaved == true && context.mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _openingRecorder = false);
    }
  }

  Future<void> _showSendInformation() async {
    if (_isCreatingInvitation ||
        _isRefreshingFamilyMember ||
        _isSendingQuestion) {
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
      await _sendQuestion(familyMember);
      return;
    }

    if (!widget.isRemoteFamilyMember || user == null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _sendDialog(
          scrollable: true,
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
      builder: (dialogContext) => _sendDialog(
        scrollable: true,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        title: Text('Enviar a ${familyMember.name}'),
        content: Text(
          'Para enviar preguntas a ${familyMember.name}, primero tendrás que invitarle a Family Stories.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
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

  Widget _sendDialog({
    required bool scrollable,
    required Widget icon,
    required Widget title,
    required Widget content,
    required List<Widget> actions,
  }) => Theme(
    data: AritoriaDesign.theme(),
    child: AlertDialog(
      scrollable: scrollable,
      backgroundColor: AritoriaColors.cream,
      surfaceTintColor: Colors.transparent,
      iconColor: AritoriaColors.olive,
      titleTextStyle: AritoriaType.section.copyWith(
        color: AritoriaColors.olive,
      ),
      contentTextStyle: AritoriaType.body.copyWith(color: AritoriaColors.muted),
      icon: icon,
      title: title,
      content: content,
      actions: actions,
    ),
  );

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

  Future<void> _sendQuestion(FamilyMember familyMember) async {
    if (_isSendingQuestion) {
      return;
    }

    setState(() => _isSendingQuestion = true);
    try {
      await widget.questionRequestService.sendQuestion(
        familyMemberId: familyMember.id,
        questionText: widget.question.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pregunta enviada a ${familyMember.name}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo enviar la pregunta. Inténtalo de nuevo.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingQuestion = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sending =
        _isCreatingInvitation ||
        _isRefreshingFamilyMember ||
        _isSendingQuestion;
    return Theme(
      data: AritoriaDesign.theme(),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          foregroundColor: AritoriaColors.olive,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 64,
              child: IgnorePointer(
                child: CustomPaint(painter: AritoriaFooterWave()),
              ),
            ),
            SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AritoriaSpace.maxWidth,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                    children: [
                      Text(
                        'Elige cómo responder',
                        textAlign: TextAlign.start,
                        style: AritoriaType.brand.copyWith(fontSize: 30),
                      ),
                      const SizedBox(height: 44),
                      QuestionText(
                        widget.question.text,
                        style: AritoriaType.section.copyWith(
                          fontSize: 26,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 40),
                      _AnswerOption(
                        icon: Icons.mic_none_rounded,
                        title: 'Responder ahora',
                        subtitle: 'Graba la respuesta en este dispositivo',
                        onTap: _openingRecorder
                            ? null
                            : () => _answerNow(context),
                      ),
                      const SizedBox(height: 18),
                      _AnswerOption(
                        icon: Icons.send_outlined,
                        title: 'Enviar a ${widget.familyMember.name}',
                        subtitle: _isCreatingInvitation
                            ? 'Creando invitación...'
                            : _isSendingQuestion
                            ? 'Enviando pregunta...'
                            : _isRefreshingFamilyMember
                            ? 'Actualizando familiar...'
                            : 'Para que responda desde su dispositivo',
                        onTap: sending ? null : _showSendInformation,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerOption extends StatelessWidget {
  const _AnswerOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AritoriaColors.sand.withValues(alpha: 0.18),
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(width: 2),
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AritoriaColors.softOlive,
              ),
              child: Icon(icon, color: AritoriaColors.olive, size: 28),
            ),
            const SizedBox(width: 12),
            Container(width: 1, height: 64, color: AritoriaColors.sand),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AritoriaType.section.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: AritoriaType.body.copyWith(
                      fontSize: 15,
                      height: 1.4,
                      color: AritoriaColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AritoriaColors.moss,
              size: 25,
            ),
          ],
        ),
      ),
    ),
  );
}
