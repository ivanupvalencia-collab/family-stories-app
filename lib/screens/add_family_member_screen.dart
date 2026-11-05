import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';
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
    if (_pickingPhoto) return;
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
    final theme = AritoriaDesign.theme();
    final labelStyle = AritoriaType.body.copyWith(fontWeight: FontWeight.w700);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: AritoriaColors.taupe.withValues(alpha: 0.65),
      ),
    );
    final inputDecoration = InputDecoration(
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AritoriaColors.olive, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: AritoriaType.body.copyWith(color: AritoriaColors.muted),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          foregroundColor: AritoriaColors.olive,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 64,
              child: IgnorePointer(
                child: CustomPaint(painter: _AddMemberWave()),
              ),
            ),
            SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 48),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AritoriaSpace.maxWidth,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Añadir ser querido',
                              textAlign: TextAlign.center,
                              style: AritoriaType.brand.copyWith(
                                fontSize: constraints.maxWidth < 340 ? 28 : 32,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Crea su perfil para guardar sus historias',
                              textAlign: TextAlign.center,
                              style: AritoriaType.body.copyWith(
                                fontSize: 15,
                                color: AritoriaColors.muted,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Center(
                              child: SizedBox.square(
                                dimension: 144,
                                child: Stack(
                                  children: [
                                    Material(
                                      color: AritoriaColors.softOlive,
                                      shape: const CircleBorder(),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        key: const ValueKey(
                                          'pick_family_member_photo',
                                        ),
                                        onTap: _pickingPhoto
                                            ? null
                                            : _pickPhoto,
                                        customBorder: const CircleBorder(),
                                        child: Semantics(
                                          label: 'Seleccionar foto (opcional)',
                                          button: true,
                                          child: FamilyMemberPhotoView(
                                            member: FamilyMember(
                                              id: 'draft',
                                              name: _nameController.text,
                                              relationship: _relationship ?? '',
                                            ),
                                            radius: 72,
                                            photoService: widget.photoService,
                                            previewBytes: _photo?.bytes,
                                            fallback: const Center(
                                              child: Icon(
                                                Icons.person_outline_rounded,
                                                size: 72,
                                                color: AritoriaColors.olive,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 4,
                                      bottom: 8,
                                      child: IconButton.filled(
                                        key: const ValueKey(
                                          'pick_family_member_photo_add',
                                        ),
                                        tooltip: 'Seleccionar foto',
                                        onPressed: _pickingPhoto
                                            ? null
                                            : _pickPhoto,
                                        style: IconButton.styleFrom(
                                          backgroundColor: AritoriaColors.olive,
                                          foregroundColor:
                                              AritoriaColors.onPhoto,
                                          minimumSize: const Size.square(40),
                                          side: const BorderSide(
                                            color: AritoriaColors.cream,
                                            width: 2,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.add_rounded,
                                          size: 27,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_photo != null)
                              TextButton(
                                onPressed: _pickingPhoto
                                    ? null
                                    : () => setState(() => _photo = null),
                                child: const Text('Quitar foto seleccionada'),
                              ),
                            const SizedBox(height: 24),
                            ExcludeSemantics(
                              child: Text('Nombre', style: labelStyle),
                            ),
                            const SizedBox(height: 8),
                            Semantics(
                              label: 'Nombre',
                              child: TextFormField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                style: AritoriaType.body,
                                decoration: inputDecoration.copyWith(
                                  hintText: 'Ej. Abuela Carmen',
                                  prefixIcon: const Icon(
                                    Icons.person_outline_rounded,
                                    color: AritoriaColors.olive,
                                    size: 23,
                                  ),
                                ),
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Introduce un nombre';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 24),
                            ExcludeSemantics(
                              child: Text(
                                'Relación contigo',
                                style: labelStyle,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Semantics(
                              label: 'Relación contigo',
                              child: DropdownButtonFormField<String>(
                                initialValue: _relationship,
                                isExpanded: true,
                                menuMaxHeight: 320,
                                dropdownColor: AritoriaColors.cream,
                                style: AritoriaType.body,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: AritoriaColors.muted,
                                ),
                                decoration: inputDecoration,
                                hint: const Text(
                                  'Selecciona una relación',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                items: _relationships
                                    .map(
                                      (relationship) => DropdownMenuItem(
                                        value: relationship,
                                        child: Text(relationship),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) =>
                                    setState(() => _relationship = value),
                                validator: (value) {
                                  if (value == null) {
                                    return 'Selecciona una relación';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 56),
                            FilledButton(
                              onPressed: _pickingPhoto
                                  ? null
                                  : _saveFamilyMember,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: const StadiumBorder(),
                                textStyle: AritoriaType.body.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('Guardar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMemberWave extends CustomPainter {
  const _AddMemberWave();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.35)
      ..cubicTo(
        size.width * 0.25,
        -size.height * 0.55,
        size.width * 0.42,
        size.height * 1.1,
        size.width * 0.65,
        size.height * 0.6,
      )
      ..cubicTo(
        size.width * 0.82,
        size.height * 0.1,
        size.width * 0.87,
        0,
        size.width,
        size.height * 0.25,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = AritoriaColors.sand.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_AddMemberWave oldDelegate) => false;
}
