import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// ピースウィジェット全体のサイズ（解答欄・選択肢エリアで共通の固定枠）。
/// 実物画像は1枚ごとに縦横比が異なるため、この枠の中に縦横比を保ったまま
/// 中央配置で表示する（枠いっぱいに引き伸ばして形を歪めることはしない）。
///
/// ピース画像そのものは [kPieceBoxWidth] × [kPieceBoxHeight]（解答欄の枠1個分）
/// に収まるサイズで表示する。ウィジェット全体の当たり判定・レイアウト間隔は
/// それより一回り大きい [kPieceSlotWidth] × [kPieceSlotHeight] を使う。
const double kPieceBoxWidth = 92;
const double kPieceBoxHeight = 92;
const double _tabDepth = 16;
const double kPieceSlotWidth = kPieceBoxWidth + _tabDepth * 2;
const double kPieceSlotHeight = kPieceBoxHeight + _tabDepth * 2;

/// ランダムにおとり・画像を選ぶ問題（`choices`を持たない問題）で使う画像素材。
/// `01.png`〜`06.png`は1種類の凹凸パターンを6色に塗り分けたセットで、型が
/// 全て同じため、この中からどれを選んで並べても必ずかみ合う。
///
/// `assets/puzzle_pieces_v2`には他に、1枚ごとに凹凸の形が異なる28枚
/// （`01001`〜`02014`）のセットもあるが、ランダムに選ぶと隣同士がかみ合わない
/// ことが分かったため、ランダム選択にはこちらを使わない（2026年時点の決定）。
/// その28枚は、あらかじめ人手でかみ合う組み合わせを選んだ`choices`つきの
/// 問題（`assets/data/words.json`のLevel 1先頭10問など）でのみ使う。
const List<String> kBasicPieceAssets = [
  'assets/puzzle_pieces_v2/01.png',
  'assets/puzzle_pieces_v2/02.png',
  'assets/puzzle_pieces_v2/03.png',
  'assets/puzzle_pieces_v2/04.png',
  'assets/puzzle_pieces_v2/05.png',
  'assets/puzzle_pieces_v2/06.png',
];

/// 画像を[kPieceBoxWidth]×[kPieceBoxHeight]の枠に実際に表示したとき、絵柄
/// （不透明部分）が左右の枠端からどれだけ離れているか（px）と、その上に
/// 重ねる文字の中心位置（枠の左端からのpx）。
///
/// 解答欄でピース同士を重ねて表示する際、隣り合うピースの[right]と[left]の
/// 合計ぶんだけ枠を重ねれば、絵柄同士がちょうど接する（重ならない・隙間も
/// できない）重なり幅になる。画像の縦横比によって値は大きく異なる
/// （例：横長で枠いっぱいに表示される画像は0に近く、縦長で左右に大きな
/// 余白ができる画像は15px前後になる）。[textCenterX]は、それより
/// さらに重ねて文字を隠さないようにする範囲を計算する際に使う。
class PieceHorizontalMargins {
  const PieceHorizontalMargins({
    required this.left,
    required this.right,
    required this.textCenterX,
  });

  final double left;
  final double right;
  final double textCenterX;
}

/// 画像本体と、その上に文字を重ねるときに必要な情報をまとめたもの。
///
/// - [textColor] : 画像の不透明部分の平均輝度から自動判定した読みやすい文字色
///   （明るい背景には濃い色、暗め・鮮やかな背景には白）。
/// - [textAlignment] : 文字を置く位置。画像の四角い範囲の中心ではなく、
///   実際にピースが写っている（透明でない）部分の中心に文字が来るように、
///   不透明ピクセルの重心から計算しておく（[kPieceBoxWidth]×[kPieceBoxHeight]
///   の枠にBoxFit.containで収めたときの実際の表示位置を考慮済み）。
/// - [margins] : 解答欄でのピース間オーバーラップ計算に使う、絵柄と枠端との
///   左右の距離。
class _LoadedPieceAsset {
  const _LoadedPieceAsset({
    required this.image,
    required this.textColor,
    required this.textAlignment,
    required this.margins,
  });

  final ui.Image image;
  final Color textColor;
  final Alignment textAlignment;
  final PieceHorizontalMargins margins;
}

final Map<String, Future<_LoadedPieceAsset>> _pieceAssetCache = {};

Future<_LoadedPieceAsset> _loadPieceAsset(String assetPath) {
  return _pieceAssetCache.putIfAbsent(assetPath, () async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final analysis = await _analyzePieceImage(image);
    final containMetrics = _containMetrics(imageWidth: image.width, imageHeight: image.height);
    final textAlignment = _computeTextAlignment(
      metrics: containMetrics,
      contentCenterFraction: analysis.contentCenterFraction,
    );
    final margins = PieceHorizontalMargins(
      left: containMetrics.boxOffsetX + analysis.contentMinXFraction * containMetrics.displayedWidth,
      right: kPieceBoxWidth -
          (containMetrics.boxOffsetX + analysis.contentMaxXFraction * containMetrics.displayedWidth),
      textCenterX:
          containMetrics.boxOffsetX + analysis.contentCenterFraction.dx * containMetrics.displayedWidth,
    );
    return _LoadedPieceAsset(
      image: image,
      textColor: analysis.textColor,
      textAlignment: textAlignment,
      margins: margins,
    );
  });
}

/// [assetPath]の画像1枚を[kPieceBoxWidth]×[kPieceBoxHeight]の枠に表示したときの
/// 左右の余白（[PieceHorizontalMargins]）を返す。解答欄でのピース間オーバーラップ
/// 計算用（`game_screen.dart`）。画像デコード結果は[_pieceAssetCache]で共有するため、
/// 同じ画像を表示用に読み込む処理と二重にデコードすることはない。
Future<PieceHorizontalMargins> loadPieceHorizontalMargins(String assetPath) {
  return _loadPieceAsset(assetPath).then((asset) => asset.margins);
}

class _ImageAnalysis {
  const _ImageAnalysis({
    required this.textColor,
    required this.contentCenterFraction,
    required this.contentMinXFraction,
    required this.contentMaxXFraction,
  });

  final Color textColor;

  /// 不透明ピクセルの重心。画像の幅・高さに対する割合（0.0〜1.0）で表す。
  final Offset contentCenterFraction;

  /// 不透明ピクセルが存在する範囲の左端・右端。画像の幅に対する割合（0.0〜1.0）。
  final double contentMinXFraction;
  final double contentMaxXFraction;
}

/// 画像の不透明部分を1回だけスキャンし、(1) 読みやすい文字色（平均輝度から判定）、
/// (2) 実際にピースが写っている部分の重心（透明な余白を除いた中心位置）、
/// (3) 不透明部分の左右の範囲、を求める。処理コストを抑えるため、ピクセルは
/// 間引いてサンプリングする。
Future<_ImageAnalysis> _analyzePieceImage(ui.Image image) async {
  const darkTextColor = Color(0xFF37474F);
  const fallback = _ImageAnalysis(
    textColor: darkTextColor,
    contentCenterFraction: Offset(0.5, 0.5),
    contentMinXFraction: 0,
    contentMaxXFraction: 1,
  );

  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) return fallback;

  final bytes = byteData.buffer.asUint8List();
  final width = image.width;
  const sampleStep = 6; // ピクセル単位の間引き幅
  var rSum = 0, gSum = 0, bSum = 0, count = 0;
  var xSum = 0, ySum = 0;
  var minX = width, maxX = 0;

  for (var i = 0; i < bytes.length; i += 4 * sampleStep) {
    if (bytes[i + 3] < 128) continue; // 透明部分は判定に含めない
    rSum += bytes[i];
    gSum += bytes[i + 1];
    bSum += bytes[i + 2];

    final pixelIndex = i ~/ 4;
    final x = pixelIndex % width;
    xSum += x;
    ySum += pixelIndex ~/ width;
    count++;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
  }
  if (count == 0) return fallback;

  final r = rSum / count;
  final g = gSum / count;
  final b = bSum / count;
  final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  final textColor = luminance > 0.55 ? darkTextColor : Colors.white;

  final contentCenterFraction = Offset(
    (xSum / count) / image.width,
    (ySum / count) / image.height,
  );

  return _ImageAnalysis(
    textColor: textColor,
    contentCenterFraction: contentCenterFraction,
    contentMinXFraction: minX / image.width,
    contentMaxXFraction: (maxX + 1) / image.width,
  );
}

/// 画像を[kPieceBoxWidth]×[kPieceBoxHeight]の枠にBoxFit.containで収めたときの
/// スケール・表示サイズ・枠内オフセットをまとめたもの。
class _ContainMetrics {
  const _ContainMetrics({
    required this.displayedWidth,
    required this.displayedHeight,
    required this.boxOffsetX,
    required this.boxOffsetY,
  });

  final double displayedWidth;
  final double displayedHeight;
  final double boxOffsetX;
  final double boxOffsetY;
}

_ContainMetrics _containMetrics({required int imageWidth, required int imageHeight}) {
  final scale = (kPieceBoxWidth / imageWidth < kPieceBoxHeight / imageHeight)
      ? kPieceBoxWidth / imageWidth
      : kPieceBoxHeight / imageHeight;
  final displayedWidth = imageWidth * scale;
  final displayedHeight = imageHeight * scale;
  return _ContainMetrics(
    displayedWidth: displayedWidth,
    displayedHeight: displayedHeight,
    boxOffsetX: (kPieceBoxWidth - displayedWidth) / 2,
    boxOffsetY: (kPieceBoxHeight - displayedHeight) / 2,
  );
}

/// [_containMetrics]の結果を踏まえ、不透明部分の重心（[contentCenterFraction]）が
/// ウィジェット全体（[kPieceSlotWidth]×[kPieceSlotHeight]）のどこに来るかを求め、
/// Stackの[Alignment]に変換する。
Alignment _computeTextAlignment({
  required _ContainMetrics metrics,
  required Offset contentCenterFraction,
}) {
  // その枠自体が、ウィジェット全体（kPieceSlotWidth×kPieceSlotHeight）の
  // 中央に配置されているぶんのオフセット。
  final slotOffsetX = (kPieceSlotWidth - kPieceBoxWidth) / 2;
  final slotOffsetY = (kPieceSlotHeight - kPieceBoxHeight) / 2;

  final contentX = slotOffsetX + metrics.boxOffsetX + contentCenterFraction.dx * metrics.displayedWidth;
  final contentY = slotOffsetY + metrics.boxOffsetY + contentCenterFraction.dy * metrics.displayedHeight;

  return Alignment(
    (contentX / kPieceSlotWidth) * 2 - 1,
    (contentY / kPieceSlotHeight) * 2 - 1,
  );
}

/// 接頭辞・語幹・接尾辞のピースを表示するウィジェット。
///
/// 形・質感は実物のピース画像をそのまま使い、縦横比を保ったまま固定枠の
/// 中央に表示する。文字はその上に重ねる。
class PuzzlePieceShape extends StatelessWidget {
  const PuzzlePieceShape({
    super.key,
    required this.text,
    required this.assetPath,
    this.highlighted = false,
  });

  final String text;

  /// `assets/puzzle_pieces_v2/`内の、どの画像を使うか（完全なアセットパス）。
  final String assetPath;

  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kPieceSlotWidth,
      height: kPieceSlotHeight,
      child: FutureBuilder<_LoadedPieceAsset>(
        future: _loadPieceAsset(assetPath),
        builder: (context, snapshot) {
          final asset = snapshot.data;
          Widget imageWidget = asset == null
              ? const SizedBox.shrink()
              : RawImage(
                  image: asset.image,
                  width: kPieceBoxWidth,
                  height: kPieceBoxHeight,
                  fit: BoxFit.contain,
                );
          if (highlighted && asset != null) {
            // BlendMode.srcATopで、画像の不透明部分だけに色を重ねる
            // （透明な背景部分まで塗りつぶさないようにするため）。
            imageWidget = ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0x59FF7043),
                BlendMode.srcATop,
              ),
              child: imageWidget,
            );
          }
          return Stack(
            alignment: Alignment.center,
            children: [
              // 画像の読み込み前後を問わず、常に枠いっぱいの当たり判定を確保する
              // （読み込み前は透明な当たり判定のみのSizedBox.shrink()になってしまい、
              // ドラッグの掴み始めが空振りする不具合があったため）。
              const SizedBox(
                width: kPieceSlotWidth,
                height: kPieceSlotHeight,
                child: ColoredBox(color: Colors.transparent),
              ),
              Align(
                alignment: Alignment.center,
                child: imageWidget,
              ),
              Align(
                alignment: asset?.textAlignment ?? Alignment.center,
                child: _pieceLabel(text, asset?.textColor ?? const Color(0xFF37474F)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ピースに重ねる文字のフォント設定（サイズ・太さ）。文字の実際の描画幅を
/// 計測する側（`game_screen.dart`の重なり幅計算）でも同じ値を参照し、
/// 見た目と計測がずれないようにする。
const TextStyle kPieceLabelTextStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);

/// ピースの上に重ねる文字。背景がどんな色でも読めるよう、塗りつぶし色と反対の
/// 色の縁取り風の影を8方向に重ねてから塗りつぶす（`Text`を1つだけにして、
/// `find.text()`のようなテキスト検索が同じ文字列を2重に見つけないようにするため、
/// 別レイヤーのTextを重ねる方式ではなく`shadows`で縁取りを表現している）。
Widget _pieceLabel(String text, Color fillColor) {
  final outlineColor = fillColor == Colors.white ? Colors.black87 : Colors.white;
  const offsets = [
    Offset(-1.4, -1.4), Offset(0, -1.4), Offset(1.4, -1.4),
    Offset(-1.4, 0), Offset(1.4, 0),
    Offset(-1.4, 1.4), Offset(0, 1.4), Offset(1.4, 1.4),
  ];

  return Text(
    text,
    style: kPieceLabelTextStyle.copyWith(
      color: fillColor,
      shadows: [
        for (final offset in offsets) Shadow(color: outlineColor, offset: offset),
      ],
    ),
  );
}

/// [text]をピースのフォント設定（[kPieceLabelTextStyle]）で描画したときの
/// 実際の横幅（px）。解答欄でピース同士を重ねる幅を計算する際、文字の
/// 実際の描画結果を覆ってしまわないようにするために使う
/// （`game_screen.dart`の重なり幅計算を参照）。
double measurePieceLabelWidth(String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: kPieceLabelTextStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}
