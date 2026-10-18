import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:word_puzzle_trainer/main.dart';
import 'package:word_puzzle_trainer/models/puzzle_word.dart';
import 'package:word_puzzle_trainer/screens/result_screen.dart';
import 'package:word_puzzle_trainer/services/auth_service.dart';
import 'package:word_puzzle_trainer/services/learning_record_service.dart';
import 'package:word_puzzle_trainer/widgets/recording_notices.dart';

import 'recording_service_test.dart' show FakeAuthBackend, FakeRecordBackend;

const _puzzle = PuzzleWord(
  id: 'test',
  word: 'unhappy',
  level: 1,
  parts: [WordPiecePart(text: 'un'), WordPiecePart(text: 'happy')],
  meaning: '不幸な',
  exampleEn: 'It is an example.',
  exampleJa: '例文です。',
  presetChoices: [],
);

void main() {
  late FakeAuthBackend auth;
  late FakeRecordBackend records;

  setUp(() {
    SharedPreferences.setMockInitialValues({'participant_id': 'Test-0001'});
    auth = FakeAuthBackend();
    records = FakeRecordBackend();
    AuthService.resetForTest(auth);
    LearningRecordService.resetForTest(records);
  });

  Future<void> openHome(WidgetTester tester) async {
    await tester.pumpWidget(const WordPuzzleTrainerApp());
    await tester.pumpAndSettle();
  }

  group('ログイン失敗の案内（ホーム画面）', () {
    testWidgets('ログインできているときは、案内は出ない', (tester) async {
      auth.uid = 'uid-1';
      await AuthService.ensureSignedIn();
      await openHome(tester);
      expect(find.byKey(const ValueKey('auth_banner')), findsNothing);
      expect(find.text(kAuthFailedTitle), findsNothing);
    });

    testWidgets('失敗すると案内と「もう一度」が出て、押して成功すると消える', (tester) async {
      auth.failNext = true;
      await AuthService.ensureSignedIn();
      await openHome(tester);

      expect(find.text(kAuthFailedTitle), findsOneWidget);
      expect(find.text(kAuthFailedBody), findsOneWidget);
      expect(find.text(kAuthRetryLabel), findsOneWidget);
      // ゲームは続けられる（STARTなどのボタンはそのまま使える）
      expect(find.text('START'), findsOneWidget);

      auth.failNext = false;
      await tester.tap(find.text(kAuthRetryLabel));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth_banner')), findsNothing);
      expect(AuthService.status.value, AuthStatus.signedIn);
    });

    testWidgets('「もう一度」を押してもまだ失敗なら、案内が残り「まだつながりません。」が付く', (tester) async {
      auth.failNext = true;
      await AuthService.ensureSignedIn();
      await openHome(tester);

      await tester.tap(find.text(kAuthRetryLabel));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth_banner')), findsOneWidget);
      expect(find.textContaining(kAuthStillFailed), findsOneWidget);
      expect(auth.calls, 2);
    });

    testWidgets('レベル選択画面にも同じ案内が出る', (tester) async {
      auth.failNext = true;
      await AuthService.ensureSignedIn();
      await openHome(tester);
      await tester.tap(find.text('START'));
      await tester.pumpAndSettle();
      expect(find.text('レベルをえらんでね'), findsOneWidget);
      expect(find.text(kAuthFailedTitle), findsOneWidget);
    });
  });

  group('保存失敗の案内', () {
    testWidgets('失敗すると小さな案内が1回だけ出て、続けて失敗しても繰り返さない', (tester) async {
      auth.uid = 'uid-1';
      records.mode = 'fail';
      await openHome(tester);

      await tester.runAsync(() async {
        await LearningRecordService.recordAttempt(
          puzzle: _puzzle,
          isCorrect: true,
          startedAt: DateTime(2026, 10, 18),
          durationSeconds: 5,
          dragCount: 2,
        );
      });
      await tester.pump();
      expect(find.text(kSaveFailedNotice), findsOneWidget);

      // 案内が消えたあとで、続けて失敗しても、もう出ない。
      await tester.pump(const Duration(seconds: 8)); // 表示のアニメーションが終わる
      await tester.pump(const Duration(seconds: 8)); // 表示時間(7秒)が過ぎる
      await tester.pumpAndSettle();
      expect(find.text(kSaveFailedNotice), findsNothing);
      await tester.runAsync(() async {
        await LearningRecordService.recordAttempt(
          puzzle: _puzzle,
          isCorrect: false,
          startedAt: DateTime(2026, 10, 18),
          durationSeconds: 5,
          dragCount: 2,
        );
      });
      await tester.pump();
      expect(find.text(kSaveFailedNotice), findsNothing);
      expect(LearningRecordService.unsavedCount.value, 2);
    });
  });

  group('結果画面の「記録できなかった問題」', () {
    Future<void> openResult(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ResultScreen(puzzle: _puzzle, isCorrect: true, isLastWord: false),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('0問のときは何も表示しない', (tester) async {
      await openResult(tester);
      expect(find.byKey(const ValueKey('unsaved_count')), findsNothing);
      expect(find.textContaining('記録できなかった問題'), findsNothing);
    });

    testWidgets('1問以上あるときだけ「記録できなかった問題：N問」を表示し、数が変わると更新される',
        (tester) async {
      await openResult(tester);
      LearningRecordService.unsavedCount.value = 2;
      await tester.pump();
      expect(find.text('記録できなかった問題：2問'), findsOneWidget);

      LearningRecordService.unsavedCount.value = 0;
      await tester.pump();
      expect(find.textContaining('記録できなかった問題'), findsNothing);
    });
  });
}
