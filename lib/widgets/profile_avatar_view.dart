import 'package:flutter/material.dart';

import '../models/profile_avatar.dart';

class ProfileAvatarView extends StatelessWidget {
  const ProfileAvatarView({
    this.avatarKey,
    this.avatarUrl,
    this.imageProvider,
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
  final ImageProvider? imageProvider;
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
    // Only ProfileAvatarImageCache downloads avatars (S-5): there is no
    // NetworkImage fallback here anymore. A remote avatar with no provider
    // shows the placeholder instead of falling back to an unrelated stock
    // face from the local catalogue.
    final hasRemoteAvatar = normalizedUrl != null && normalizedUrl.isNotEmpty;
    final provider = hasRemoteAvatar ? imageProvider : null;
    final image = provider != null
        ? Image(
            image: provider,
            fit: BoxFit.cover,
            alignment: alignment,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder,
            errorBuilder: (context, error, stackTrace) => placeholder,
          )
        : hasRemoteAvatar
        ? placeholder
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
