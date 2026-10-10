import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/family_member.dart';

// Separate from the guest's family_members key. Only server-confirmed records
// are written here; an empty list is a valid cached server result.
class RemoteFamilyMemberCache {
  RemoteFamilyMemberCache({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;
  Future<void> _writes = Future.value();
  int revision = 0;

  String _key(String backend, String owner) =>
      'remote_family_members_v1:${base64Url.encode(utf8.encode(backend))}:$owner';

  Future<List<FamilyMember>?> read(String backend, String owner) async {
    // Wait for earlier mutations, so opening another screen cannot revive an
    // older reference while its replacement is being persisted.
    await _writes;
    try {
      final value = await _preferences.getStringList(_key(backend, owner));
      if (value == null) return null;
      return value.map((v) {
        final json = jsonDecode(v) as Map<String, dynamic>;
        if (json['id'] is! String) throw const FormatException('Missing id');
        return FamilyMember.fromJson(json);
      }).toList();
    } catch (_) {
      return null; // Corrupt/unavailable cache must not prevent a server load.
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.catchError((Object _) {});
    return _writes;
  }

  Future<void> replace(
    String backend,
    String owner,
    List<FamilyMember> members,
  ) {
    revision++;
    final values = members.map((m) => jsonEncode(m.toJson())).toList();
    return _enqueue(() async {
      final key = _key(backend, owner);
      if (!listEquals(await _preferences.getStringList(key), values)) {
        await _preferences.setStringList(key, values);
      }
    });
  }

  Future<void> upsert(String backend, String owner, FamilyMember member) {
    revision++;
    return _enqueue(() async {
      final key = _key(backend, owner);
      final values = await _preferences.getStringList(key);
      // With no snapshot yet, keep the records legitimately obtained so far.
      // The next full server refresh fills in the rest of the owner's list.
      final members = (values ?? <String>[])
          .map((v) => FamilyMember.fromJson(jsonDecode(v)))
          .toList();
      final index = members.indexWhere((m) => m.id == member.id);
      if (index < 0) {
        members.add(member);
      } else {
        members[index] = member;
      }
      final updated = members.map((m) => jsonEncode(m.toJson())).toList();
      if (!listEquals(values, updated)) {
        await _preferences.setStringList(key, updated);
      }
    });
  }

  Future<void> remove(String backend, String owner, String memberId) {
    revision++;
    return _enqueue(() async {
      final key = _key(backend, owner);
      final values = await _preferences.getStringList(key);
      if (values == null) return;
      await _preferences.setStringList(
        key,
        values.where((v) => jsonDecode(v)['id'] != memberId).toList(),
      );
    });
  }
}

abstract interface class CachedFamilyMemberService {
  Future<List<FamilyMember>?> loadCachedForOwner(String ownerId);
}
