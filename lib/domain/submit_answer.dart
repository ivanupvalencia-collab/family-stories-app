import 'app_failure.dart';
import 'postgrest_failure.dart';

import '../models/family_story.dart';
import '../models/question_request.dart';
import '../services/profile_image_picker.dart';
import '../services/question_request_service.dart';
import '../services/story_photo_service.dart';

/// Outcome of [SubmitAnswer.call]: [failure] is null when the answer was
/// committed; [photoAttached] is false only when a photo was requested and
/// could not be attached (the answer itself is already safe).
class SubmitAnswerResult {
  const SubmitAnswerResult({required this.failure, required this.photoAttached});
  final AppFailure? failure;
  final bool photoAttached;
}

/// A-1: the answer transaction, previously inlined in the screen's State
/// (`question_request_screen.dart`). Uploads the audio, completes the
/// request — rolling the upload back when the RPC fails — and attaches the
/// optional photo. A photo failure never discards a committed answer.
class SubmitAnswer {
  SubmitAnswer({required this.questionRequests, this.photos});

  final QuestionRequestService questionRequests;

  /// Null means the caller has no photo store: a requested photo is
  /// reported as not attached instead of fabricating a concrete service.
  final StoryPhotoService? photos;

  Future<SubmitAnswerResult> call({
    required QuestionRequest request,
    required String audioPath,
    required Duration duration,
    PickedProfileImage? photo,
  }) async {
    final objectPath = createQuestionAnswerObjectPath(request.id);
    var uploaded = false;
    late String storyId;
    try {
      await questionRequests.uploadAnswerAudio(
        localAudioPath: audioPath,
        objectPath: objectPath,
      );
      uploaded = true;
      storyId = await questionRequests.completeQuestionRequest(
        questionRequestId: request.id,
        audioPath: objectPath,
        durationSeconds: duration.inSeconds,
      );
    } catch (error) {
      if (uploaded) {
        try {
          await questionRequests.deleteAnswerAudio(objectPath);
        } catch (_) {
          // Storage cleanup depends on the authenticated user's DELETE
          // policy.
        }
      }
      return SubmitAnswerResult(
        failure: isPostgrestDenied(error)
            ? const AppFailure.rejected('La respuesta no se puede enviar.')
            : const AppFailure.unavailable(),
        photoAttached: true,
      );
    }
    if (photo != null) {
      final photoStore = photos;
      if (photoStore == null) {
        // No photo store: the answer is safe, the photo is not attached.
        return const SubmitAnswerResult(failure: null, photoAttached: false);
      }
      try {
        // The completion RPC's returned ID is authoritative. A separate
        // photo failure never enters the audio rollback above.
        final FamilyStory? seed = await questionRequests.loadAnswerStory(
          request.id,
        );
        if (seed == null || seed.id != storyId) {
          throw StateError('Answer metadata unavailable');
        }
        await photoStore.save(seed, photo);
      } catch (_) {
        return const SubmitAnswerResult(failure: null, photoAttached: false);
      }
    }
    return const SubmitAnswerResult(failure: null, photoAttached: true);
  }
}
