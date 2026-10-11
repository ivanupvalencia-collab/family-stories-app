import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/family_relationships.dart';
import '../services/family_member_photo_service.dart';
import '../widgets/family_member_photo_view.dart';
import '../design/aritoria_design.dart';

class EditFamilyMemberScreen extends StatefulWidget {
  const EditFamilyMemberScreen({
    required this.member,
    this.photos,
    this.onManagePhoto,
    super.key,
  });
  final FamilyMember member;
  final FamilyMemberPhotoService? photos;
  final Future<FamilyMember?> Function(bool remove)? onManagePhoto;
  @override
  State<EditFamilyMemberScreen> createState() => _EditFamilyMemberScreenState();
}

class _EditFamilyMemberScreenState extends State<EditFamilyMemberScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.member.name,
  );
  late String _relationship = widget.member.relationship;
  late FamilyMember _member = widget.member;
  bool _photoBusy = false;

  Future<void> _managePhoto(bool remove) async {
    if (_photoBusy || widget.onManagePhoto == null) return;
    setState(() => _photoBusy = true);
    try {
      final updated = await widget.onManagePhoto!(remove);
      if (mounted && updated != null) setState(() => _member = updated);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Editar información')),
    body: PopScope(
      canPop: !_photoBusy,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.photos != null && widget.onManagePhoto != null) ...[
            Center(
              child: FamilyMemberPhotoView(
                member: _member,
                photoService: widget.photos!,
                radius: 48,
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text('Foto del ser querido', style: AritoriaType.caption),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _photoBusy ? null : () => _managePhoto(false),
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('Cambiar foto'),
                ),
                if (_member.photoPath != null)
                  TextButton.icon(
                    onPressed: _photoBusy ? null : () => _managePhoto(true),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar foto'),
                  ),
              ],
            ),
            if (_photoBusy) const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 24),
          ],
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_photoBusy,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Escribe un nombre'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _relationship,
                  decoration: const InputDecoration(labelText: 'Relación'),
                  items: {...familyRelationships, widget.member.relationship}
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: _photoBusy
                      ? null
                      : (v) {
                          if (v != null) setState(() => _relationship = v);
                        },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _photoBusy
                      ? null
                      : () {
                          if (_form.currentState!.validate()) {
                            Navigator.pop(
                              context,
                              FamilyMember(
                                id: widget.member.id,
                                name: _name.text.trim(),
                                relationship: _relationship,
                                linkedAccountId: widget.member.linkedAccountId,
                                photoPath: _member.photoPath,
                              ),
                            );
                          }
                        },
                  child: const Text('Guardar cambios'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
