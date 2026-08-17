import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/level_select_screen.dart';

void main() {
  runApp(const WordPuzzleTrainerApp());
}

class WordPuzzleTrainerApp extends StatelessWidget {
  const WordPuzzleTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '英単語パズルトレーナー',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B9BD5)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      initialRoute: HomeScreen.routeName,
      routes: {
        HomeScreen.routeName: (context) => const HomeScreen(),
        LevelSelectScreen.routeName: (context) => const LevelSelectScreen(),
      },
    );
  }
}
