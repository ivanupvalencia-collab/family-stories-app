import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/family_member.dart';

abstract class FamilyMemberStorage {
  Future<List<FamilyMember>> load();
  Future<void> save(List<FamilyMember> familyMembers);
}

class SharedPreferencesFamilyMemberStorage implements FamilyMemberStorage {
  static const _storageKey = 'family_members';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<List<FamilyMember>> load() async {
    final storedMembers = await _preferences.getStringList(_storageKey) ?? [];

    var needsMigration = false;
    final familyMembers = storedMembers.map((member) {
      final json = jsonDecode(member) as Map<String, dynamic>;
      needsMigration |= json['id'] == null;
      return FamilyMember.fromJson(json);
    }).toList();

    if (needsMigration) {
      await save(familyMembers);
    }

    return familyMembers;
  }

  @override
  Future<void> save(List<FamilyMember> familyMembers) {
    final storedMembers = familyMembers
        .map((member) => jsonEncode(member.toJson()))
        .toList();

    return _preferences.setStringList(_storageKey, storedMembers);
  }
}
