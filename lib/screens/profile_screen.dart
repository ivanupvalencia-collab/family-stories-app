import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({this.authService, super.key});

  final AuthService? authService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthService _authService;
  late final StreamSubscription<AuthUser?> _authSubscription;
  AuthUser? _user;
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? SupabaseGoogleAuthService();
    _user = _authService.currentUser;
    _authSubscription = _authService.authStateChanges.listen((user) {
      if (mounted) {
        setState(() => _user = user);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isWorking = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (mounted) {
        setState(() => _user = user);
      }
    } on GoogleSignInCancelledException {
      if (mounted) {
        _showMessage('Inicio de sesión cancelado.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('No se pudo iniciar sesión. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  Future<void> _signOut() async {
    setState(() => _isWorking = true);
    try {
      await _authService.signOut();
      if (mounted) {
        setState(() => _user = null);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('No se pudo cerrar sesión. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  Widget _buildAvatar(ThemeData theme, AuthUser? user) {
    final photoUrl = user?.photoUrl;

    return CircleAvatar(
      radius: 44,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
      onForegroundImageError: photoUrl == null ? null : (_, _) {},
      child: Icon(
        user == null ? Icons.person_outline : Icons.person,
        size: 48,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAvatar(theme, user),
                  const SizedBox(height: 24),
                  Text(
                    user?.name ??
                        (user == null
                            ? 'Aún no has iniciado sesión'
                            : 'Usuario'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.email ?? 'Inicia sesión para guardar tus historias y acceder a ellas desde otros dispositivos.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (user == null)
                    OutlinedButton.icon(
                      onPressed: _isWorking ? null : _signInWithGoogle,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: Text(
                        _isWorking
                            ? 'Iniciando sesión...'
                            : 'Continuar con Google',
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _isWorking ? null : _signOut,
                      icon: const Icon(Icons.logout),
                      label: Text(
                        _isWorking ? 'Cerrando sesión...' : 'Cerrar sesión',
                      ),
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
