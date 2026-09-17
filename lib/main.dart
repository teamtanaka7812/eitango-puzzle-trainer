import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/level_select_screen.dart';
import 'screens/participant_id_screen.dart';
import 'screens/settings_screen.dart';
import 'services/participant_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase接続は現時点でWeb版のみ対応（DefaultFirebaseOptionsを参照）。
  // 他プラットフォーム向けビルドでは初期化自体をスキップし、コンパイル・起動が
  // 壊れないようにする（学習データ送信機能自体は次回実装予定）。
  if (kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
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
      home: const _StartupGate(),
      routes: {
        LevelSelectScreen.routeName: (context) => const LevelSelectScreen(),
        SettingsScreen.routeName: (context) => const SettingsScreen(),
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
