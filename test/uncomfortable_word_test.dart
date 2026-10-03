import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:word_puzzle_trainer/models/puzzle_word.dart';
import 'package:word_puzzle_trainer/screens/game_screen.dart';

Future<void> _dragToTarget(
  WidgetTester tester, {
  required Finder from,
  required Finder to,
}) async {
  await tester.ensureVisible(from);
  await tester.pumpAndSettle();
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
  testWidgets('advocate（3ピース単語）が実データ通り3ピースで表示され、正しく解ける', (tester) async {
    final byLevel = await WordRepository.loadByLevel();
    final level3 = byLevel[3]!;
    final advocate = level3.firstWhere((w) => w.id == 'advocate');

    // ad + voc + ate の3ピースであること。
    // （2026年9月、13単語を3ピース→2ピースに統合した際、それまでこの回帰
    // テストが使っていた「uncomfortable」も2ピースになったため、引き続き
    // 3ピースのままの単語に差し替えた。テストの目的（3枠の解答欄が正しく
    // 表示され、3ピースともドラッグで正しく配置できること）は変わらない。）
    expect(advocate.parts.length, 3);
    expect(advocate.parts.map((p) => p.text).toList(), ['ad', 'voc', 'ate']);

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(puzzle: advocate, onAnswer: (value) => result = value),
      ),
    );

    // 3ピースとも選択肢に表示されていること（2ピースのまま欠けたりしていないか）。
    expect(find.text('ad'), findsOneWidget);
    expect(find.text('voc'), findsOneWidget);
    expect(find.text('ate'), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot_2')), findsOneWidget);

    await _dragToTarget(tester, from: find.text('ad'), to: find.byKey(const ValueKey('slot_0')));
    await _dragToTarget(tester, from: find.text('voc'), to: find.byKey(const ValueKey('slot_1')));
    await _dragToTarget(tester, from: find.text('ate'), to: find.byKey(const ValueKey('slot_2')));

    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
