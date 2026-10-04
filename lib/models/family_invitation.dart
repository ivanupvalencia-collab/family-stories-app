class FamilyInvitation {
  const FamilyInvitation({
    required this.id,
    required this.token,
    required this.expiresAt,
  });

  factory FamilyInvitation.fromJson(Map<String, dynamic> json) {
    return FamilyInvitation(
      id: json['invitation_id'] as String,
      token: json['invitation_token'] as String,
      expiresAt: DateTime.parse(json['invitation_expires_at'] as String),
    );
  }

  final String id;
  final String token;
  final DateTime expiresAt;
}

class InvitationPreview {
  const InvitationPreview({
    required this.familyMemberName,
    required this.inviterName,
    required this.expiresAt,
  });

  factory InvitationPreview.fromJson(Map<String, dynamic> json) {
    return InvitationPreview(
      familyMemberName: json['family_member_name'] as String,
      inviterName: json['inviter_name'] as String? ?? 'Alguien',
      expiresAt: DateTime.parse(json['invitation_expires_at'] as String),
    );
  }

  final String familyMemberName;
  final String inviterName;
  final DateTime expiresAt;
}
