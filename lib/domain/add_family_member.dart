import 'app_failure.dart';
import 'postgrest_failure.dart';

import '../models/family_member.dart';
import '../services/family_member_photo_service.dart';
import '../services/family_member_service.dart';
import '../services/family_member_storage.dart';
import '../services/profile_image_picker.dart';

/// Outcome of [AddFamilyMember.call]: [saved] is the created member when
/// [failure] is null; [photoSaved] is false only when a photo was
/// requested and could not be stored (the member itself is already safe).
class AddFamilyMemberResult {
  const AddFamilyMemberResult({
    required this.failure,
    required this.saved,
    required this.photoSaved,
  });
  final AppFailure? failure;
  final FamilyMember? saved;
  final bool photoSaved;
}

/// A-1: the member creation transaction, previously inlined in Home's
/// State. Creates the member locally or remotely and attaches the
/// optional photo; a photo failure never discards a saved member.
class AddFamilyMember {
  AddFamilyMember({
    required this.members,
    required this.photos,
    required this.localStorage,
  });

  final FamilyMemberService members;
  final FamilyMemberPhotoService photos;
  final FamilyMemberStorage localStorage;

  Future<AddFamilyMemberResult> call({
    required FamilyMember member,
    required String? ownerId,
    PickedProfileImage? photo,
  }) async {
    try {
      final saved = ownerId == null
          ? await _appendLocally(member)
          : await members.create(
              ownerId: ownerId,
              name: member.name,
              relationship: member.relationship,
            );
      if (photo != null) {
        try {
          return AddFamilyMemberResult(
            failure: null,
            saved: await photos.save(saved, photo),
            photoSaved: true,
          );
        } catch (_) {
          return AddFamilyMemberResult(
            failure: null,
            saved: saved,
            photoSaved: false,
          );
        }
      }
      return AddFamilyMemberResult(failure: null, saved: saved, photoSaved: true);
    } catch (error) {
      return AddFamilyMemberResult(
        failure: isPostgrestDenied(error)
            ? const AppFailure.rejected('No se pudo guardar el familiar.')
            : const AppFailure.unavailable(),
        saved: null,
        photoSaved: true,
      );
    }
  }

  Future<FamilyMember> _appendLocally(FamilyMember member) async {
    final current = await localStorage.load();
    await localStorage.save([...current, member]);
    return member;
  }
}
