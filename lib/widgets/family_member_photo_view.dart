import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../services/family_member_photo_service.dart';
import '../services/visible_account_avatar_service.dart';
import 'account_avatar_view.dart';
import 'private_photo_view.dart';

// Own photos always take priority; linked account avatars are display-only.
class FamilyMemberPhotoView extends StatelessWidget {
  const FamilyMemberPhotoView({
    required this.member,
    required this.photoService,
    this.radius = 40,
    this.previewBytes,
    this.circular = true,
    this.width,
    this.height,
    this.fallback,
    this.alignment = Alignment.center,
    this.avatarService,
    super.key,
  });

  final FamilyMember member;
  final FamilyMemberPhotoService photoService;
  final double radius;
  final Uint8List? previewBytes;
  final bool circular;
  final double? width;
  final double? height;
  final Widget? fallback;
  final Alignment alignment;
  final VisibleAccountAvatarService? avatarService;

  @override
  Widget build(BuildContext context) {
    final placeholder =
        fallback ??
        ColoredBox(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Center(
            child: Icon(
              Icons.person_outline,
              size: radius * 1.1,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        );
    final linkedId = member.linkedAccountId;
    return PrivatePhotoView<FamilyMember>(
      item: member,
      identity: member.id,
      reference: member.photoPath,
      service: photoService,
      width: width ?? radius * 2,
      height: height ?? radius * 2,
      circular: circular,
      alignment: alignment,
      previewBytes: previewBytes,
      label: 'Foto de ${member.name}',
      fallback:
          member.photoPath == null && previewBytes == null && linkedId != null
          ? AccountAvatarView(
              accountId: linkedId,
              service: avatarService,
              radius: radius,
              width: width,
              height: height,
              circular: circular,
              alignment: alignment,
              fallback: placeholder,
            )
          : placeholder,
    );
  }
}
