import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:word_puzzle_trainer/models/puzzle_word.dart';
import 'package:word_puzzle_trainer/screens/game_screen.dart';

const _twoPiecePuzzle = PuzzleWord(
  id: 'test-unhappy',
  word: 'unhappy',
  level: 1,
  parts: [
    WordPiecePart(text: 'un'),
    WordPiecePart(text: 'happy'),
  ],
  meaning: '不幸な',
  exampleEn: 'example sentence',
  exampleJa: '例文',
);

const _threePiecePuzzle = PuzzleWord(
  id: 'test-combination',
  word: 'combination',
  level: 1,
  parts: [
    WordPiecePart(text: 'com'),
    WordPiecePart(text: 'bina'),
    WordPiecePart(text: 'tion'),
  ],
  meaning: '結合',
  exampleEn: 'example sentence',
  exampleJa: '例文',
);

Future<void> _dragToTarget(
  WidgetTester tester, {
  required Finder from,
  required Finder to,
}) async {
  final start = tester.getCenter(from);
  final end = tester.getCenter(to);

  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveTo(end);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _dragPieceToSlot(
  WidgetTester tester, {
  required String pieceText,
  required int slotIndex,
}) async {
  await _dragToTarget(
    tester,
    from: find.text(pieceText),
    to: find.byKey(ValueKey('slot_$slotIndex')),
  );
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('2ピースの単語でも全ピースとボタンが表示される', (tester) async {
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: _twoPiecePuzzle, onAnswer: (_) {})),
    );

    expect(find.text('un'), findsOneWidget);
    expect(find.text('happy'), findsOneWidget);
    expect(find.text('Answer!'), findsOneWidget);
    expect(find.text('Menu'), findsOneWidget);
  });

  testWidgets('3ピースの単語でも全ピースが表示される', (tester) async {
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: _threePiecePuzzle, onAnswer: (_) {})),
    );

    expect(find.text('com'), findsOneWidget);
    expect(find.text('bina'), findsOneWidget);
    expect(find.text('tion'), findsOneWidget);
  });

  testWidgets('解答欄は単語のピース数によらず常に3枠（slot_0〜slot_2）表示される', (tester) async {
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: _twoPiecePuzzle, onAnswer: (_) {})),
    );

    expect(find.byKey(const ValueKey('slot_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_2')), findsOneWidget);
  });

  testWidgets('選択肢には正解ピースに加えて3〜4個のおとりピースが混ざる', (tester) async {
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: _twoPiecePuzzle, onAnswer: (_) {})),
    );

    final draggableCount = find.byType(Draggable<int>).evaluate().length;
    // 正解2ピース + おとり3〜4個 = 5〜6個。
    expect(draggableCount, greaterThanOrEqualTo(5));
    expect(draggableCount, lessThanOrEqualTo(6));
  });

  testWidgets('2ピースの単語を正しく並べてAnswer!を押すとonAnswer(true)が呼ばれる', (tester) async {
    bool? result;
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: _twoPiecePuzzle, onAnswer: (value) => result = value)),
    );

    await _dragPieceToSlot(tester, pieceText: 'un', slotIndex: 0);
    await _dragPieceToSlot(tester, pieceText: 'happy', slotIndex: 1);

    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('2ピースの単語で、余った3枠目に何か置いてしまうとonAnswer(false)が呼ばれる', (tester) async {
    bool? result;
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: _twoPiecePuzzle, onAnswer: (value) => result = value)),
    );

    await _dragPieceToSlot(tester, pieceText: 'un', slotIndex: 0);
    await _dragPieceToSlot(tester, pieceText: 'happy', slotIndex: 1);

    // おとりピース（トレイに残っている、un/happy以外のどれか）を、余っているslot_2に置いてしまう。
    final decoyFinder = find
        .descendant(
          of: find.byKey(const ValueKey('piece_tray_area')),
          matching: find.byType(Draggable<int>),
        )
        .first;
    await _dragToTarget(tester, from: decoyFinder, to: find.byKey(const ValueKey('slot_2')));

    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('3ピースの単語を間違った位置に置いてAnswer!を押すとonAnswer(false)が呼ばれる', (tester) async {
    bool? result;
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: _threePiecePuzzle, onAnswer: (value) => result = value)),
    );

    // わざと com をスロット2（tionの位置）に置く。
    await _dragPieceToSlot(tester, pieceText: 'com', slotIndex: 2);

    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('何も置かずにAnswer!を押すとonAnswer(false)が呼ばれる', (tester) async {
    bool? result;
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: _twoPiecePuzzle, onAnswer: (value) => result = value)),
    );

    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('配置済みピースをタップするとトレイに戻る', (tester) async {
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: _twoPiecePuzzle, onAnswer: (_) {})),
    );

    await _dragPieceToSlot(tester, pieceText: 'un', slotIndex: 0);
    expect(find.text('un'), findsOneWidget);

    await tester.tap(find.text('un'));
    await tester.pumpAndSettle();

    expect(find.text('un'), findsOneWidget);
  });

  testWidgets('配置済みピースをドラッグしてトレイに戻すこともできる', (tester) async {
    bool? result;
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: _twoPiecePuzzle, onAnswer: (value) => result = value)),
    );

    await _dragPieceToSlot(tester, pieceText: 'un', slotIndex: 0);
    await _dragPieceToSlot(tester, pieceText: 'happy', slotIndex: 1);

    // happy をドラッグでトレイに戻す。
    await _dragToTarget(
      tester,
      from: find.text('happy'),
      to: find.byKey(const ValueKey('piece_tray_area')),
    );

    // slot_1が空になったはずなので、Answer!はfalseになる。
    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('解答欄の外側であれば、選択肢エリア以外にドロップしても選択肢に戻る', (tester) async {
    bool? result;
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: _twoPiecePuzzle, onAnswer: (value) => result = value)),
    );

    await _dragPieceToSlot(tester, pieceText: 'un', slotIndex: 0);
    await _dragPieceToSlot(tester, pieceText: 'happy', slotIndex: 1);

    // happy を、選択肢エリアではなく画面上部のタイトル文字の位置にドロップする。
    await _dragToTarget(
      tester,
      from: find.text('happy'),
      to: find.text('単語を組み立てよう'),
    );

    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
