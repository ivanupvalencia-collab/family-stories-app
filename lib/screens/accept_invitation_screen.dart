import 'package:flutter/material.dart';

import '../models/family_invitation.dart';
import '../services/invitation_service.dart';

class AcceptInvitationScreen extends StatefulWidget {
  const AcceptInvitationScreen({
    required this.invitationService,
    this.initialToken,
    super.key,
  });

  final InvitationService invitationService;
  final String? initialToken;

  @override
  State<AcceptInvitationScreen> createState() => _AcceptInvitationScreenState();
}

class _AcceptInvitationScreenState extends State<AcceptInvitationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tokenController;
  InvitationPreview? _preview;
  String? _verifiedToken;
  String? _errorMessage;
  bool _isChecking = false;
  bool _isAccepting = false;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initialToken);
    if (widget.initialToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkToken();
        }
      });
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    return '$day/$month/${localDate.year}';
  }

  Future<void> _checkToken() async {
    if (!_formKey.currentState!.validate() || _isChecking) {
      return;
    }

    final token = _tokenController.text.trim();
    setState(() {
      _isChecking = true;
      _errorMessage = null;
      _preview = null;
      _verifiedToken = null;
    });

    try {
      final preview = await widget.invitationService.getInvitationPreview(
        token,
      );
      if (!mounted) {
        return;
      }
      if (preview == null) {
        setState(() {
          _errorMessage = 'El código no es válido o ya no está disponible.';
        });
      } else {
        setState(() {
          _preview = preview;
          _verifiedToken = token;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No se pudo comprobar el código. Inténtalo de nuevo.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _acceptInvitation() async {
    final token = _verifiedToken;
    if (token == null || _isAccepting) {
      return;
    }

    setState(() {
      _isAccepting = true;
      _errorMessage = null;
    });
    try {
      final accepted = await widget.invitationService.acceptInvitation(token);
      if (!mounted) {
        return;
      }
      if (accepted) {
        setState(() => _accepted = true);
      } else {
        setState(() {
          _preview = null;
          _verifiedToken = null;
          _errorMessage = 'La invitación ya no es válida o no está disponible.';
        });
      }
    } on CannotAcceptOwnInvitationException {
      if (mounted) {
        setState(() {
          _errorMessage =
              'No puedes aceptar una invitación creada por ti mismo.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'No se pudo aceptar la invitación. Inténtalo de nuevo.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isAccepting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Código de invitación')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _accepted
                ? _InvitationAccepted(onClose: () => Navigator.pop(context))
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Form(
                        key: _formKey,
                        child: TextFormField(
                          controller: _tokenController,
                          enabled: !_isChecking && !_isAccepting,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Código de invitación',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Introduce el código de invitación';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _checkToken(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _isChecking || _isAccepting
                            ? null
                            : _checkToken,
                        child: Text(
                          _isChecking ? 'Comprobando...' : 'Comprobar código',
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          key: const ValueKey('invitation_error'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      if (_preview case final preview?) ...[
                        const SizedBox(height: 28),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${preview.inviterName} te invita a conectarte como ${preview.familyMemberName}.',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Caduca el ${_formatDate(preview.expiresAt)}.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: _isAccepting
                                          ? null
                                          : () => Navigator.pop(context),
                                      child: const Text('Cancelar'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: _isAccepting
                                          ? null
                                          : _acceptInvitation,
                                      child: Text(
                                        _isAccepting
                                            ? 'Aceptando...'
                                            : 'Aceptar',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _InvitationAccepted extends StatelessWidget {
  const _InvitationAccepted({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            'Invitación aceptada',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Ya estás conectado con este familiar.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          FilledButton(onPressed: onClose, child: const Text('Volver')),
        ],
      ),
    );
  }
}
