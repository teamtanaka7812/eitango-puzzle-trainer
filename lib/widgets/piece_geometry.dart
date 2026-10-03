import 'dart:math';

import 'piece_geometry.g.dart';

export 'piece_geometry.g.dart' show kPiecePxPerUnit, kPieceGeometry;

/// ピース 1 枚の見た目の大きさの基準: SVG 原本の 1 単位 (約 1mm) が画面上で
/// 何論理ピクセルになるか。本体(四角い部分)は約 66×74 単位なので、この値で
/// 表示上の本体サイズが決まる。小学生にも読みやすい文字サイズ(20px)に
/// 合わせて調整する。
const double kUnitPx = 1.0;

/// ピースの文字の左右に確保する余白 (px)。
const double kLabelPadding = 10;

/// 隣のピースとの継ぎ目の形。
enum PieceConnector { tab, socket, flat }

/// `tools/piece_exporter` が SVG 原本から測った、ピース画像 1 枚ぶんの形状情報。
/// 長さは全て PNG 上のピクセル (1 単位 = [kPiecePxPerUnit] px)。
///
/// 「本体」は四角い部分、「継ぎ目」は左右の隣のピースと接する辺。隣のピース
/// どうしは、本体の左右の端をぴったり突き合わせて並べると、出っ張り(tab)と
/// 凹み(socket)がかみ合う。
class PieceGeometry {
  const PieceGeometry({
    required this.width,
    required this.height,
    required this.bodyLeft,
    required this.bodyRight,
    required this.bodyTop,
    required this.bodyBottom,
    required this.stretchable,
    required this.stretchLeft,
    required this.stretchRight,
    required this.insetLeft,
    required this.insetRight,
    required this.leftConnector,
    required this.rightConnector,
    required this.leftTop,
    required this.rightTop,
    required this.leftBottom,
    required this.rightBottom,
  });

  final int width, height;

  /// 本体の矩形 (右・下は含まない端)。出っ張り・凹みは含まない。
  final int bodyLeft, bodyRight, bodyTop, bodyBottom;

  /// 絵を崩さずに横へ引き伸ばせる列 [stretchLeft, stretchRight)。
  final bool stretchable;
  final int stretchLeft, stretchRight;

  /// 文字を置けない、本体の左右端からの距離 (凹みの深さ)。
  final int insetLeft, insetRight;

  final PieceConnector leftConnector, rightConnector;

  /// 左右の継ぎ目の上端・下端の高さ。隣のピースと継ぎ目の角を合わせるのに使う。
  final int leftTop, rightTop, leftBottom, rightBottom;

  /// PNG のピクセルを論理ピクセルに直す倍率。
  static const double scale = kUnitPx / kPiecePxPerUnit;

  double get widthPx => width * scale;
  double get heightPx => height * scale;
  double get bodyLeftPx => bodyLeft * scale;
  double get bodyWidthPx => (bodyRight - bodyLeft) * scale;
  double get bodyHeightPx => (bodyBottom - bodyTop) * scale;
  double get leftTopPx => leftTop * scale;
  double get rightTopPx => rightTop * scale;

  /// 右側(本体の右端より外)にはみ出している幅 (出っ張り・光彩)。
  double get rightOverhangPx => (width - bodyRight) * scale;

  /// 文字を置ける、本体の中の幅 (引き伸ばす前)。
  double get textSpanPx => (bodyRight - bodyLeft - insetLeft - insetRight) * scale;

  /// 幅 [labelWidth] の文字を余白つきで収めるために、横へ伸ばす量 (px)。
  /// 伸ばせない形のピースは 0 (文字が収まらない場合は呼び出し側で縮小する)。
  double extraFor(double labelWidth) {
    if (!stretchable) return 0;
    return max(0.0, labelWidth + 2 * kLabelPadding - textSpanPx);
  }
}

/// `assets/puzzle_pieces_v3/stem_g_1.png` のようなパスから形状を引く。
/// 未知の画像なら null。
PieceGeometry? pieceGeometryOf(String assetPath) {
  final slash = assetPath.lastIndexOf('/');
  final file = assetPath.substring(slash + 1);
  final dot = file.lastIndexOf('.');
  final name = dot == -1 ? file : file.substring(0, dot);
  return kPieceGeometry[name];
}
