import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/auth_service.dart';
import 'services/avatar_storage_service.dart';
import 'services/family_member_photo_service.dart';
import 'services/family_member_service.dart';
import 'services/family_member_storage.dart';
import 'services/family_story_service.dart';
import 'services/family_story_storage.dart';
import 'services/incoming_link_service.dart';
import 'services/invitation_service.dart';
import 'services/invitation_share_service.dart';
import 'services/profile_image_picker.dart';
import 'services/profile_service.dart';
import 'services/question_request_service.dart';
import 'services/received_request_details_service.dart';
import 'services/session_monitor.dart';
import 'services/visible_account_avatar_service.dart';

/// A-3: the single composition root. `main()` builds it once, after
/// `Supabase.initialize`, and every screen receives its dependencies from
/// here: no widget below the graph constructs a concrete service or falls
/// back to a singleton.
///
/// Tests inject fakes through the same constructor parameters; only the
/// parameters left null resolve to a concrete implementation.
class AppGraph {
  factory AppGraph({
    AuthService? authService,
    ProfileService? profileService,
    ProfileImagePicker? profileImagePicker,
    AvatarStorageService? avatarStorageService,
    VisibleAccountAvatarService? visibleAccountAvatarService,
    FamilyMemberStorage? familyMemberStorage,
    FamilyMemberService? familyMemberService,
    FamilyMemberPhotoService? familyMemberPhotoService,
    FamilyStoryStorage? familyStoryStorage,
    FamilyStoryService? familyStoryService,
    InvitationService? invitationService,
    InvitationShareService? invitationShareService,
    IncomingLinkService? incomingLinkService,
    QuestionRequestService? questionRequestService,
    ReceivedRequestDetailsService? receivedRequestDetailsService,
    SessionMonitor? sessionMonitor,
  }) {
    // A-4: one shared auth subscription, created only when a concrete
    // service that listens is actually built (tests inject both services).
    final session =
        familyMemberService == null || familyStoryService == null
        ? sessionMonitor ?? SessionMonitor(Supabase.instance.client)
        : sessionMonitor;
    return AppGraph._(
      authService: authService ?? SupabaseGoogleAuthService(),
      profileService: profileService ?? SupabaseProfileService(),
      profileImagePicker: profileImagePicker ?? DeviceProfileImagePicker(),
      avatarStorageService: avatarStorageService,
      // The avatar metadata service needs the client; local-only
      // installations and widget tests keep it null and render the
      // fallback initials.
      visibleAccountAvatarService:
          visibleAccountAvatarService ?? _resolveAvatars(),
      familyMemberStorage:
          familyMemberStorage ?? SharedPreferencesFamilyMemberStorage(),
      familyMemberService:
          familyMemberService ??
          SupabaseFamilyMemberService(sessionMonitor: session),
      // Nullable on purpose: Home resolves the photo service per account
      // (local storage mode against Supabase mode).
      familyMemberPhotoService: familyMemberPhotoService,
      familyStoryStorage: familyStoryStorage ?? LocalFamilyStoryStorage(),
      familyStoryService:
          familyStoryService ??
          SupabaseFamilyStoryService(sessionMonitor: session),
      invitationService: invitationService ?? SupabaseInvitationService(),
      invitationShareService:
          invitationShareService ?? PlatformInvitationShareService(),
      incomingLinkService:
          incomingLinkService ?? PlatformIncomingLinkService(),
      questionRequestService:
          questionRequestService ?? SupabaseQuestionRequestService(),
      receivedRequestDetailsService:
          receivedRequestDetailsService ?? SupabaseReceivedRequestDetailsService(),
      sessionMonitor: session,
    );
  }

  AppGraph._({
    required this.authService,
    required this.profileService,
    required this.profileImagePicker,
    required this.avatarStorageService,
    required this.visibleAccountAvatarService,
    required this.familyMemberStorage,
    required this.familyMemberService,
    required this.familyMemberPhotoService,
    required this.familyStoryStorage,
    required this.familyStoryService,
    required this.invitationService,
    required this.invitationShareService,
    required this.incomingLinkService,
    required this.questionRequestService,
    required this.receivedRequestDetailsService,
    this.sessionMonitor,
  });

  final AuthService authService;
  final ProfileService profileService;
  final ProfileImagePicker profileImagePicker;

  /// Nullable on purpose: building the concrete one resolves the Supabase
  /// client, so ProfileScreen keeps its lazy in-screen resolution for the
  /// local-only case exactly as before the graph existed.
  final AvatarStorageService? avatarStorageService;
  final VisibleAccountAvatarService? visibleAccountAvatarService;
  final FamilyMemberStorage familyMemberStorage;
  final FamilyMemberService familyMemberService;

  /// Null in production: Home builds it per account (local against Supabase
  /// mode); tests inject a fixed one.
  final FamilyMemberPhotoService? familyMemberPhotoService;
  final FamilyStoryStorage familyStoryStorage;
  final FamilyStoryService familyStoryService;
  final InvitationService invitationService;
  final InvitationShareService invitationShareService;
  final IncomingLinkService incomingLinkService;
  final QuestionRequestService questionRequestService;
  final ReceivedRequestDetailsService receivedRequestDetailsService;

  /// A-4: owned here so the whole graph can detach at once.
  final SessionMonitor? sessionMonitor;

  static VisibleAccountAvatarService? _resolveAvatars() {
    try {
      return SupabaseVisibleAccountAvatarService(
        client: Supabase.instance.client,
      );
    } catch (_) {
      return null; // Local-only installations and widget tests.
    }
  }

  /// A-4: detaches every auth listener the graph owns.
  void dispose() {
    sessionMonitor?.dispose();
  }
}
