import 'dart:math';

import 'puzzle_piece_shape.dart';

/// 空欄のスロットの本体の幅・高さ。ピースを置く前は、ここで決めた標準の大きさで
/// 表示する (正解ピースの長さを先に反映すると、答えの長さがヒントになるため)。
final double kEmptySlotBodyWidth = 66 * kUnitPx;
final double kEmptySlotBodyHeight = 74 * kUnitPx;

/// 1 問のあいだ変わらない、解答欄の外枠の寸法。問題に登場する全ピースの
/// 形から求めるので、ピースを置いたり外したりしても解答欄の高さは動かない。
class RowMetrics {
  RowMetrics._({
    required this.leftPad,
    required this.rightPad,
    required this.topPad,
    required this.height,
  });

  factory RowMetrics.of(Iterable<PieceFit> fits) {
    var leftPad = 0.0, rightPad = 0.0, above = 0.0, below = 0.0, step = 0.0;
    for (final f in fits) {
      final g = f.geometry;
      leftPad = max(leftPad, g.bodyLeftPx);
      rightPad = max(rightPad, g.rightOverhangPx);
      above = max(above, g.leftTopPx);
      below = max(below, g.heightPx - g.leftTopPx);
      // 継ぎ目の角を合わせて並べると、1枚進むごとに、そのピースの上の辺の
      // 傾き(左右の継ぎ目の高さの差)ぶんだけ次のピースの高さがずれる。
      step = max(step, (g.rightTopPx - g.leftTopPx).abs());
    }
    // 3 枚並ぶとずれが 2 回重なりうる (上下どちらにも)。
    final slack = step * 2;
    return RowMetrics._(
      leftPad: leftPad,
      rightPad: rightPad,
      topPad: above + slack,
      height: above + below + slack * 2,
    );
  }

  /// 本体の左端より左にはみ出す幅 (左の出っ張り)。
  final double leftPad;
  final double rightPad;

  /// 基準の高さ (本体の上端をここに合わせる)。
  final double topPad;
  final double height;
}

/// 解答欄の 1 スロット分の配置。
class SlotPlacement {
  const SlotPlacement({
    required this.bodyLeft,
    required this.bodyWidth,
    required this.pieceTop,
  });

  /// 本体の左端 (行の左端 = leftPad 込みの座標)。
  final double bodyLeft;

  /// 本体の幅。空欄なら [kEmptySlotBodyWidth]。
  final double bodyWidth;

  /// ピース画像の上端 (空欄なら null)。
  final double? pieceTop;
}

class RowLayout {
  RowLayout({
    required this.slots,
    required this.paintOrder,
    required this.bodyTotalWidth,
    required this.width,
  });

  final List<SlotPlacement> slots;

  /// 奥から手前への描画順 (スロット番号)。
  final List<int> paintOrder;

  /// 本体どうしを突き合わせた全体の幅 (背景の幅)。
  final double bodyTotalWidth;

  /// 左右の出っ張りを含む、解答欄全体の幅。
  final double width;
}

/// 解答欄の配置を求める。[fits] は各スロットに置かれたピース (空欄は null)。
///
/// - 横: 本体の左右の端をぴったり突き合わせて並べる。出っ張りと凹みはこれで
///   かみ合い、隙間も重なりもできない。ピースを置くとその幅(文字の長さに応じて
///   伸びた幅)ぶんだけ、右隣以降が押し出される。
/// - 縦: 隣り合うピースどうしは継ぎ目の上端の角を合わせる。隣が空欄のときは
///   基準の高さに本体の上端を合わせる。
/// - 重なり: 隣との継ぎ目で出っ張りを持つ方を手前に描く。
RowLayout layoutRow(List<PieceFit?> fits, RowMetrics metrics) {
  final slots = <SlotPlacement>[];
  var x = metrics.leftPad;
  double? previousTop;
  PieceFit? previous;
  for (final fit in fits) {
    double? top;
    if (fit != null) {
      final own = fit.geometry;
      if (previous != null && previousTop != null) {
        top = previousTop + previous.geometry.rightTopPx - own.leftTopPx;
      } else {
        top = metrics.topPad - own.leftTopPx;
      }
    }
    final bodyWidth = fit?.bodyWidth ?? kEmptySlotBodyWidth;
    slots.add(SlotPlacement(bodyLeft: x, bodyWidth: bodyWidth, pieceTop: top));
    x += bodyWidth;
    previous = fit;
    previousTop = top;
  }
  final bodyTotal = x - metrics.leftPad;
  return RowLayout(
    slots: slots,
    paintOrder: _paintOrder(fits),
    bodyTotalWidth: bodyTotal,
    width: x + metrics.rightPad,
  );
}

List<int> _paintOrder(List<PieceFit?> fits) {
  // behind[i] = i より奥に描くべきスロット
  final behind = {for (var i = 0; i < fits.length; i++) i: <int>{}};
  for (var i = 0; i + 1 < fits.length; i++) {
    final left = fits[i], right = fits[i + 1];
    if (left == null || right == null) continue;
    final leftOnTop = left.geometry.rightConnector == PieceConnector.tab ||
        right.geometry.leftConnector != PieceConnector.tab;
    if (leftOnTop) {
      behind[i]!.add(i + 1);
    } else {
      behind[i + 1]!.add(i);
    }
  }
  final order = <int>[];
  final done = <int>{};
  while (order.length < fits.length) {
    for (var i = 0; i < fits.length; i++) {
      if (done.contains(i)) continue;
      if (behind[i]!.every(done.contains)) {
        order.add(i);
        done.add(i);
      }
    }
  }
  return order;
}
