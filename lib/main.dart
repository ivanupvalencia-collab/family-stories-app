import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const FamilyStoriesApp());
}

class FamilyStoriesApp extends StatelessWidget {
  const FamilyStoriesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Stories',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF72594A)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
