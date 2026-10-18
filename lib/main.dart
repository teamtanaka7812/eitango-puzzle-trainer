import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/level_select_screen.dart';
import 'screens/participant_id_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_service.dart';
import 'services/participant_service.dart';
import 'widgets/recording_notices.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WordPuzzleTrainerApp());
  // 匿名ログイン（学習記録を「本人の記録だけ」に絞り込むための識別子。AuthService、
  // firestore.rules参照）は、画面の表示を待たせないよう、アプリの起動後に始める。
  // 失敗しても（通信できない・1時間あたりの新規作成の上限に達した、など）ゲームは
  // 遊べる。失敗したときは、ホーム画面などに小さな案内と「もう一度」ボタンが出る
  // （AuthStatusBanner）。Web以外では何もしない。
  unawaited(AuthService.ensureSignedIn());
}

class WordPuzzleTrainerApp extends StatelessWidget {
  const WordPuzzleTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '英単語パズルトレーナー',
      debugShowCheckedModeBanner: false,
      // 記録の保存に失敗したときの小さな案内を、どの画面でも出せるようにする。
      scaffoldMessengerKey: kMessengerKey,
      builder: (context, child) => RecordingNoticeListener(child: child ?? const SizedBox.shrink()),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B9BD5)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const _StartupGate(),
      routes: {
        LevelSelectScreen.routeName: (context) => const LevelSelectScreen(),
        SettingsScreen.routeName: (context) => const SettingsScreen(),
        HistoryScreen.routeName: (context) => const HistoryScreen(),
      },
    );
  }
}

/// アプリ起動時に、参加者IDが端末に保存済みかを確認してから、
/// ホーム画面か参加者ID入力画面のどちらを見せるかを決める起動ゲート。
/// ナビゲーションスタックの一番最初のルートとして働くので、
/// `Navigator.popUntil((route) => route.isFirst)`（ゲーム画面・結果画面の
/// 「Menu」ボタン）は、これまで通りここに戻ってくる。
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late Future<String?> _participantId;

  @override
  void initState() {
    super.initState();
    _participantId = ParticipantService.getParticipantId();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _participantId,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == null) {
          return ParticipantIdScreen(
            onSaved: () => setState(() {
              _participantId = ParticipantService.getParticipantId();
            }),
          );
        }
        return const HomeScreen();
      },
    );
  }
}
