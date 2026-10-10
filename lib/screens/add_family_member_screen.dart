import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/family_relationships.dart';
import '../services/profile_image_picker.dart';
import '../services/family_member_photo_service.dart';
import '../widgets/family_member_photo_view.dart';

class FamilyMemberDraft {
  const FamilyMemberDraft({required this.member, this.photo});
  final FamilyMember member;
  final PickedProfileImage? photo;
}

class AddFamilyMemberScreen extends StatefulWidget {
  const AddFamilyMemberScreen({
    required this.imagePicker,
    required this.photoService,
    super.key,
  });

  final ProfileImagePicker imagePicker;
  final FamilyMemberPhotoService photoService;

  @override
  State<AddFamilyMemberScreen> createState() => _AddFamilyMemberScreenState();
}

class _AddFamilyMemberScreenState extends State<AddFamilyMemberScreen> {
  static const _relationships = familyRelationships;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _relationship;
  PickedProfileImage? _photo;
  bool _pickingPhoto = false;

  Future<void> _pickPhoto() async {
    setState(() => _pickingPhoto = true);
    try {
      final photo = await widget.imagePicker.pickFromGallery();
      if (photo != null && mounted) setState(() => _photo = photo);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo elegir la foto.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveFamilyMember() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      FamilyMemberDraft(
        member: FamilyMember.create(
          name: _nameController.text.trim(),
          relationship: _relationship!,
        ),
        photo: _photo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Añadir familiar')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Introduce un nombre';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: _relationship,
                      decoration: const InputDecoration(
                        labelText: 'Relación contigo',
                        border: OutlineInputBorder(),
                      ),
                      items: _relationships
                          .map(
                            (relationship) => DropdownMenuItem(
                              value: relationship,
                              child: Text(relationship),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _relationship = value;
                        });
                      },
                      validator: (value) {
                        if (value == null) {
                          return 'Selecciona una relación';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    FamilyMemberPhotoView(
                      member: FamilyMember(
                        id: 'draft',
                        name: _nameController.text,
                        relationship: _relationship ?? '',
                      ),
                      photoService: widget.photoService,
                      previewBytes: _photo?.bytes,
                    ),
                    TextButton.icon(
                      key: const ValueKey('pick_family_member_photo'),
                      onPressed: _pickingPhoto ? null : _pickPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Elegir foto (opcional)'),
                    ),
                    if (_photo != null)
                      TextButton(
                        onPressed: _pickingPhoto
                            ? null
                            : () => setState(() => _photo = null),
                        child: const Text('Quitar foto seleccionada'),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _pickingPhoto ? null : _saveFamilyMember,
                      child: const Text('Guardar'),
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
