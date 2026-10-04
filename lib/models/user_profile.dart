class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    this.avatarKey,
    this.avatarUrl,
    this.createdAt,
  });

  final String id;
  final String name;
  final String? avatarKey;
  final String? avatarUrl;
  final DateTime? createdAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'];

    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarKey: json['avatar_key'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: createdAt is String ? DateTime.tryParse(createdAt) : null,
    );
  }

  UserProfile copyWith({String? name, String? avatarKey}) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      avatarKey: avatarKey ?? this.avatarKey,
      avatarUrl: avatarUrl,
      createdAt: createdAt,
    );
  }
}
