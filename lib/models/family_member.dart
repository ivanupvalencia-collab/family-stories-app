import 'local_id.dart';

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.name,
    required this.relationship,
    this.linkedAccountId,
    this.photoPath,
  });

  factory FamilyMember.create({
    required String name,
    required String relationship,
  }) {
    return FamilyMember(
      id: generateLocalId(),
      name: name,
      relationship: relationship,
    );
  }

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      id: json['id'] as String? ?? generateLocalId(),
      name: json['name'] as String,
      relationship: json['relationship'] as String,
      linkedAccountId: json['linkedAccountId'] as String?,
      photoPath: json['photoPath'] as String?,
    );
  }

  factory FamilyMember.fromSupabaseJson(Map<String, dynamic> json) {
    return FamilyMember(
      id: json['id'] as String,
      name: json['name'] as String,
      relationship: json['relationship'] as String,
      linkedAccountId: json['linked_account_id'] as String?,
      photoPath: json['photo_path'] as String?,
    );
  }

  final String id;
  final String name;
  final String relationship;
  final String? linkedAccountId;
  // App-private relative filename for local members; private Storage object
  // path for remote members. Never a linked account's avatar or a public URL.
  final String? photoPath;

  FamilyMember withPhotoPath(String? path) => FamilyMember(
    id: id,
    name: name,
    relationship: relationship,
    linkedAccountId: linkedAccountId,
    photoPath: path,
  );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'relationship': relationship,
      'linkedAccountId': linkedAccountId,
      'photoPath': photoPath,
    };
  }

  Map<String, dynamic> toSupabaseInsert({required String ownerId}) {
    return {
      'owner_id': ownerId,
      'name': name,
      'relationship': relationship,
      'linked_account_id': linkedAccountId,
    };
  }
}
