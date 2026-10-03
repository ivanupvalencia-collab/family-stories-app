import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../services/auth_service.dart';
import '../services/family_member_storage.dart';
import '../services/family_story_storage.dart';
import '../services/profile_service.dart';
import 'add_family_member_screen.dart';
import 'family_member_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    this.authService,
    this.profileService,
    this.familyMemberStorage,
    this.familyStoryStorage,
    super.key,
  });

  final AuthService? authService;
  final ProfileService? profileService;
  final FamilyMemberStorage? familyMemberStorage;
  final FamilyStoryStorage? familyStoryStorage;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final FamilyMemberStorage _familyMemberStorage;
  final List<FamilyMember> _familyMembers = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _familyMemberStorage =
        widget.familyMemberStorage ?? SharedPreferencesFamilyMemberStorage();
    _loadFamilyMembers();
  }

  Future<void> _loadFamilyMembers() async {
    try {
      final familyMembers = await _familyMemberStorage.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _familyMembers.addAll(familyMembers);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      _showMessage('No se pudieron cargar los familiares guardados.');
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

    setState(() => _isSaving = true);
    try {
      await _familyMemberStorage.save([..._familyMembers, familyMember]);
      if (!mounted) {
        return;
      }
      setState(() {
        _familyMembers.add(familyMember);
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

  void _openFamilyMember(FamilyMember familyMember) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FamilyMemberScreen(
          familyMember: familyMember,
          familyStoryStorage: widget.familyStoryStorage,
        ),
      ),
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileScreen(
          authService: widget.authService,
          profileService: widget.profileService,
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
