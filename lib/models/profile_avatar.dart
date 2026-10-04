class ProfileAvatar {
  const ProfileAvatar({required this.key, required this.assetPath});

  final String key;
  final String assetPath;
}

abstract final class ProfileAvatarCatalog {
  static const avatars = <ProfileAvatar>[
    ProfileAvatar(key: 'avatar_01', assetPath: 'assets/avatars/avatar_01.png'),
    ProfileAvatar(key: 'avatar_02', assetPath: 'assets/avatars/avatar_02.png'),
    ProfileAvatar(key: 'avatar_03', assetPath: 'assets/avatars/avatar_03.png'),
    ProfileAvatar(key: 'avatar_04', assetPath: 'assets/avatars/avatar_04.png'),
  ];

  static ProfileAvatar? findByKey(String? key) {
    if (key == null) {
      return null;
    }

    for (final avatar in avatars) {
      if (avatar.key == key) {
        return avatar;
      }
    }
    return null;
  }
}
