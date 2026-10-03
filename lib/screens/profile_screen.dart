import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({this.authService, this.profileService, super.key});

  final AuthService? authService;
  final ProfileService? profileService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthService _authService;
  late final ProfileService _profileService;
  late final StreamSubscription<AuthUser?> _authSubscription;
  AuthUser? _user;
  UserProfile? _profile;
  bool _isWorking = false;
  bool _isProfileLoading = false;
  bool _profileLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? SupabaseGoogleAuthService();
    _profileService = widget.profileService ?? SupabaseProfileService();
    _user = _authService.currentUser;
    _isProfileLoading = _user != null;
    _authSubscription = _authService.authStateChanges.listen(_applyAuthUser);

    final user = _user;
    if (user != null) {
      unawaited(_loadProfile(user.id, showLoading: false));
    }
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

  void _applyAuthUser(AuthUser? user) {
    if (!mounted) {
      return;
    }

    final userChanged = _user?.id != user?.id;
    setState(() {
      _user = user;
      if (user == null || userChanged) {
        _profile = null;
        _profileLoadFailed = false;
        _isProfileLoading = user != null;
      }
    });

    if (user != null && userChanged) {
      unawaited(_loadProfile(user.id, showLoading: false));
    }
  }

  Future<void> _loadProfile(String userId, {bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isProfileLoading = true;
        _profileLoadFailed = false;
      });
    }

    try {
      final profile = await _profileService.loadForUser(userId);
      if (!mounted || _user?.id != userId) {
        return;
      }
      setState(() {
        _profile = profile;
        _isProfileLoading = false;
        _profileLoadFailed = false;
      });
    } catch (_) {
      if (!mounted || _user?.id != userId) {
        return;
      }
      setState(() {
        _profile = null;
        _isProfileLoading = false;
        _profileLoadFailed = true;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isWorking = true);
    try {
      final user = await _authService.signInWithGoogle();
      _applyAuthUser(user);
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
      _applyAuthUser(null);
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

  Widget _buildAvatar(ThemeData theme, UserProfile? profile) {
    final photoUrl = profile?.avatarUrl;

    return CircleAvatar(
      radius: 44,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
      onForegroundImageError: photoUrl == null ? null : (_, _) {},
      child: Icon(
        profile == null ? Icons.person_outline : Icons.person,
        size: 48,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;
    final profile = _profile;

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
                  _buildAvatar(theme, profile),
                  const SizedBox(height: 24),
                  if (user != null && _isProfileLoading)
                    const Center(
                      child: SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    )
                  else
                    Text(
                      user == null
                          ? 'Aún no has iniciado sesión'
                          : profile?.name ?? 'Usuario',
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
                  if (user != null && _profileLoadFailed) ...[
                    const SizedBox(height: 12),
                    Text(
                      'No se pudo cargar tu perfil.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _loadProfile(user.id),
                      child: const Text('Reintentar'),
                    ),
                  ],
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
