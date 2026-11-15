import 'package:flutter/material.dart';

import '../screens/photo_editor_screen.dart';
import 'profile_image_picker.dart';

/// Every gallery selection is confirmed here before any caller stores bytes.
abstract final class PhotoSelectionService {
  static Future<PickedProfileImage?> pick(
    BuildContext context, {
    required ProfileImagePicker picker,
  }) async {
    final image = await picker.pickFromGallery();
    if (image == null || !context.mounted) return null;
    return Navigator.of(context).push<PickedProfileImage>(
      MaterialPageRoute(builder: (_) => PhotoEditorScreen(image: image)),
    );
  }
}
