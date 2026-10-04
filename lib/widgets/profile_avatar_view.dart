import 'package:flutter/material.dart';

import '../models/profile_avatar.dart';

class ProfileAvatarView extends StatelessWidget {
  const ProfileAvatarView({
    this.avatarKey,
    this.avatarUrl,
    this.radius = 48,
    super.key,
  });

  final String? avatarKey;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = avatarUrl?.trim();
    final avatar = ProfileAvatarCatalog.findByKey(avatarKey);

    return Center(
      child: SizedBox.square(
        dimension: radius * 2,
        child: ClipOval(
          child: normalizedUrl != null && normalizedUrl.isNotEmpty
              ? Image.network(
                  normalizedUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _GenericAvatarIcon(radius: radius),
                )
              : avatar != null
              ? Image.asset(avatar.assetPath, fit: BoxFit.contain)
              : _GenericAvatarIcon(radius: radius),
        ),
      ),
    );
  }
}

class _GenericAvatarIcon extends StatelessWidget {
  const _GenericAvatarIcon({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.primaryContainer,
      child: Center(
        child: Icon(
          Icons.person_outline,
          size: radius * 1.1,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
