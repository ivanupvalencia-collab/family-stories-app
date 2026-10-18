import 'dart:async';

import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/avatar_storage_service.dart';
import '../services/invitation_service.dart';
import '../services/profile_image_picker.dart';
import '../services/profile_service.dart';
import '../services/profile_avatar_image_cache.dart';
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
    final profileService = _profileService;
    if (userChanged &&
        _user != null &&
        profileService is ProfileAvatarImageSource) {
      (profileService as ProfileAvatarImageSource).avatarImages.clear();
    }
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
    final theme = AritoriaDesign.theme();
    final user = _user;
    final profile = _profile;
    final canEdit = user != null && profile != null && !_isWorking;
    final profileService = _profileService;
    final avatarImage =
        profile != null && profileService is ProfileAvatarImageSource
        ? (profileService as ProfileAvatarImageSource).avatarImages.imageFor(
            profile,
          )
        : null;

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 80,
          centerTitle: false,
          title: const Text('Perfil', style: AritoriaType.brand),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AritoriaSpace.maxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox.square(
                          dimension: 120,
                          child: Stack(
                            children: [
                              ProfileAvatarView(
                                key: const ValueKey('profile_avatar'),
                                avatarKey: profile?.avatarKey,
                                avatarUrl: profile?.avatarUrl,
                                imageProvider: avatarImage,
                                radius: 60,
                              ),
                              if (user != null && profile != null)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AritoriaColors.sage,
                                      border: Border.all(
                                        color: AritoriaColors.cream,
                                        width: 3,
                                      ),
                                    ),
                                    child: IconButton(
                                      tooltip: 'Editar foto de perfil',
                                      onPressed: canEdit ? _editProfile : null,
                                      color: AritoriaColors.onPhoto,
                                      icon: const Icon(
                                        Icons.camera_alt_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                          style: AritoriaType.section.copyWith(
                            fontSize: 28,
                            color: AritoriaColors.olive,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        user?.email ?? 'Inicia sesión para guardar tus historias y acceder a ellas desde otros dispositivos.',
                        textAlign: TextAlign.center,
                        style: AritoriaType.body.copyWith(
                          color: AritoriaColors.muted,
                        ),
                      ),
                      if (user != null && _profileLoadFailed) ...[
                        const SizedBox(height: 12),
                        Text(
                          'No se pudo cargar tu perfil.',
                          textAlign: TextAlign.center,
                          style: AritoriaType.body.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              _loadProfile(user.id, forceRefresh: true),
                          child: const Text('Reintentar'),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (user == null) ...[
                        OutlinedButton.icon(
                          onPressed: _isWorking ? null : _signInWithGoogle,
                          icon: const Icon(Icons.account_circle_outlined),
                          label: Text(
                            _isWorking
                                ? 'Iniciando sesión...'
                                : 'Continuar con Google',
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _ProfileSection(
                        title: 'Tu cuenta',
                        children: [
                          if (user != null && profile != null)
                            _ProfileOption(
                              icon: Icons.person_outline,
                              title: 'Editar perfil',
                              subtitle: 'Nombre y foto de tu cuenta',
                              onTap: canEdit ? _editProfile : null,
                            ),
                          _ProfileOption(
                            icon: Icons.group_outlined,
                            title: 'Introducir código de invitación',
                            subtitle: 'Acepta una invitación recibida',
                            onTap: _isWorking ? null : _openInvitationCode,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ProfileSection(
                        title: 'Ajustes',
                        children: [
                          _ProfileOption(
                            icon: Icons.notifications_none_rounded,
                            title: 'Notificaciones',
                            subtitle: 'Gestiona tus preferencias',
                            onTap: () => _showMessage('Próximamente'),
                          ),
                          _ProfileOption(
                            icon: Icons.lock_outline_rounded,
                            title: 'Privacidad',
                            subtitle: 'Controla tus datos',
                            onTap: () => _showMessage('Próximamente'),
                          ),
                          _ProfileOption(
                            icon: Icons.help_outline_rounded,
                            title: 'Ayuda y soporte',
                            subtitle: 'Preguntas frecuentes y contacto',
                            onTap: () => _showMessage('Próximamente'),
                          ),
                        ],
                      ),
                      if (user != null) ...[
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: _isWorking ? null : _signOut,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.35,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.logout_rounded, size: 21),
                          label: Text(
                            _isWorking ? 'Cerrando sesión...' : 'Cerrar sesión',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AritoriaColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AritoriaColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AritoriaType.section.copyWith(color: AritoriaColors.olive),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileOption extends StatelessWidget {
  const _ProfileOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AritoriaColors.sage.withValues(alpha: 0.13),
              ),
              child: Icon(icon, size: 23, color: AritoriaColors.olive),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AritoriaType.body),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AritoriaType.caption.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AritoriaColors.muted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
