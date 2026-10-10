import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';
import '../models/family_story.dart';
import '../services/story_photo_service.dart';
import 'private_photo_view.dart';

class StoryPhotoView extends StatelessWidget {
  const StoryPhotoView({
    required this.story,
    required this.service,
    this.width = 64,
    this.height = 64,
    super.key,
  });
  final FamilyStory story;
  final StoryPhotoService service;
  final double width, height;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: PrivatePhotoView<FamilyStory>(
      item: story,
      identity: story.id,
      reference: story.photoPath,
      service: service,
      width: width,
      height: height,
      label: 'Foto de esta historia',
      fallback: const ColoredBox(
        color: AritoriaColors.sand,
        child: Center(
          child: Icon(Icons.auto_stories_outlined, color: AritoriaColors.olive),
        ),
      ),
    ),
  );
}
