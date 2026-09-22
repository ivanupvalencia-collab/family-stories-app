import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/family_member_storage.dart';
import 'services/family_story_storage.dart';

void main() {
  runApp(const FamilyStoriesApp());
}

class FamilyStoriesApp extends StatelessWidget {
  const FamilyStoriesApp({
    this.familyMemberStorage,
    this.familyStoryStorage,
    super.key,
  });

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
        familyMemberStorage: familyMemberStorage,
        familyStoryStorage: familyStoryStorage,
      ),
    );
  }
}
