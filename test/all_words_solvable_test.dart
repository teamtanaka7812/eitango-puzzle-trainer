import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:word_puzzle_trainer/models/puzzle_word.dart';
import 'package:word_puzzle_trainer/screens/game_screen.dart';

/// 実データ（assets/data/words.json）の全問題が、画面上のドラッグ操作だけで
/// 正しく解けること。ピースの大きさ・並びは文字の長さで変わるため
/// （長い単語ほどピースが横に伸びる）、どの単語でもピースを掴んで解答欄に
/// 置けることを確かめる。
void main() {
  testWidgets('words.json の全単語を、ドラッグ操作で正しく解ける', (tester) async {
    final byLevel = await WordRepository.loadByLevel();
    final words = [for (final level in byLevel.keys.toList()..sort()) ...byLevel[level]!];
    expect(words, isNotEmpty);

    final failures = <String>[];
    for (final word in words) {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            key: ValueKey(word.id),
            puzzle: word,
            onAnswer: (value) => result = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var slot = 0; slot < word.parts.length; slot++) {
        final piece = find.text(word.parts[slot].text);
        final target = find.byKey(ValueKey('slot_$slot'));
        // 画面の狭いテスト環境では、選択肢エリアを縦にスクロールしないと届かない
        // ピースがある。
        await tester.ensureVisible(piece);
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(tester.getCenter(piece.first));
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.moveTo(tester.getCenter(target));
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.up();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Answer!'));
      await tester.pumpAndSettle();
      if (result != true) failures.add(word.id);
    }
    expect(failures, isEmpty, reason: '解けなかった単語: $failures');
  });
}
