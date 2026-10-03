import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/family_member_storage.dart';
import 'services/family_story_storage.dart';

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
    this.familyMemberStorage,
    this.familyStoryStorage,
    super.key,
  });

  final AuthService? authService;
  final FamilyMemberStorage? familyMemberStorage;
  final FamilyStoryStorage? familyStoryStorage;

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
        familyMemberStorage: familyMemberStorage,
        familyStoryStorage: familyStoryStorage,
      ),
    );
  }
}
