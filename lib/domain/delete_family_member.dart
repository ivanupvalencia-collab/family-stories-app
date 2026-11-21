import 'app_failure.dart';

import '../models/family_member.dart';
import '../services/family_member_deletion_service.dart';
import '../services/family_member_photo_service.dart';
import '../services/family_member_service.dart';
import '../services/family_story_service.dart';
import '../services/story_photo_service.dart';

/// A-1: the remote family-member deletion transaction, previously inlined
/// in the screen's State (`family_member_screen.dart`). Executes the
/// deletion plan and clears every local remnant of the member: the member
/// cache, both photo caches and the downloaded audio.
class DeleteFamilyMember {
  DeleteFamilyMember({
    required this.deletion,
    required this.photos,
    required this.storyPhotos,
    required this.remoteStories,
    this.memberCache,
  });

  final FamilyMemberDeletionService deletion;
  final FamilyMemberPhotoService photos;
  final StoryPhotoService storyPhotos;
  final FamilyStoryService? remoteStories;
  final FamilyMemberCacheRemover? memberCache;

  /// Returns null when the member (and every remnant) was removed.
  Future<AppFailure?> call({
    required String ownerId,
    required FamilyMember member,
  }) async {
    try {
      final plan = await deletion.delete(
        ownerId: ownerId,
        familyMemberId: member.id,
      );
      await memberCache?.forgetMember(ownerId, member.id);
      await photos.forgetPhotos(
        ownerId,
        plan.resources
            .where((r) => r.bucket == 'family-member-photos')
            .map((r) => r.path),
      );
      await storyPhotos.forgetPhotos(
        ownerId,
        plan.resources
            .where((r) => r.bucket == 'story-photos')
            .map((r) => r.path),
      );
      await remoteStories?.clearAudioCache();
      return null;
    } catch (_) {
      // The plan may be partially applied on the server: the screen
      // refreshes and offers a retry instead of reporting blind success.
      return const AppFailure.unavailable();
    }
  }
}
