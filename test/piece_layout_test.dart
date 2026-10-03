import 'package:flutter_test/flutter_test.dart';

import 'package:word_puzzle_trainer/models/puzzle_word.dart';
import 'package:word_puzzle_trainer/widgets/piece_geometry.dart';
import 'package:word_puzzle_trainer/widgets/piece_row_layout.dart';
import 'package:word_puzzle_trainer/widgets/puzzle_piece_shape.dart';

PieceFit _fit(String name, String text) =>
    PieceFit.of('assets/puzzle_pieces_v3/$name.png', text);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ピース形状データ', () {
    test('本体・伸ばせる列が画像の内側に収まっている', () {
      for (final entry in kPieceGeometry.entries) {
        final g = entry.value;
        expect(g.bodyLeft, greaterThanOrEqualTo(0), reason: entry.key);
        expect(g.bodyRight, lessThanOrEqualTo(g.width), reason: entry.key);
        expect(g.bodyTop, greaterThanOrEqualTo(0), reason: entry.key);
        expect(g.bodyBottom, lessThanOrEqualTo(g.height), reason: entry.key);
        if (g.stretchable) {
          expect(g.stretchLeft, greaterThan(g.bodyLeft), reason: entry.key);
          expect(g.stretchRight, lessThan(g.bodyRight), reason: entry.key);
          expect(g.stretchRight, greaterThan(g.stretchLeft), reason: entry.key);
        }
      }
    });

    test('出題で使う形（1番・3番）は、全ての役割で横に伸ばせる', () {
      for (final name in ['pre', 'stem_g', 'stem_y', 'suf']) {
        for (final k in [1, 3]) {
          expect(kPieceGeometry['${name}_$k']!.stretchable, isTrue, reason: '${name}_$k');
        }
      }
    });
  });

  group('文字の長さに合わせた横の伸び', () {
    test('短い文字は伸びず、長い文字ほど本体が広がる', () {
      final short = _fit('stem_g_1', 'a');
      final long = _fit('stem_g_1', 'unfortunate');
      expect(short.extra, 0);
      expect(long.extra, greaterThan(0));
      expect(long.bodyWidth, greaterThan(short.bodyWidth));
      // 伸ばした後の文字領域が、文字の幅＋左右の余白ちょうど。
      expect(long.textSpan,
          closeTo(measurePieceLabelWidth('unfortunate') + 2 * kLabelPadding, 0.001));
    });

    test('全問題の全ピースで、文字がピースの文字領域に収まる（ピースが文字を隠さない）', () async {
      final byLevel = await WordRepository.loadByLevel();
      for (final word in [for (final l in byLevel.values) ...l]) {
        for (final c in word.presetChoices) {
          final fit = PieceFit.of(c.assetPath, c.text);
          expect(fit.textSpan,
              greaterThanOrEqualTo(measurePieceLabelWidth(c.text) + 2 * kLabelPadding - 0.001),
              reason: '${word.id}: ${c.text}');
          // 文字の中心は本体の内側にある。
          expect(fit.textCenter.dx, greaterThan(fit.geometry.bodyLeftPx));
          expect(fit.textCenter.dx, lessThan(fit.geometry.bodyLeftPx + fit.bodyWidth));
        }
      }
    });
  });

  group('解答欄の並べ方', () {
    final fits = [_fit('pre_1', 'un'), _fit('stem_g_1', 'fortunate'), _fit('suf_1', 'ly')];
    final metrics = RowMetrics.of(fits);

    test('空欄は標準の大きさで並ぶ', () {
      final layout = layoutRow([null, null, null], metrics);
      for (var i = 0; i < 3; i++) {
        expect(layout.slots[i].bodyWidth, kEmptySlotBodyWidth);
        expect(layout.slots[i].bodyLeft,
            closeTo(metrics.leftPad + i * kEmptySlotBodyWidth, 0.001));
        expect(layout.slots[i].pieceTop, isNull);
      }
    });

    test('隣り合うスロットは本体どうしがぴったり接する（隙間も重なりもない）', () {
      final layout = layoutRow(fits, metrics);
      for (var i = 0; i < 2; i++) {
        final a = layout.slots[i], b = layout.slots[i + 1];
        expect(b.bodyLeft, closeTo(a.bodyLeft + a.bodyWidth, 0.001));
      }
      expect(layout.slots[1].bodyWidth, closeTo(fits[1].bodyWidth, 0.001));
    });

    test('長いピースを置くと、右隣以降がその伸びたぶんだけ押し出される', () {
      final empty = layoutRow([null, null, null], metrics);
      final placed = layoutRow([null, fits[1], null], metrics);
      expect(placed.slots[2].bodyLeft - empty.slots[2].bodyLeft,
          closeTo(fits[1].bodyWidth - kEmptySlotBodyWidth, 0.001));
      expect(placed.slots[0].bodyLeft, empty.slots[0].bodyLeft);
    });

    test('隣り合うピースは継ぎ目の上端の角が同じ高さに合う', () {
      final layout = layoutRow(fits, metrics);
      for (var i = 0; i < 2; i++) {
        final leftCorner = layout.slots[i].pieceTop! + fits[i].geometry.rightTopPx;
        final rightCorner = layout.slots[i + 1].pieceTop! + fits[i + 1].geometry.leftTopPx;
        expect(rightCorner, closeTo(leftCorner, 0.001));
      }
    });

    test('ピースが解答欄の高さの外にはみ出さない', () async {
      final byLevel = await WordRepository.loadByLevel();
      for (final word in [for (final l in byLevel.values) ...l]) {
        final all = [for (final c in word.presetChoices) PieceFit.of(c.assetPath, c.text)];
        final m = RowMetrics.of(all);
        // 先頭3枚・末尾3枚を並べた、代表的な2通りで調べる。
        for (final trio in [all.take(3).toList(), all.reversed.take(3).toList()]) {
          final layout = layoutRow(trio, m);
          for (var i = 0; i < trio.length; i++) {
            final top = layout.slots[i].pieceTop!;
            expect(top, greaterThanOrEqualTo(-0.001), reason: word.id);
            expect(top + trio[i].height, lessThanOrEqualTo(m.height + 0.001), reason: word.id);
          }
        }
      }
    });

    test('継ぎ目で出っ張りを持つ側のピースが手前に描かれる', () {
      // 1番: 前置・語幹とも右側に出っ張り → 左が手前（描画は右から先）
      expect(layoutRow(fits, metrics).paintOrder, [2, 1, 0]);

      // 3番: 語幹・後置が左側に出っ張り → 右が手前（描画は左から先）
      final k3 = [_fit('pre_3', 'un'), _fit('stem_g_3', 'fortunate'), _fit('suf_3', 'ly')];
      expect(layoutRow(k3, RowMetrics.of(k3)).paintOrder, [0, 1, 2]);
    });
  });
}
