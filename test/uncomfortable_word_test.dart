import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:word_puzzle_trainer/models/puzzle_word.dart';
import 'package:word_puzzle_trainer/screens/game_screen.dart';

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

void main() {
  testWidgets('uncomfortable（Level3の3ピース単語）が実データ通り3ピースで表示され、正しく解ける', (tester) async {
    final byLevel = await WordRepository.loadByLevel();
    final level3 = byLevel[3]!;
    final uncomfortable = level3.firstWhere((w) => w.id == 'uncomfortable');

    // design書5.3の通り、un + comfort + able の3ピースであること。
    expect(uncomfortable.parts.length, 3);
    expect(uncomfortable.parts.map((p) => p.text).toList(), ['un', 'comfort', 'able']);

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(puzzle: uncomfortable, onAnswer: (value) => result = value),
      ),
    );

    // 3ピースとも選択肢に表示されていること（2ピースのまま欠けたりしていないか）。
    expect(find.text('un'), findsOneWidget);
    expect(find.text('comfort'), findsOneWidget);
    expect(find.text('able'), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_2')), findsOneWidget);

    await _dragToTarget(tester, from: find.text('un'), to: find.byKey(const ValueKey('slot_0')));
    await _dragToTarget(
        tester, from: find.text('comfort'), to: find.byKey(const ValueKey('slot_1')));
    await _dragToTarget(tester, from: find.text('able'), to: find.byKey(const ValueKey('slot_2')));

    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
