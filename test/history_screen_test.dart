import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:word_puzzle_trainer/screens/history_screen.dart';
import 'package:word_puzzle_trainer/services/local_history_service.dart';

void main() {
  testWidgets('記録がないときは案内メッセージを表示する', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('まだ記録がありません'), findsOneWidget);
  });

  testWidgets('記録があるときは合計・レベル別の内訳を表示する', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocalHistoryService.recordAttempt(level: 1, isCorrect: true);
    await LocalHistoryService.recordAttempt(level: 1, isCorrect: true);
    await LocalHistoryService.recordAttempt(level: 2, isCorrect: false);

    await tester.pumpWidget(const MaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget); // 解いた問題数
    expect(find.text('2'), findsOneWidget); // 正解数
    expect(find.text('67%'), findsOneWidget); // 全体正答率

    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('Level 3'), findsOneWidget);
    expect(find.text('2 / 2 問正解'), findsOneWidget);
    expect(find.text('0 / 1 問正解'), findsOneWidget);
    expect(find.text('0 / 0 問正解'), findsOneWidget);
  });
}
