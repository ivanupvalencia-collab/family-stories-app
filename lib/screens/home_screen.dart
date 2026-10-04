import 'dart:async';

import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../services/auth_service.dart';
import '../services/avatar_storage_service.dart';
import '../services/family_member_service.dart';
import '../services/family_member_storage.dart';
import '../services/family_story_storage.dart';
import '../services/invitation_service.dart';
import '../services/invitation_share_service.dart';
import '../services/profile_image_picker.dart';
import '../services/profile_service.dart';
import 'add_family_member_screen.dart';
import 'family_member_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    this.authService,
    this.profileService,
    this.profileImagePicker,
    this.avatarStorageService,
    this.familyMemberStorage,
    this.familyMemberService,
    this.familyStoryStorage,
    this.invitationService,
    this.invitationShareService,
    super.key,
  });

  final AuthService? authService;
  final ProfileService? profileService;
  final ProfileImagePicker? profileImagePicker;
  final AvatarStorageService? avatarStorageService;
  final FamilyMemberStorage? familyMemberStorage;
  final FamilyMemberService? familyMemberService;
  final FamilyStoryStorage? familyStoryStorage;
  final InvitationService? invitationService;
  final InvitationShareService? invitationShareService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AuthService _authService;
  late final FamilyMemberStorage _familyMemberStorage;
  late final FamilyMemberService _familyMemberService;
  late final InvitationService _invitationService;
  late final InvitationShareService _invitationShareService;
  late final ProfileService _profileService;
  late final StreamSubscription<AuthUser?> _authSubscription;
  final List<FamilyMember> _familyMembers = [];
  AuthUser? _user;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _loadFailed = false;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? SupabaseGoogleAuthService();
    _familyMemberStorage =
        widget.familyMemberStorage ?? SharedPreferencesFamilyMemberStorage();
    _familyMemberService =
        widget.familyMemberService ?? SupabaseFamilyMemberService();
    _invitationService =
        widget.invitationService ?? SupabaseInvitationService();
    _invitationShareService =
        widget.invitationShareService ?? PlatformInvitationShareService();
    _profileService = widget.profileService ?? SupabaseProfileService();
    _user = _authService.currentUser;
    _authSubscription = _authService.authStateChanges.listen(_applyAuthUser);
    _loadFamilyMembers();
    unawaited(_preloadProfile(_user));
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _applyAuthUser(AuthUser? user) {
    if (!mounted || _user?.id == user?.id) {
      return;
    }

    if (_user != null) {
      _profileService.clearCache();
    }
    setState(() {
      _user = user;
      _familyMembers.clear();
    });
    _loadFamilyMembers();
    unawaited(_preloadProfile(user));
  }

  Future<void> _preloadProfile(AuthUser? user) async {
    if (user == null) {
      return;
    }

    try {
      await _profileService.loadForUser(user.id);
    } catch (_) {
      // ProfileScreen keeps its own retryable error state when opened.
    }
  }

  Future<void> _loadFamilyMembers() async {
    final request = ++_loadRequest;
    final user = _user;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      final familyMembers = user == null
          ? await _familyMemberStorage.load()
          : await _familyMemberService.loadForOwner(user.id);
      if (!mounted || request != _loadRequest) {
        return;
      }
      setState(() {
        _familyMembers
          ..clear()
          ..addAll(familyMembers);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _loadRequest) {
        return;
      }
      setState(() {
        _familyMembers.clear();
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addFamilyMember() async {
    final familyMember = await Navigator.of(context).push<FamilyMember>(
      MaterialPageRoute(builder: (context) => const AddFamilyMemberScreen()),
    );

    if (familyMember == null || !mounted) {
      return;
    }

    final user = _user;
    setState(() => _isSaving = true);
    try {
      final savedMember = user == null
          ? await _saveLocalFamilyMember(familyMember)
          : await _familyMemberService.create(
              ownerId: user.id,
              name: familyMember.name,
              relationship: familyMember.relationship,
            );
      if (!mounted || _user?.id != user?.id) {
        return;
      }
      setState(() {
        _familyMembers.add(savedMember);
      });
    } catch (_) {
      if (mounted) {
        _showMessage('No se pudo guardar el familiar. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<FamilyMember> _saveLocalFamilyMember(FamilyMember familyMember) async {
    await _familyMemberStorage.save([..._familyMembers, familyMember]);
    return familyMember;
  }

  Future<void> _openFamilyMember(FamilyMember familyMember) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FamilyMemberScreen(
          familyMember: familyMember,
          authService: _authService,
          familyMemberService: _familyMemberService,
          invitationService: _invitationService,
          invitationShareService: _invitationShareService,
          isRemoteFamilyMember: _user != null,
          familyStoryStorage: widget.familyStoryStorage,
        ),
      ),
    );
    if (mounted && _user != null) {
      await _loadFamilyMembers();
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileScreen(
          authService: _authService,
          profileService: _profileService,
          profileImagePicker: widget.profileImagePicker,
          avatarStorageService: widget.avatarStorageService,
          invitationService: _invitationService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: _openProfile,
            tooltip: 'Perfil',
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    'Family Stories',
                    style: textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Conserva las historias de las personas que quieres.',
                    style: textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _isLoading || _isSaving
                        ? null
                        : _addFamilyMember,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Añadir familiar'),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'Tus familiares',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _loadFailed
                        ? _FamilyMembersLoadError(onRetry: _loadFamilyMembers)
                        : _familyMembers.isEmpty
                        ? Center(
                            child: Text(
                              'Todavía no has añadido ningún familiar.',
                              textAlign: TextAlign.center,
                              style: textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _familyMembers.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final familyMember = _familyMembers[index];

                              return Card(
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person_outline),
                                  ),
                                  title: Text(familyMember.name),
                                  subtitle: Text(familyMember.relationship),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _openFamilyMember(familyMember),
                                ),
                              );
                            },
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

class _FamilyMembersLoadError extends StatelessWidget {
  const _FamilyMembersLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No se pudieron cargar los familiares.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
