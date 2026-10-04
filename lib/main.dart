import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'screens/accept_invitation_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'services/auth_service.dart';
import 'services/avatar_storage_service.dart';
import 'services/family_member_storage.dart';
import 'services/family_member_service.dart';
import 'services/family_story_storage.dart';
import 'services/family_story_service.dart';
import 'services/incoming_link_service.dart';
import 'services/invitation_link.dart';
import 'services/invitation_service.dart';
import 'services/invitation_share_service.dart';
import 'services/profile_image_picker.dart';
import 'services/profile_service.dart';
import 'services/question_request_service.dart';

const _supabaseUrl = 'https://hwqvdrtehvixqloegilg.supabase.co';
const _supabasePublishableKey =
    'sb_publishable_y2Pi4ezsjcRTrrOiSsyEsw_BdKFCOef';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );

  runApp(const FamilyStoriesApp());
}

class FamilyStoriesApp extends StatefulWidget {
  const FamilyStoriesApp({
    this.authService,
    this.profileService,
    this.profileImagePicker,
    this.avatarStorageService,
    this.familyMemberStorage,
    this.familyMemberService,
    this.familyStoryStorage,
    this.familyStoryService,
    this.invitationService,
    this.invitationShareService,
    this.incomingLinkService,
    this.questionRequestService,
    super.key,
  });

  final AuthService? authService;
  final ProfileService? profileService;
  final ProfileImagePicker? profileImagePicker;
  final AvatarStorageService? avatarStorageService;
  final FamilyMemberStorage? familyMemberStorage;
  final FamilyMemberService? familyMemberService;
  final FamilyStoryStorage? familyStoryStorage;
  final FamilyStoryService? familyStoryService;
  final InvitationService? invitationService;
  final InvitationShareService? invitationShareService;
  final IncomingLinkService? incomingLinkService;
  final QuestionRequestService? questionRequestService;

  @override
  State<FamilyStoriesApp> createState() => _FamilyStoriesAppState();
}

class _FamilyStoriesAppState extends State<FamilyStoriesApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AuthService _authService;
  late final ProfileService _profileService;
  late final InvitationService _invitationService;
  late final QuestionRequestService _questionRequestService;
  late final IncomingLinkService _incomingLinkService;
  late final StreamSubscription<Uri> _linkSubscription;
  late final StreamSubscription<AuthUser?> _authSubscription;
  String? _pendingInvitationToken;
  String? _activeInvitationToken;
  bool _loginRouteOpen = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? SupabaseGoogleAuthService();
    _profileService = widget.profileService ?? SupabaseProfileService();
    _invitationService =
        widget.invitationService ?? SupabaseInvitationService();
    _questionRequestService =
        widget.questionRequestService ?? SupabaseQuestionRequestService();
    _incomingLinkService =
        widget.incomingLinkService ?? PlatformIncomingLinkService();
    _linkSubscription = _incomingLinkService.uriLinks.listen(
      _handleIncomingUri,
    );
    _authSubscription = _authService.authStateChanges.listen(_handleAuthChange);
  }

  @override
  void dispose() {
    _linkSubscription.cancel();
    _authSubscription.cancel();
    super.dispose();
  }

  void _handleIncomingUri(Uri uri) {
    final token = InvitationLink.tokenFrom(uri);
    if (token == null ||
        _pendingInvitationToken != null ||
        _activeInvitationToken != null) {
      return;
    }

    if (_authService.currentUser == null) {
      _pendingInvitationToken = token;
      _afterCurrentFrame(_openLoginForPendingInvitation);
    } else {
      _activeInvitationToken = token;
      _afterCurrentFrame(() => _openInvitation(token));
    }
  }

  void _handleAuthChange(AuthUser? user) {
    if (user == null || _pendingInvitationToken == null) {
      return;
    }

    if (_loginRouteOpen) {
      _navigatorKey.currentState?.pop();
    }
    _afterCurrentFrame(_continuePendingInvitation);
  }

  void _afterCurrentFrame(Future<void> Function() action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(action());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openLoginForPendingInvitation() async {
    if (_loginRouteOpen ||
        _pendingInvitationToken == null ||
        _authService.currentUser != null) {
      await _continuePendingInvitation();
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _afterCurrentFrame(_openLoginForPendingInvitation);
      return;
    }

    _loginRouteOpen = true;
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (context) => ProfileScreen(
          authService: _authService,
          profileService: _profileService,
          profileImagePicker: widget.profileImagePicker,
          avatarStorageService: widget.avatarStorageService,
          invitationService: _invitationService,
        ),
      ),
    );
    _loginRouteOpen = false;

    if (_authService.currentUser != null) {
      await _continuePendingInvitation();
    } else {
      _pendingInvitationToken = null;
    }
  }

  Future<void> _continuePendingInvitation() async {
    if (_authService.currentUser == null || _activeInvitationToken != null) {
      return;
    }

    final token = _pendingInvitationToken;
    if (token == null) {
      return;
    }
    _pendingInvitationToken = null;
    _activeInvitationToken = token;
    await _openInvitation(token);
  }

  Future<void> _openInvitation(String token) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _activeInvitationToken = null;
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute(
        builder: (context) => AcceptInvitationScreen(
          invitationService: _invitationService,
          initialToken: token,
        ),
      ),
    );
    if (_activeInvitationToken == token) {
      _activeInvitationToken = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Family Stories',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF72594A)),
        useMaterial3: true,
      ),
      home: HomeScreen(
        authService: _authService,
        profileService: _profileService,
        profileImagePicker: widget.profileImagePicker,
        avatarStorageService: widget.avatarStorageService,
        familyMemberStorage: widget.familyMemberStorage,
        familyMemberService: widget.familyMemberService,
        familyStoryStorage: widget.familyStoryStorage,
        familyStoryService: widget.familyStoryService,
        invitationService: _invitationService,
        invitationShareService: widget.invitationShareService,
        questionRequestService: _questionRequestService,
      ),
    );
  }
}
