import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:word_puzzle_trainer/main.dart';

void main() {
  // 起動直後は参加者ID保存有無を確認する非同期処理（_StartupGate）を経由するため、
  // 「参加者IDが保存済み（＝2回目以降の起動）」を想定するテストでは、事前に
  // SharedPreferencesへ値をセットしておき、pumpAndSettle()でゲートの解決を待つ。
  testWidgets('Home screen shows title and menu buttons', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'participant_id': 'test-participant'});
    await tester.pumpWidget(const WordPuzzleTrainerApp());
    await tester.pumpAndSettle();

    expect(find.text('英単語パズルトレーナー'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);
    expect(find.text('HISTORY'), findsOneWidget);
    expect(find.text('WORD BOOK'), findsOneWidget);
    expect(find.text('ENCYCLOPEDIA'), findsOneWidget);
  });

  testWidgets('Tapping START navigates to level select screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'participant_id': 'test-participant'});
    await tester.pumpWidget(const WordPuzzleTrainerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();

    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('Level 3'), findsOneWidget);
  });

  testWidgets('初回起動時は参加者ID入力画面が表示され、入力するとホーム画面に進む', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WordPuzzleTrainerApp());
    await tester.pumpAndSettle();

    // 参加者ID未保存なので、ホーム画面ではなく入力画面が出ているはず。
    expect(find.text('参加者IDを入力してください'), findsOneWidget);
    expect(find.text('START'), findsNothing);

    await tester.enterText(find.byType(TextFormField), '1234');
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();

    expect(find.text('START'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('participant_id'), '1234');
  });
}
