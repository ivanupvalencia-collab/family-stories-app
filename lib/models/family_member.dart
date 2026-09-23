import 'local_id.dart';

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.name,
    required this.relationship,
    this.linkedAccountId,
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
    );
  }

  final String id;
  final String name;
  final String relationship;
  final String? linkedAccountId;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'relationship': relationship,
      'linkedAccountId': linkedAccountId,
    };
  }
}
