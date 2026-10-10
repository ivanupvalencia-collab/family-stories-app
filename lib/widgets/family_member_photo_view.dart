import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../services/family_member_photo_service.dart';
import 'private_photo_view.dart';

// The reusable entry point for a member's own photo. It never loads profiles.
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

  @override
  Widget build(BuildContext context) => PrivatePhotoView<FamilyMember>(
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
        ),
  );
}
