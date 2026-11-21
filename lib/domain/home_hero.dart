import '../models/family_member.dart';
import '../models/profile_avatar.dart';
import '../models/user_profile.dart';

/// A-2: pure domain rule — the hero of Home is the first member with
/// something to show: an own photo, or a linked account with a visible
/// avatar. Moved out of the widget so it stays testable without UI.
FamilyMember? selectHomeHero(
  List<FamilyMember> members, {
  UserProfile? Function(String accountId)? linkedProfile,
}) {
  if (members.isEmpty) return null;
  return members.firstWhere((member) {
    if (member.photoPath != null) return true;
    final accountId = member.linkedAccountId;
    final profile = accountId == null ? null : linkedProfile?.call(accountId);
    return (profile?.avatarUrl?.trim().isNotEmpty ?? false) ||
        ProfileAvatarCatalog.findByKey(profile?.avatarKey) != null;
  }, orElse: () => members.first);
}
