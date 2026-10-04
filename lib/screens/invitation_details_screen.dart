import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/family_invitation.dart';
import '../services/invitation_link.dart';
import '../services/invitation_share_service.dart';

class InvitationDetailsScreen extends StatefulWidget {
  const InvitationDetailsScreen({
    required this.familyMemberName,
    required this.invitation,
    required this.shareService,
    super.key,
  });

  final String familyMemberName;
  final FamilyInvitation invitation;
  final InvitationShareService shareService;

  @override
  State<InvitationDetailsScreen> createState() =>
      _InvitationDetailsScreenState();
}

class _InvitationDetailsScreenState extends State<InvitationDetailsScreen> {
  bool _isCopying = false;
  bool _isSharing = false;

  String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    return '$day/$month/${localDate.year}';
  }

  Future<void> _copyText(String text, String successMessage) async {
    if (_isCopying) {
      return;
    }
    setState(() => _isCopying = true);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo copiar el código.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCopying = false);
      }
    }
  }

  Future<void> _shareInvitation() async {
    if (_isSharing) {
      return;
    }
    setState(() => _isSharing = true);
    try {
      await widget.shareService.shareInvitation(widget.invitation.token);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo compartir la invitación.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Invitación creada')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Invitación para ${widget.familyMemberName}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Caduca el ${_formatDate(widget.invitation.expiresAt)}.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Código de invitación',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          widget.invitation.token,
                          key: const ValueKey('invitation_token'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _isCopying || _isSharing
                      ? null
                      : () => _copyText(
                          InvitationLink.build(widget.invitation.token)
                              .toString(),
                          'Enlace copiado.',
                        ),
                  icon: const Icon(Icons.link_outlined),
                  label: Text(_isCopying ? 'Copiando...' : 'Copiar enlace'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isCopying || _isSharing ? null : _shareInvitation,
                  icon: const Icon(Icons.share_outlined),
                  label: Text(
                    _isSharing ? 'Compartiendo...' : 'Compartir invitación',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _isCopying || _isSharing
                      ? null
                      : () => _copyText(
                          widget.invitation.token,
                          'Código copiado.',
                        ),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copiar código'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
