import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'piece_geometry.dart';

export 'piece_geometry.dart' show PieceConnector, PieceGeometry, kUnitPx;

/// ピース画像 (`assets/puzzle_pieces_v3/`) の置き場。画像は
/// `{pre,stem_g,stem_y,suf}_{1..4}.png` の 16 枚で、`tools/piece_exporter` が
/// SVG 原本から書き出したもの。形状の寸法は [kPieceGeometry] を参照。
///
/// 文字の長さに合わせて、ピースの本体(四角い部分)を横に引き伸ばして表示する
/// (出っ張り・凹みの形は変えない)。伸ばせる列はピースごとに測定済み。
const String kPieceAssetDir = 'assets/puzzle_pieces_v3';

/// ピースに重ねる文字のフォント設定（サイズ・太さ）。小学生にも読みやすいよう、
/// 長い単語でも文字サイズは変えず、ピースの方を伸ばして収める。
///
/// 文字幅の測定（[measurePieceLabelWidth]）と実際の描画で必ず同じ見た目になるよう、
/// 周囲のテーマから何も継承しない(`inherit: false`)完全指定にしている。継承すると、
/// 測定時(テーマの外)と描画時(テーマの中)で書体・字間が違い、ピースを伸ばしすぎたり
/// 足りなかったりする。
const TextStyle kPieceLabelTextStyle = TextStyle(
  inherit: false,
  fontFamily: 'Roboto',
  fontSize: 20,
  fontWeight: FontWeight.bold,
  letterSpacing: 0,
  color: Color(0xFF37474F),
);

final Map<String, double> _labelWidthCache = {};

/// [text]をピースのフォント設定（[kPieceLabelTextStyle]）で描画したときの
/// 実際の横幅（px）。ピースをどれだけ伸ばすかの計算に使う。
double measurePieceLabelWidth(String text) {
  return _labelWidthCache.putIfAbsent(text, () {
    final painter = TextPainter(
      text: TextSpan(text: text, style: kPieceLabelTextStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  });
}

/// 画像 [assetPath] に文字 [text] を載せたときの、ピース 1 枚の表示寸法。
/// 画面上のレイアウト計算 (解答欄・選択肢エリア) と描画の両方で同じ値を使う。
class PieceFit {
  PieceFit._(this.geometry, this.extra);

  factory PieceFit.of(String assetPath, String text) {
    final geometry = pieceGeometryOf(assetPath);
    assert(geometry != null, '未知のピース画像: $assetPath');
    final g = geometry ?? kPieceGeometry.values.first;
    return PieceFit._(g, g.extraFor(measurePieceLabelWidth(text)));
  }

  final PieceGeometry geometry;

  /// 横に引き伸ばす量 (px)。
  final double extra;

  /// 画像全体 (出っ張り・光彩を含む) の大きさ。
  double get width => geometry.widthPx + extra;
  double get height => geometry.heightPx;

  /// 本体 (四角い部分) の幅。隣のピースとはこの幅ぶんずつで突き合わせる。
  double get bodyWidth => geometry.bodyWidthPx + extra;

  /// 文字を置ける範囲の幅と中心 (ピースの左上を原点とした座標)。
  double get textSpan => geometry.textSpanPx + extra;
  Offset get textCenter {
    final g = geometry;
    final left = g.bodyLeftPx + g.insetLeft * PieceGeometry.scale;
    return Offset(
      left + textSpan / 2,
      (g.bodyTop + g.bodyBottom) / 2 * PieceGeometry.scale,
    );
  }
}

class _LoadedPieceAsset {
  const _LoadedPieceAsset({required this.image, required this.textColor});

  final ui.Image image;
  final Color textColor;
}

final Map<String, Future<_LoadedPieceAsset>> _pieceAssetCache = {};

Future<_LoadedPieceAsset> _loadPieceAsset(String assetPath, PieceGeometry geometry) {
  return _pieceAssetCache.putIfAbsent(assetPath, () async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final image = frame.image;
    return _LoadedPieceAsset(
      image: image,
      textColor: await _readableTextColor(image, geometry),
    );
  });
}

/// 本体の中央の色の明るさから、読みやすい文字色（明るい色には濃い文字、
/// 暗い色には白）を決める。ピースは半透明なので、白い背景に重ねた見た目で判定する。
Future<Color> _readableTextColor(ui.Image image, PieceGeometry g) async {
  const darkTextColor = Color(0xFF37474F);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) return darkTextColor;
  final x = (g.bodyLeft + g.bodyRight) ~/ 2;
  final y = (g.bodyTop + g.bodyBottom) ~/ 2;
  final i = (y * image.width + x) * 4;
  final a = byteData.getUint8(i + 3) / 255;
  double blend(int c) => c * a + 255 * (1 - a);
  final r = blend(byteData.getUint8(i));
  final gr = blend(byteData.getUint8(i + 1));
  final b = blend(byteData.getUint8(i + 2));
  final luminance = (0.299 * r + 0.587 * gr + 0.114 * b) / 255;
  return luminance > 0.55 ? darkTextColor : Colors.white;
}

/// 接頭辞・語幹・接尾辞のピースを表示するウィジェット。
///
/// ピース画像の本体部分を、文字の長さに合わせて横に引き伸ばして描き、その上に
/// 文字を重ねる。ウィジェットの大きさは [PieceFit.width] × [PieceFit.height]
/// (出っ張りを含む画像全体)。
class PuzzlePieceShape extends StatelessWidget {
  const PuzzlePieceShape({
    super.key,
    required this.text,
    required this.assetPath,
    this.highlighted = false,
  });

  final String text;

  /// `assets/puzzle_pieces_v3/`内の、どの画像を使うか（完全なアセットパス）。
  final String assetPath;

  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final fit = PieceFit.of(assetPath, text);
    return SizedBox(
      width: fit.width,
      height: fit.height,
      child: FutureBuilder<_LoadedPieceAsset>(
        future: _loadPieceAsset(assetPath, fit.geometry),
        builder: (context, snapshot) {
          final asset = snapshot.data;
          Widget? imageWidget;
          Widget? effectsWidget;
          if (asset != null) {
            // 輪郭線・影は本体の外側だけに描く別レイヤー。ハイライトの色付けは
            // 本体にだけ掛け、輪郭・影には掛けない。
            effectsWidget = CustomPaint(
              size: Size(fit.width, fit.height),
              painter: _PieceEffectsPainter(
                image: asset.image,
                geometry: fit.geometry,
                extra: fit.extra,
              ),
            );
            imageWidget = CustomPaint(
              size: Size(fit.width, fit.height),
              painter: _PieceImagePainter(
                image: asset.image,
                geometry: fit.geometry,
                extra: fit.extra,
              ),
            );
            if (highlighted) {
              // BlendMode.srcATopで、画像の不透明部分だけに色を重ねる
              // （透明な背景部分まで塗りつぶさないようにするため）。
              imageWidget = ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Color(0xA6FF6D00),
                  BlendMode.srcATop,
                ),
                child: imageWidget,
              );
            }
          }
          final center = fit.textCenter;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 画像の読み込み前後を問わず、常にピース全体の当たり判定を確保する
              // （読み込み前は透明な当たり判定のみになってしまい、ドラッグの
              // 掴み始めが空振りする不具合があったため）。
              const Positioned.fill(child: ColoredBox(color: Colors.transparent)),
              if (effectsWidget != null) Positioned.fill(child: effectsWidget),
              if (imageWidget != null) Positioned.fill(child: imageWidget),
              Positioned(
                left: center.dx - fit.textSpan / 2,
                top: center.dy - 20,
                width: fit.textSpan,
                height: 40,
                child: Center(
                  // 伸ばせない形のピースで文字が収まらないときだけ縮小する。
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _pieceLabel(text, asset?.textColor ?? const Color(0xFF37474F)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ピース画像を、[extra] px だけ [offset] ずらして(論理 px)、[paint] で描く。
void _drawPieceBody(
  Canvas canvas,
  ui.Image image,
  PieceGeometry g,
  double extra,
  Paint paint, {
  Offset offset = Offset.zero,
}) {
  canvas.save();
  canvas.translate(offset.dx, offset.dy);
  canvas.scale(PieceGeometry.scale);
  if (extra <= 0.01 || !g.stretchable) {
    canvas.drawImage(image, Offset.zero, paint);
  } else {
    // 伸ばせる列(stretchLeft〜stretchRight)だけを横に引き伸ばし、左右の
    // 出っ張り・凹み・縁は元の大きさのまま描く。
    canvas.drawImageNine(
      image,
      Rect.fromLTRB(g.stretchLeft.toDouble(), 0, g.stretchRight.toDouble(), g.height.toDouble()),
      Rect.fromLTWH(0, 0, g.width + extra / PieceGeometry.scale, g.height.toDouble()),
      paint,
    );
  }
  canvas.restore();
}

/// ピース画像を、[extra] px だけ本体を横に引き伸ばして描く。
class _PieceImagePainter extends CustomPainter {
  _PieceImagePainter({
    required this.image,
    required this.geometry,
    required this.extra,
  });

  final ui.Image image;
  final PieceGeometry geometry;
  final double extra;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.medium;
    _drawPieceBody(canvas, image, geometry, extra, paint);
  }

  @override
  bool shouldRepaint(covariant _PieceImagePainter old) =>
      old.image != image || old.geometry != geometry || old.extra != extra;
}

/// 輪郭線の色・太さ (論理 px) と、影の濃さ・ずらし・ぼかし。背景が同系色でも
/// ピースの形が分かるようにするための、控えめな値。
const Color _kOutlineColor = Color(0xFF37474F);
const double _kOutlineOpacity = 0.55;
const double _kOutlineWidth = 1.0;
const double _kShadowOpacity = 0.28;
const Offset _kShadowOffset = Offset(0, 1.5);
const double _kShadowSigma = 1.6;

/// ピース本体の「外側だけ」に、薄い輪郭線と控えめな影を描く。
///
/// 本体は半透明(約85%)なので、本体の下に輪郭や影を敷くと透けて本体の色が
/// 変わってしまう。そこで、本体の形(不透明に近い部分)を型として抜き取り、
/// 型の外側にだけ描く。本体の透明度・色・大きさ(レイアウト)には影響しない。
class _PieceEffectsPainter extends CustomPainter {
  _PieceEffectsPainter({
    required this.image,
    required this.geometry,
    required this.extra,
  });

  final ui.Image image;
  final PieceGeometry geometry;
  final double extra;

  /// 画像の透明度が約 100/255 を超える所だけを、不透明な単色にする。
  /// 縁のにじみ(透明度 60 前後以下)は型に含めない。
  static ColorFilter _silhouette(Color color) {
    final r = (color.r * 255).roundToDouble();
    final g = (color.g * 255).roundToDouble();
    final b = (color.b * 255).roundToDouble();
    return ColorFilter.matrix(<double>[
      0, 0, 0, 0, r, //
      0, 0, 0, 0, g,
      0, 0, 0, 0, b,
      0, 0, 0, 10, -1000,
    ]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(-8, -8, size.width + 16, size.height + 16);
    final mask = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = _silhouette(Colors.black);
    final cut = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = _silhouette(Colors.black)
      ..blendMode = BlendMode.dstOut;

    // 影: 型をずらしてぼかし、型そのものの内側を抜く。
    canvas.saveLayer(bounds, Paint()..color = Colors.black.withValues(alpha: _kShadowOpacity));
    canvas.saveLayer(
      bounds,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: _kShadowSigma, sigmaY: _kShadowSigma),
    );
    _drawPieceBody(canvas, image, geometry, extra, mask, offset: _kShadowOffset);
    canvas.restore();
    _drawPieceBody(canvas, image, geometry, extra, cut);
    canvas.restore();

    // 輪郭線: 型を全方向に少しずつずらして重ね(=太らせて)、型の内側を抜く。
    // 不透明な単色で重ねてから、レイヤー全体を一度に半透明にする(重なりで濃くならない)。
    canvas.saveLayer(bounds, Paint()..color = Colors.black.withValues(alpha: _kOutlineOpacity));
    final ring = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = _silhouette(_kOutlineColor);
    const steps = 12;
    for (var i = 0; i < steps; i++) {
      final a = 2 * pi * i / steps;
      _drawPieceBody(
        canvas,
        image,
        geometry,
        extra,
        ring,
        offset: Offset(cos(a), sin(a)) * _kOutlineWidth,
      );
    }
    _drawPieceBody(canvas, image, geometry, extra, cut);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PieceEffectsPainter old) =>
      old.image != image || old.geometry != geometry || old.extra != extra;
}

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

/// 選択肢エリアで、ピース 1 個が占める最大の大きさ (全ピースのうち最大の幅・高さ)。
Size maxPieceSize(Iterable<PieceFit> fits) {
  var w = 0.0, h = 0.0;
  for (final f in fits) {
    w = max(w, f.width);
    h = max(h, f.height);
  }
  return Size(w, h);
}
