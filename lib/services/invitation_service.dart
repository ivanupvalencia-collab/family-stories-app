import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family_invitation.dart';

class CannotAcceptOwnInvitationException implements Exception {
  const CannotAcceptOwnInvitationException();
}

abstract class InvitationService {
  Future<FamilyInvitation> createInvitation(String familyMemberId);

  Future<InvitationPreview?> getInvitationPreview(String token);

  Future<bool> acceptInvitation(String token);

  Future<bool> cancelInvitation(String invitationId);
}

class SupabaseInvitationService implements InvitationService {
  SupabaseInvitationService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<FamilyInvitation> createInvitation(String familyMemberId) async {
    final data = await _client.rpc(
      'create_family_invitation',
      params: {'p_family_member_id': familyMemberId},
    );
    final row = _singleRow(data);
    if (row == null) {
      throw StateError('The invitation RPC returned no data.');
    }
    return FamilyInvitation.fromJson(row);
  }

  @override
  Future<InvitationPreview?> getInvitationPreview(String token) async {
    final data = await _client.rpc(
      'get_family_invitation_preview',
      params: {'p_token': token},
    );
    final row = _singleRow(data);
    return row == null ? null : InvitationPreview.fromJson(row);
  }

  @override
  Future<bool> acceptInvitation(String token) async {
    try {
      final data = await _client.rpc(
        'accept_family_invitation',
        params: {'p_token': token},
      );
      return data == true;
    } on PostgrestException catch (error) {
      if (error.message == 'cannot_accept_own_invitation') {
        throw const CannotAcceptOwnInvitationException();
      }
      rethrow;
    }
  }

  @override
  Future<bool> cancelInvitation(String invitationId) async {
    final data = await _client.rpc(
      'cancel_family_invitation',
      params: {'p_invitation_id': invitationId},
    );
    return data == true;
  }

  Map<String, dynamic>? _singleRow(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is List && data.isNotEmpty) {
      return Map<String, dynamic>.from(data.first as Map);
    }
    return null;
  }
}
