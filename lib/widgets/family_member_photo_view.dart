import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/family_member.dart';
import '../services/family_member_photo_service.dart';

// The reusable entry point for a member's own photo. It never loads profiles.
class FamilyMemberPhotoView extends StatefulWidget {
  const FamilyMemberPhotoView({
    required this.member,
    required this.photoService,
    this.radius = 40,
    this.previewBytes,
    super.key,
  });

  final FamilyMember member;
  final FamilyMemberPhotoService photoService;
  final double radius;
  final Uint8List? previewBytes;

  @override
  State<FamilyMemberPhotoView> createState() => _FamilyMemberPhotoViewState();
}

class _FamilyMemberPhotoViewState extends State<FamilyMemberPhotoView> {
  Future<Uint8List>? _photo;
  Listenable? _cacheChanges;

  void _load() {
    _photo =
        widget.previewBytes == null &&
            widget.member.photoPath != null &&
            widget.photoService.cachedPhoto(widget.member) == null
        ? widget.photoService.load(widget.member)
        : null;
  }

  void _watchCache() {
    _cacheChanges?.removeListener(_cacheChanged);
    _cacheChanges =
        widget.member.photoPath == null || widget.previewBytes != null
        ? null
        : widget.photoService.cacheChanges;
    _cacheChanges?.addListener(_cacheChanged);
  }

  void _cacheChanged() {
    // Discard a completed Future too: it must not retain another session's data
    // or re-download a path just removed by a successful photo edit.
    setState(() => _photo = null);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _watchCache();
  }

  @override
  void didUpdateWidget(FamilyMemberPhotoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member.id != widget.member.id ||
        oldWidget.member.photoPath != widget.member.photoPath ||
        oldWidget.photoService != widget.photoService ||
        oldWidget.previewBytes != widget.previewBytes) {
      _load();
      _watchCache();
    }
  }

  @override
  void dispose() {
    _cacheChanges?.removeListener(_cacheChanged);
    super.dispose();
  }

  Widget _fallback() => ColoredBox(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Center(
      child: Icon(
        Icons.person_outline,
        size: widget.radius * 1.1,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    ),
  );

  Widget _image(Uint8List? bytes) => bytes == null || bytes.isEmpty
      ? _fallback()
      : Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: false,
          errorBuilder: (_, _, _) => _fallback(),
        );

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: 'Foto de ${widget.member.name}',
      image: true,
      child: SizedBox.square(
        dimension: widget.radius * 2,
        child: ClipOval(
          child: widget.previewBytes != null
              ? _image(widget.previewBytes)
              : FutureBuilder<Uint8List>(
                  future: _photo,
                  builder: (context, snapshot) => _image(
                    _cacheChanges == null &&
                            snapshot.connectionState == ConnectionState.done &&
                            !snapshot.hasError
                        ? widget.photoService.cachedPhoto(widget.member) ??
                              snapshot.data
                        : widget.photoService.cachedPhoto(widget.member),
                  ),
                ),
        ),
      ),
    ),
  );
}
