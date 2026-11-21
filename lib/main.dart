import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'design/aritoria_design.dart';
import 'screens/accept_invitation_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'services/auth_service.dart';
import 'services/avatar_storage_service.dart';
import 'services/family_member_storage.dart';
import 'services/family_member_service.dart';
import 'services/family_member_photo_service.dart';
import 'services/family_story_storage.dart';
import 'services/family_story_service.dart';
import 'services/incoming_link_service.dart';
import 'services/invitation_link.dart';
import 'services/invitation_service.dart';
import 'services/invitation_share_service.dart';
import 'services/profile_image_picker.dart';
import 'services/profile_service.dart';
import 'services/question_request_service.dart';
import 'services/received_request_details_service.dart';
import 'services/secure_session_storage.dart';
import 'services/session_data_sweeper.dart';
import 'services/shared_http_client.dart';

const _supabaseUrl = 'https://hwqvdrtehvixqloegilg.supabase.co';
const _supabasePublishableKey =
    'sb_publishable_y2Pi4ezsjcRTrrOiSsyEsw_BdKFCOef';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // S-3: the session (JWT + refresh token) and the PKCE verifier must not
  // live in plain SharedPreferences, where they are readable from the app's
  // private directory and travel in device backups.
  const secureStore = FlutterSecureKeyValueStore();
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
    // C-7: every storage/REST/auth download shares the app's single pooled
    // HttpClient (connection timeout included) with the avatar downloads.
    httpClient: sharedSupabaseHttpClient,
    // The app owns deep-link handling through PlatformIncomingLinkService and
    // never uses a redirect/OAuth flow, so supabase_flutter must not install
    // its own link observer and race with getInitialUri().
    authOptions: FlutterAuthClientOptions(
      detectSessionInUri: false,
      // Migrates any session still stored in plain SharedPreferences on the
      // first launch after the upgrade, so nobody gets signed out.
      localStorage: SecureLocalStorage(
        sessionKey: SecureLocalStorage.sessionKeyFor(_supabaseUrl),
        store: secureStore,
      ),
      pkceAsyncStorage: SecureGotrueAsyncStorage(store: secureStore),
    ),
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
    this.familyMemberPhotoService,
    this.familyStoryStorage,
    this.familyStoryService,
    this.invitationService,
    this.invitationShareService,
    this.incomingLinkService,
    this.questionRequestService,
    this.receivedRequestDetailsService,
    super.key,
  });

  final AuthService? authService;
  final ProfileService? profileService;
  final ProfileImagePicker? profileImagePicker;
  final AvatarStorageService? avatarStorageService;
  final FamilyMemberStorage? familyMemberStorage;
  final FamilyMemberService? familyMemberService;
  final FamilyMemberPhotoService? familyMemberPhotoService;
  final FamilyStoryStorage? familyStoryStorage;
  final FamilyStoryService? familyStoryService;
  final InvitationService? invitationService;
  final InvitationShareService? invitationShareService;
  final IncomingLinkService? incomingLinkService;
  final QuestionRequestService? questionRequestService;
  final ReceivedRequestDetailsService? receivedRequestDetailsService;

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
  SessionDataSweeper? _sessionSweeper;
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
    unawaited(_handleInitialUri());
    _authSubscription = _authService.authStateChanges.listen(_handleAuthChange);
    // S-6: one sweeper for the whole app, subscribed before any screen can
    // download anything. Installations without Supabase.initialize (local-only
    // and widget tests) have nothing to purge.
    try {
      _sessionSweeper = SessionDataSweeper(client: Supabase.instance.client);
    } catch (_) {
      _sessionSweeper = null;
    }
  }

  @override
  void dispose() {
    _sessionSweeper?.dispose();
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

  Future<void> _handleInitialUri() async {
    try {
      final uri = await _incomingLinkService.getInitialUri();
      if (uri != null && mounted) {
        _handleIncomingUri(uri);
      }
    } catch (_) {
      // Opening the app must remain possible if the platform cannot read a link.
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
        colorScheme: AritoriaDesign.theme().colorScheme,
        scaffoldBackgroundColor: AritoriaColors.cream,
        appBarTheme: AritoriaDesign.theme().appBarTheme,
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AritoriaColors.olive,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(
        authService: _authService,
        profileService: _profileService,
        profileImagePicker: widget.profileImagePicker,
        avatarStorageService: widget.avatarStorageService,
        familyMemberStorage: widget.familyMemberStorage,
        familyMemberService: widget.familyMemberService,
        familyMemberPhotoService: widget.familyMemberPhotoService,
        familyStoryStorage: widget.familyStoryStorage,
        familyStoryService: widget.familyStoryService,
        invitationService: _invitationService,
        invitationShareService: widget.invitationShareService,
        questionRequestService: _questionRequestService,
        receivedRequestDetailsService: widget.receivedRequestDetailsService,
      ),
    );
  }
}
