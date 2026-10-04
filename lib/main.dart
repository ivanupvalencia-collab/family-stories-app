import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/avatar_storage_service.dart';
import 'services/family_member_storage.dart';
import 'services/family_member_service.dart';
import 'services/family_story_storage.dart';
import 'services/invitation_service.dart';
import 'services/invitation_share_service.dart';
import 'services/profile_image_picker.dart';
import 'services/profile_service.dart';

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

class FamilyStoriesApp extends StatelessWidget {
  const FamilyStoriesApp({
    this.authService,
    this.profileService,
    this.profileImagePicker,
    this.avatarStorageService,
    this.familyMemberStorage,
    this.familyMemberService,
    this.familyStoryStorage,
    this.invitationService,
    this.invitationShareService,
    super.key,
  });

  final AuthService? authService;
  final ProfileService? profileService;
  final ProfileImagePicker? profileImagePicker;
  final AvatarStorageService? avatarStorageService;
  final FamilyMemberStorage? familyMemberStorage;
  final FamilyMemberService? familyMemberService;
  final FamilyStoryStorage? familyStoryStorage;
  final InvitationService? invitationService;
  final InvitationShareService? invitationShareService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Stories',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF72594A)),
        useMaterial3: true,
      ),
      home: HomeScreen(
        authService: authService,
        profileService: profileService,
        profileImagePicker: profileImagePicker,
        avatarStorageService: avatarStorageService,
        familyMemberStorage: familyMemberStorage,
        familyMemberService: familyMemberService,
        familyStoryStorage: familyStoryStorage,
        invitationService: invitationService,
        invitationShareService: invitationShareService,
      ),
    );
  }
}
