import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:word_puzzle_trainer/screens/level_play_screen.dart';

// Level 1 は assets/data/words.json の順で、以下の14問（q_listの10問→従来の4問）。
const _level1Words = <List<String>>[
  ['il', 'legal'],
  ['develop', 'ment'],
  ['un', 'fortunate', 'ly'],
  ['re', 'appear', 'ance'],
  ['in', 'dependent', 'ly'],
  ['re', 'consider', 'ation'],
  ['un', 'believe', 'able'],
  ['un', 'comfort', 'able'],
  ['dis', 'agree', 'ment'],
  ['un', 'depend', 'able'],
  ['un', 'happy'],
  ['re', 'write'],
  ['help', 'ful'],
  ['care', 'less'],
];

Future<void> _dragPieceToSlot(
  WidgetTester tester, {
  required String pieceText,
  required int slotIndex,
}) async {
  final pieceFinder = find.text(pieceText);
  final slotFinder = find.byKey(ValueKey('slot_$slotIndex'));

  final start = tester.getCenter(pieceFinder);
  final end = tester.getCenter(slotFinder);

  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveTo(end);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pumpAndSettle();
}

/// 結果画面は羊の画像を追加したことで縦に長くなり、テストの仮想画面サイズでは
/// ボタンが画面外にはみ出すことがあるため、タップ前にスクロールして表示させる。
Future<void> _tapButton(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Level 1（14問）を最後まで正しく解くとレベル選択画面（前の画面）に戻る', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LevelPlayScreen(level: 1)),
                ),
                child: const Text('レベル1へ'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('レベル1へ'));
    await tester.pumpAndSettle();

    for (var i = 0; i < _level1Words.length; i++) {
      expect(find.textContaining('${i + 1} / ${_level1Words.length}'), findsOneWidget);

      final pieces = _level1Words[i];
      for (var slot = 0; slot < pieces.length; slot++) {
        await _dragPieceToSlot(tester, pieceText: pieces[slot], slotIndex: slot);
      }
      await tester.tap(find.text('Answer!'));
      await tester.pumpAndSettle();
      expect(find.text('Correct!'), findsOneWidget);

      final isLast = i == _level1Words.length - 1;
      await _tapButton(tester, isLast ? 'レベル選択に戻る' : '次の問題へ');
    }

    // レベル選択画面の代わりに置いた「レベル1へ」ボタンの画面まで戻ってきているはず。
    expect(find.text('レベル1へ'), findsOneWidget);
  });

  testWidgets('「もう一度挑戦する」を押すと同じ問題番号のままリセットされる', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LevelPlayScreen(level: 1)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1 / ${_level1Words.length}'), findsOneWidget);

    // わざと間違えて Incorrect にする（1問目は il + legal の2ピース）。
    await _dragPieceToSlot(tester, pieceText: 'il', slotIndex: 1);
    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect!'), findsOneWidget);

    await _tapButton(tester, 'もう一度挑戦する');

    // 同じ1問目のまま。
    expect(find.textContaining('1 / ${_level1Words.length}'), findsOneWidget);

    // 盤面がリセットされていれば、何も置かずにAnswer!を押すと必ずIncorrectになる。
    await tester.tap(find.text('Answer!'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect!'), findsOneWidget);
  });
}
