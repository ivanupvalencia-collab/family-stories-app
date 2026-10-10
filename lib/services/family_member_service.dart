import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family_member.dart';

abstract class FamilyMemberService {
  Future<List<FamilyMember>> loadForOwner(String ownerId);

  Future<FamilyMember?> loadMemberForOwner({
    required String ownerId,
    required String familyMemberId,
  });

  Future<FamilyMember> create({
    required String ownerId,
    required String name,
    required String relationship,
  });

  Future<FamilyMember> updatePhoto({
    required String ownerId,
    required String familyMemberId,
    required String? photoPath,
    required String? expectedPhotoPath,
  });
}

class SupabaseFamilyMemberService implements FamilyMemberService {
  SupabaseFamilyMemberService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<FamilyMember>> loadForOwner(String ownerId) async {
    final data = await _client
        .from('family_members')
        .select('id, name, relationship, linked_account_id, photo_path')
        .eq('owner_id', ownerId)
        .order('created_at');

    return data.map(FamilyMember.fromSupabaseJson).toList();
  }

  @override
  Future<FamilyMember?> loadMemberForOwner({
    required String ownerId,
    required String familyMemberId,
  }) async {
    final data = await _client
        .from('family_members')
        .select('id, name, relationship, linked_account_id, photo_path')
        .eq('owner_id', ownerId)
        .eq('id', familyMemberId)
        .maybeSingle();

    return data == null ? null : FamilyMember.fromSupabaseJson(data);
  }

  @override
  Future<FamilyMember> create({
    required String ownerId,
    required String name,
    required String relationship,
  }) async {
    final familyMember = FamilyMember.create(
      name: name,
      relationship: relationship,
    );
    final data = await _client
        .from('family_members')
        .insert(familyMember.toSupabaseInsert(ownerId: ownerId))
        .select('id, name, relationship, linked_account_id, photo_path')
        .single();

    return FamilyMember.fromSupabaseJson(data);
  }

  @override
  Future<FamilyMember> updatePhoto({
    required String ownerId,
    required String familyMemberId,
    required String? photoPath,
    required String? expectedPhotoPath,
  }) async {
    if (_client.auth.currentUser?.id != ownerId) {
      throw StateError('The owner session is required.');
    }
    // Install supabase/manual/02_family_member_photo_rpc.sql manually first.
    // The RPC updates only photo_path and checks ownership and the old value.
    final data = await _client.rpc(
      'set_family_member_photo',
      params: {
        'p_family_member_id': familyMemberId,
        'p_photo_path': photoPath,
        'p_expected_photo_path': expectedPhotoPath,
      },
    );
    return FamilyMember.fromSupabaseJson(
      Map<String, dynamic>.from(data as Map),
    );
  }
}
