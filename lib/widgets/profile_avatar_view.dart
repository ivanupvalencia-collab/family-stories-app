import 'package:flutter/material.dart';

import '../models/profile_avatar.dart';

class ProfileAvatarView extends StatelessWidget {
  const ProfileAvatarView({
    this.avatarKey,
    this.avatarUrl,
    this.radius = 48,
    this.width,
    this.height,
    this.circular = true,
    this.alignment = Alignment.center,
    this.fallback,
    super.key,
  });

  final String? avatarKey;
  final String? avatarUrl;
  final double radius;
  final double? width;
  final double? height;
  final bool circular;
  final Alignment alignment;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = avatarUrl?.trim();
    final avatar = ProfileAvatarCatalog.findByKey(avatarKey);
    final placeholder = fallback ?? _GenericAvatarIcon(radius: radius);
    final image = normalizedUrl != null && normalizedUrl.isNotEmpty
        ? Image.network(
            normalizedUrl,
            fit: BoxFit.cover,
            alignment: alignment,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder,
            errorBuilder: (context, error, stackTrace) => placeholder,
          )
        : avatar != null
        ? Image.asset(avatar.assetPath, fit: BoxFit.contain)
        : placeholder;

    return Center(
      child: SizedBox(
        width: width ?? radius * 2,
        height: height ?? radius * 2,
        child: circular ? ClipOval(child: image) : ClipRect(child: image),
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
