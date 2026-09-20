import 'package:flutter/material.dart';

import '../models/family_member.dart';
import 'add_family_member_screen.dart';
import 'family_member_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<FamilyMember> _familyMembers = [];

  Future<void> _addFamilyMember() async {
    final familyMember = await Navigator.of(context).push<FamilyMember>(
      MaterialPageRoute(builder: (context) => const AddFamilyMemberScreen()),
    );

    if (familyMember == null || !mounted) {
      return;
    }

    setState(() {
      _familyMembers.add(familyMember);
    });
  }

  void _openFamilyMember(FamilyMember familyMember) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FamilyMemberScreen(familyMember: familyMember),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
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
                    onPressed: _addFamilyMember,
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
                    child: _familyMembers.isEmpty
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
