import 'package:flutter/material.dart';

import '../models/family_member.dart';

class AddFamilyMemberScreen extends StatefulWidget {
  const AddFamilyMemberScreen({super.key});

  @override
  State<AddFamilyMemberScreen> createState() => _AddFamilyMemberScreenState();
}

class _AddFamilyMemberScreenState extends State<AddFamilyMemberScreen> {
  static const _relationships = [
    'Abuelo/a',
    'Padre/Madre',
    'Hermano/a',
    'Pareja',
    'Hijo/a',
    'Otro',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _relationship;

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
      FamilyMember.create(
        name: _nameController.text.trim(),
        relationship: _relationship!,
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
                    FilledButton(
                      onPressed: _saveFamilyMember,
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
