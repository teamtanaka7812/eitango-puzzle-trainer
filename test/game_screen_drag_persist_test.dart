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

Offset _globalTopLeftOf(WidgetTester tester, String pieceText) {
  final finder = find.ancestor(of: find.text(pieceText), matching: find.byType(Draggable<int>));
  return tester.renderObject<RenderBox>(finder).localToGlobal(Offset.zero);
}

/// 現在トレイに散らばっている全ピース（おとり含む）の中心座標一覧。
List<Offset> _currentPieceCenters(WidgetTester tester) {
  return find.byType(Draggable<int>).evaluate().map((element) {
    final box = element.renderObject! as RenderBox;
    return box.localToGlobal(box.size.center(Offset.zero));
  }).toList();
}

/// おとりピースはランダムな位置に散らばっているため、固定座標をドロップ先に
/// 選ぶと別のピースとたまたま重なることがある。他のどのピースからも十分離れた
/// 場所を候補から選ぶことで、意図しないピースを掴んでしまうのを避ける。
Offset _pickClearSpot(WidgetTester tester, Offset areaTopLeft, Size areaSize) {
  final others = _currentPieceCenters(tester);
  const fractions = [0.1, 0.3, 0.5, 0.7, 0.9];
  final candidates = <Offset>[
    for (final fy in fractions)
      for (final fx in fractions) areaTopLeft + Offset(areaSize.width * fx, areaSize.height * fy),
  ];
  for (final candidate in candidates) {
    if (others.every((o) => (o - candidate).distance > 160)) {
      return candidate;
    }
  }
  // 十分離れた候補が見つからない場合は、最も混雑していない候補を選ぶ。
  candidates.sort((a, b) {
    final da = others.map((o) => (o - a).distance).fold(double.infinity, (m, d) => d < m ? d : m);
    final db = others.map((o) => (o - b).distance).fold(double.infinity, (m, d) => d < m ? d : m);
    return db.compareTo(da);
  });
  return candidates.first;
}

void main() {
  testWidgets('選択肢エリア内でピースをドラッグすると、ドロップした場所にそのまま留まる',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(puzzle: _twoPiecePuzzle, onAnswer: (_) {})),
    );
    await tester.pumpAndSettle();

    final before = _globalTopLeftOf(tester, 'un');

    final areaBox =
        tester.renderObject<RenderBox>(find.byKey(const ValueKey('piece_tray_area')));
    final areaTopLeft = areaBox.localToGlobal(Offset.zero);
    final areaSize = areaBox.size;

    const grabOffset = Offset(30, 30);
    final dropTarget = _pickClearSpot(tester, areaTopLeft, areaSize);

    final gesture = await tester.startGesture(before + grabOffset);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(dropTarget);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    final after = _globalTopLeftOf(tester, 'un');
    final expectedTopLeft = dropTarget - grabOffset;

    // 元の位置には戻っていない（スナップバックしていない）。
    expect((after - before).distance, greaterThan(50));
    // ドロップした場所のすぐ近くに留まっている。
    expect((after - expectedTopLeft).distance, lessThan(70));

    // 続けてもう一度、別の場所へドラッグしても同様に留まるか確認する。
    final secondDropTarget = _pickClearSpot(tester, areaTopLeft, areaSize);
    final gesture2 = await tester.startGesture(after + grabOffset);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture2.moveTo(secondDropTarget);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture2.up();
    await tester.pumpAndSettle();

    final afterSecond = _globalTopLeftOf(tester, 'un');
    final expectedSecondTopLeft = secondDropTarget - grabOffset;
    expect((afterSecond - expectedSecondTopLeft).distance, lessThan(70));
  });
}
