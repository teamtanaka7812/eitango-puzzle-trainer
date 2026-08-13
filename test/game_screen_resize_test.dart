import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:word_puzzle_trainer/models/puzzle_word.dart';
import 'package:word_puzzle_trainer/screens/game_screen.dart';
import 'package:word_puzzle_trainer/widgets/puzzle_piece_shape.dart';

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

/// 選択肢エリア（piece_tray_area）に対する、指定ピースの相対位置（0.0〜1.0）を求める。
Offset _relativePositionOf(WidgetTester tester, String pieceText) {
  final areaBox = tester.renderObject<RenderBox>(find.byKey(const ValueKey('piece_tray_area')));
  final areaTopLeft = areaBox.localToGlobal(Offset.zero);
  final areaSize = areaBox.size;

  final pieceFinder = find.ancestor(
    of: find.text(pieceText),
    matching: find.byType(Draggable<int>),
  );
  final pieceBox = tester.renderObject<RenderBox>(pieceFinder);
  final pieceTopLeft = pieceBox.localToGlobal(Offset.zero);

  final relative = pieceTopLeft - areaTopLeft;
  final maxX = areaSize.width - kPieceSlotWidth;
  final maxY = areaSize.height - kPieceSlotHeight;
  return Offset(relative.dx / maxX, relative.dy / maxY);
}

void main() {
  testWidgets('ウィンドウサイズが変わっても、ピースの相対位置（盤面に対する割合）は保たれる',
      (tester) async {
    addTearDown(() => tester.view.resetPhysicalSize());

    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MaterialApp(home: GameScreen(puzzle: _twoPiecePuzzle, onAnswer: (_) {})),
    );
    await tester.pumpAndSettle();

    final beforeUn = _relativePositionOf(tester, 'un');
    final beforeHappy = _relativePositionOf(tester, 'happy');

    // ウィンドウサイズを変更する。
    tester.view.physicalSize = const Size(1400, 700);
    await tester.pumpAndSettle();

    final afterUn = _relativePositionOf(tester, 'un');
    final afterHappy = _relativePositionOf(tester, 'happy');

    // 割合（相対位置）はリサイズ前後でほぼ変わらないはず（許容誤差つき）。
    expect(afterUn.dx, closeTo(beforeUn.dx, 0.02));
    expect(afterUn.dy, closeTo(beforeUn.dy, 0.02));
    expect(afterHappy.dx, closeTo(beforeHappy.dx, 0.02));
    expect(afterHappy.dy, closeTo(beforeHappy.dy, 0.02));
  });
}
