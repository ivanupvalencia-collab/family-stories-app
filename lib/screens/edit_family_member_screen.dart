import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../models/family_relationships.dart';

class EditFamilyMemberScreen extends StatefulWidget {
  const EditFamilyMemberScreen({required this.member, super.key});
  final FamilyMember member;
  @override
  State<EditFamilyMemberScreen> createState() => _EditFamilyMemberScreenState();
}

class _EditFamilyMemberScreenState extends State<EditFamilyMemberScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.member.name,
  );
  late String _relationship = widget.member.relationship;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Editar información')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Escribe un nombre' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _relationship,
                decoration: const InputDecoration(labelText: 'Relación'),
                items: {...familyRelationships, widget.member.relationship}
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _relationship = v);
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.pop(
                      context,
                      FamilyMember(
                        id: widget.member.id,
                        name: _name.text.trim(),
                        relationship: _relationship,
                        linkedAccountId: widget.member.linkedAccountId,
                        photoPath: widget.member.photoPath,
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
  );
}
