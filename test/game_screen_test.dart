import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:word_puzzle_trainer/screens/game_screen.dart';

import 'support/test_puzzles.dart';

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
      wrap(GameScreen(puzzle: twoPiecePuzzle, onAnswer: (_) {})),
    );

    expect(find.text('un'), findsOneWidget);
    expect(find.text('happy'), findsOneWidget);
    expect(find.text('Answer!'), findsOneWidget);
    expect(find.text('Menu'), findsOneWidget);
  });

  testWidgets('3ピースの単語でも全ピースが表示される', (tester) async {
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: threePiecePuzzle, onAnswer: (_) {})),
    );

    expect(find.text('com'), findsOneWidget);
    expect(find.text('bina'), findsOneWidget);
    expect(find.text('tion'), findsOneWidget);
  });

  testWidgets('解答欄の枠数は正解のピース数と同じ（2ピースなら2枠、3ピースなら3枠）', (tester) async {
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: twoPiecePuzzle, onAnswer: (_) {})),
    );
    expect(find.byKey(const ValueKey('slot_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_2')), findsNothing);

    // 実アプリは問題ごとにGameScreenを作り直す（キーが異なる）ので、同じようにする。
    await tester.pumpWidget(
      wrap(GameScreen(key: const ValueKey('three'), puzzle: threePiecePuzzle, onAnswer: (_) {})),
    );
    expect(find.byKey(const ValueKey('slot_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_2')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_3')), findsNothing);
  });

  testWidgets('選択肢には、単語データに用意された正解ピースとおとりピースが全て並ぶ', (tester) async {
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: twoPiecePuzzle, onAnswer: (_) {})),
    );

    // おとりはデータ側で固定されている（実行時に抽選しない）。
    expect(find.byType(Draggable<int>).evaluate().length, twoPiecePuzzle.presetChoices.length);
    for (final choice in twoPiecePuzzle.presetChoices) {
      expect(find.text(choice.text), findsOneWidget);
    }
  });

  testWidgets('2ピースの単語を正しく並べてAnswer!を押すとonAnswer(true)が呼ばれる', (tester) async {
    bool? result;
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: twoPiecePuzzle, onAnswer: (value) => result = value)),
    );

    await _dragPieceToSlot(tester, pieceText: 'un', slotIndex: 0);
    await _dragPieceToSlot(tester, pieceText: 'happy', slotIndex: 1);

    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('2ピースの単語で、おとりピースを置いてAnswer!を押すとonAnswer(false)が呼ばれる', (tester) async {
    bool? result;
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: twoPiecePuzzle, onAnswer: (value) => result = value)),
    );

    await _dragPieceToSlot(tester, pieceText: 'un', slotIndex: 0);

    // おとりピース（dis）をslot_1に置く。
    await _dragPieceToSlot(tester, pieceText: 'dis', slotIndex: 1);

    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('3ピースの単語を間違った位置に置いてAnswer!を押すとonAnswer(false)が呼ばれる', (tester) async {
    bool? result;
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: threePiecePuzzle, onAnswer: (value) => result = value)),
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
      wrap(GameScreen(puzzle: twoPiecePuzzle, onAnswer: (value) => result = value)),
    );

    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('配置済みピースをタップするとトレイに戻る', (tester) async {
    await tester.pumpWidget(
      wrap(GameScreen(puzzle: twoPiecePuzzle, onAnswer: (_) {})),
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
      wrap(GameScreen(puzzle: twoPiecePuzzle, onAnswer: (value) => result = value)),
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
      wrap(GameScreen(puzzle: twoPiecePuzzle, onAnswer: (value) => result = value)),
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
