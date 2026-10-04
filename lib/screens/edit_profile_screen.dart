import 'package:flutter/material.dart';

import '../models/profile_avatar.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../widgets/profile_avatar_view.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    required this.userId,
    required this.profile,
    required this.profileService,
    super.key,
  });

  final String userId;
  final UserProfile profile;
  final ProfileService profileService;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String? _selectedAvatarKey;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _selectedAvatarKey = widget.profile.avatarKey;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final profile = await widget.profileService.updateProfile(
        userId: widget.userId,
        name: _nameController.text.trim(),
        avatarKey: _selectedAvatarKey,
      );
      if (mounted) {
        Navigator.of(context).pop(profile);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo guardar el nombre. Inténtalo de nuevo.',
              ),
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isSaving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Introduce un nombre';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) {
                        if (!_isSaving) {
                          _save();
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Avatar',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 4,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (final avatar in ProfileAvatarCatalog.avatars)
                          _AvatarOption(
                            avatar: avatar,
                            selected: avatar.key == _selectedAvatarKey,
                            enabled: !_isSaving,
                            onSelected: () {
                              setState(() {
                                _selectedAvatarKey = avatar.key;
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: Text(_isSaving ? 'Guardando...' : 'Guardar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarOption extends StatelessWidget {
  const _AvatarOption({
    required this.avatar,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final ProfileAvatar avatar;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Seleccionar ${avatar.key}',
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('avatar_option_${avatar.key}'),
        onTap: enabled ? onSelected : null,
        customBorder: const CircleBorder(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: selected ? 4 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: ProfileAvatarView(avatarKey: avatar.key),
              ),
            ),
            if (selected)
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  key: ValueKey('selected_avatar_${avatar.key}'),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.surface, width: 2),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.check,
                    size: 16,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
