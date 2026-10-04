import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/avatar_storage_service.dart';
import '../services/invitation_service.dart';
import '../services/profile_image_picker.dart';
import '../services/profile_service.dart';
import '../widgets/profile_avatar_view.dart';
import 'accept_invitation_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    this.authService,
    this.profileService,
    this.profileImagePicker,
    this.avatarStorageService,
    this.invitationService,
    super.key,
  });

  final AuthService? authService;
  final ProfileService? profileService;
  final ProfileImagePicker? profileImagePicker;
  final AvatarStorageService? avatarStorageService;
  final InvitationService? invitationService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthService _authService;
  late final ProfileService _profileService;
  late final InvitationService _invitationService;
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
    _invitationService =
        widget.invitationService ?? SupabaseInvitationService();
    _user = _authService.currentUser;
    final user = _user;
    _profile = user == null ? null : _profileService.cachedForUser(user.id);
    _isProfileLoading = user != null && _profile == null;
    _authSubscription = _authService.authStateChanges.listen(_applyAuthUser);

    if (user != null) {
      unawaited(
        _loadProfile(
          user.id,
          showLoading: false,
          forceRefresh: _profile != null,
        ),
      );
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
    final cachedProfile = user == null
        ? null
        : _profileService.cachedForUser(user.id);
    setState(() {
      _user = user;
      if (user == null || userChanged) {
        _profile = cachedProfile;
        _profileLoadFailed = false;
        _isProfileLoading = user != null && cachedProfile == null;
      }
    });

    if (user != null && userChanged) {
      unawaited(
        _loadProfile(
          user.id,
          showLoading: false,
          forceRefresh: cachedProfile != null,
        ),
      );
    }
  }

  Future<void> _loadProfile(
    String userId, {
    bool showLoading = true,
    bool forceRefresh = false,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        _isProfileLoading = true;
        _profileLoadFailed = false;
      });
    }

    try {
      final profile = await _profileService.loadForUser(
        userId,
        forceRefresh: forceRefresh,
      );
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
      _profileService.clearCache();
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

  Future<void> _editProfile() async {
    final user = _user;
    final profile = _profile;
    if (user == null || profile == null) {
      return;
    }

    final updatedProfile = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(
          userId: user.id,
          profile: profile,
          profileService: _profileService,
          profileImagePicker:
              widget.profileImagePicker ?? DeviceProfileImagePicker(),
          avatarStorageService:
              widget.avatarStorageService ?? SupabaseAvatarStorageService(),
        ),
      ),
    );

    if (updatedProfile != null && mounted && _user?.id == user.id) {
      setState(() => _profile = updatedProfile);
    }
  }

  Future<void> _openInvitationCode() async {
    if (_user == null) {
      _showMessage('Necesitas iniciar sesión para aceptar una invitación.');
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            AcceptInvitationScreen(invitationService: _invitationService),
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
                  ProfileAvatarView(
                    key: const ValueKey('profile_avatar'),
                    avatarKey: profile?.avatarKey,
                    avatarUrl: profile?.avatarUrl,
                  ),
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
                      onPressed: () =>
                          _loadProfile(user.id, forceRefresh: true),
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
                  else ...[
                    if (profile != null) ...[
                      FilledButton.icon(
                        onPressed: _isWorking ? null : _editProfile,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar perfil'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _isWorking ? null : _signOut,
                      icon: const Icon(Icons.logout),
                      label: Text(
                        _isWorking ? 'Cerrando sesión...' : 'Cerrar sesión',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _isWorking ? null : _openInvitationCode,
                    icon: const Icon(Icons.password_outlined),
                    label: const Text('Introducir código de invitación'),
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
