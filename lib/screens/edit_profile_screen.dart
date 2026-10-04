import 'package:flutter/material.dart';

import '../models/profile_avatar.dart';
import '../models/user_profile.dart';
import '../services/avatar_storage_service.dart';
import '../services/profile_image_picker.dart';
import '../services/profile_service.dart';
import '../widgets/profile_avatar_view.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    required this.userId,
    required this.profile,
    required this.profileService,
    required this.profileImagePicker,
    required this.avatarStorageService,
    super.key,
  });

  final String userId;
  final UserProfile profile;
  final ProfileService profileService;
  final ProfileImagePicker profileImagePicker;
  final AvatarStorageService avatarStorageService;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String? _selectedAvatarKey;
  String? _avatarUrl;
  PickedProfileImage? _selectedPhoto;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _selectedAvatarKey = widget.profile.avatarKey;
    _avatarUrl = widget.profile.avatarUrl;
  }

  Future<void> _pickPhoto() async {
    try {
      final photo = await widget.profileImagePicker.pickFromGallery();
      if (photo == null || !mounted) {
        return;
      }

      setState(() {
        _selectedPhoto = photo;
        _selectedAvatarKey = null;
        _avatarUrl = null;
      });
    } catch (_) {
      if (mounted) {
        _showMessage('No se pudo elegir la foto. Inténtalo de nuevo.');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
      var avatarUrl = _avatarUrl;
      final selectedPhoto = _selectedPhoto;
      if (selectedPhoto != null) {
        avatarUrl = await widget.avatarStorageService.uploadAvatar(
          userId: widget.userId,
          image: selectedPhoto,
        );
      }

      final profile = await widget.profileService.updateProfile(
        userId: widget.userId,
        name: _nameController.text.trim(),
        avatarKey: _selectedAvatarKey,
        avatarUrl: avatarUrl,
      );
      if (mounted) {
        Navigator.of(context).pop(profile);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('No se pudo guardar el perfil. Inténtalo de nuevo.');
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
                    _AvatarPreview(
                      photo: _selectedPhoto,
                      avatarKey: _selectedAvatarKey,
                      avatarUrl: _avatarUrl,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      key: const ValueKey('pick_profile_photo'),
                      onPressed: _isSaving ? null : _pickPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Elegir foto de la galería'),
                    ),
                    const SizedBox(height: 20),
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
                                _selectedPhoto = null;
                                _avatarUrl = null;
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

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.photo,
    required this.avatarKey,
    required this.avatarUrl,
  });

  final PickedProfileImage? photo;
  final String? avatarKey;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final selectedPhoto = photo;
    if (selectedPhoto == null) {
      return ProfileAvatarView(
        key: const ValueKey('edit_profile_avatar_preview'),
        avatarKey: avatarKey,
        avatarUrl: avatarUrl,
        radius: 44,
      );
    }

    return Center(
      child: SizedBox.square(
        dimension: 88,
        child: ClipOval(
          child: Image.memory(
            selectedPhoto.bytes,
            key: const ValueKey('selected_profile_photo_preview'),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const ProfileAvatarView(radius: 44),
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
