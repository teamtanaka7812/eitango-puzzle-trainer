// SVG 原本 (tools/piece_exporter/svg) → アプリ用 PNG + 形状メタデータの書き出し。
//
// 実行:  cd tools/piece_exporter && flutter test
// 出力:  ../../assets/puzzle_pieces_v3/{pre,stem_g,stem_y,suf}_{1..4}.png
//        ../../lib/widgets/piece_geometry.g.dart  (形状メタデータ。アプリが同期的に参照する)
//        preview/chain_*.png (目視確認用。git 管理外)
//
// PNG は SVG の 1 単位 = kExportScale px で描画し、外周の余白を切り詰める。
// 本体(四角い部分)の位置・「横に伸ばしても絵が崩れない列」・文字を置ける
// 範囲を測って JSON に残す。アプリ側はこれを使って、ラベルの長さに合わせて
// ピースを横に伸ばし、隣のピースと本体どうしをぴったり突き合わせて並べる。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const int kExportScale = 3; // SVG 1 単位あたりのピクセル数
const double kCanvasW = 215, kCanvasH = 310; // SVG の viewBox
const String srcDir = 'svg';
const String outDir = '../../assets/puzzle_pieces_v3';
const String previewDir = 'preview';
const String geometryDartOut = '../../lib/widgets/piece_geometry.g.dart';

/// SVG ファイル名 → 出力名。
const Map<String, String> kSources = {
  'pre_piece_': 'pre_',
  'g_stem_piece_': 'stem_g_',
  'y_stem_piece_': 'stem_y_',
  'suf_piece_': 'suf_',
};

class Raster {
  Raster(this.w, this.h, this.rgba);
  final int w, h;
  final Uint8List rgba;
  int alpha(int x, int y) => rgba[(y * w + x) * 4 + 3];
  int ch(int x, int y, int c) => rgba[(y * w + x) * 4 + c];
}

Future<Raster> renderSvg(String svg) async {
  final info = await vg.loadPicture(SvgStringLoader(svg), null);
  final w = (kCanvasW * kExportScale).round();
  final h = (kCanvasH * kExportScale).round();
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.scale(w / info.size.width, h / info.size.height);
  canvas.drawPicture(info.picture);
  final img = await rec.endRecording().toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return Raster(w, h, bd!.buffer.asUint8List());
}

/// 縁取り(白い光彩・黒い細線)を消した SVG。本体の輪郭だけを測るために使う。
String fillOnly(String svg) => svg
    .replaceAll('stroke="#ffffff"', 'stroke="none"')
    .replaceAll('stroke="#000000"', 'stroke="none"')
    .replaceAll('stroke:#000000', 'stroke:none');

Future<ui.Image> encodeImage(Raster r, ui.Rect crop) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  final src = await _toImage(r);
  canvas.drawImageRect(
    src,
    crop,
    ui.Rect.fromLTWH(0, 0, crop.width, crop.height),
    ui.Paint()..filterQuality = ui.FilterQuality.none,
  );
  return rec.endRecording().toImage(crop.width.round(), crop.height.round());
}

Future<ui.Image> _toImage(Raster r) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(r.rgba, r.w, r.h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// 値の集まりのうち、tol 以内に最も多く固まっている塊の中央値。
int clusterMode(List<int> values, int tol) {
  final v = [...values]..sort();
  var bestCount = 0, bestStart = 0;
  var j = 0;
  for (var i = 0; i < v.length; i++) {
    while (v[j] < v[i] - tol) {
      j++;
    }
    // 窓 [j, i] は v[i]-tol 以上 v[i] 以下。
    if (i - j + 1 > bestCount) {
      bestCount = i - j + 1;
      bestStart = j;
    }
  }
  return v[bestStart + bestCount ~/ 2];
}

class Geometry {
  Geometry({
    required this.name,
    required this.w,
    required this.h,
    required this.bodyL,
    required this.bodyR,
    required this.bodyT,
    required this.bodyB,
    required this.stretchL,
    required this.stretchR,
    required this.insetL,
    required this.insetR,
    required this.leftKind,
    required this.rightKind,
    required this.stretchRun,
    required this.stretchable,
    required this.leftTop,
    required this.rightTop,
    required this.leftBottom,
    required this.rightBottom,
  });
  final String name;
  final int w, h; // PNG サイズ (px)
  final int bodyL, bodyR, bodyT, bodyB; // 本体の矩形 (PNG 内 px, R/B は含まない端)
  final int stretchL, stretchR; // 横に伸ばしてよい列 [L, R) (px)
  final int insetL, insetR; // 文字を置けない左右の内側の余白 (凹みの深さ, px)
  final String leftKind, rightKind; // tab / socket / flat
  // 隣のピースとの継ぎ目の上端・下端の高さ (PNG 内 px)。継ぎ目の角どうしを合わせるのに使う。
  final int leftTop, rightTop, leftBottom, rightBottom;
  final bool stretchable; // 絵を崩さずに横へ伸ばせる列が見つかったか
  final int stretchRun; // 見つかった「絵が変わらない列」の最大連続幅 (px, 診断用)
  late (int, int) cropOrigin; // 切り出し左上 (SVG 描画キャンバス内 px)

  Map<String, dynamic> toJson() => {
        'w': w,
        'h': h,
        'bodyL': bodyL,
        'bodyR': bodyR,
        'bodyT': bodyT,
        'bodyB': bodyB,
        'stretchable': stretchable,
        'stretchL': stretchL,
        'stretchR': stretchR,
        'insetL': insetL,
        'insetR': insetR,
        'leftKind': leftKind,
        'rightKind': rightKind,
        'leftTop': leftTop,
        'rightTop': rightTop,
        'leftBottom': leftBottom,
        'rightBottom': rightBottom,
      };
}

bool _sameColumn(Raster r, int xa, int xb, int y0, int y1, int tol) {
  for (var y = y0; y < y1; y++) {
    for (var c = 0; c < 4; c++) {
      if ((r.ch(xa, y, c) - r.ch(xb, y, c)).abs() > tol) return false;
    }
  }
  return true;
}

Geometry analyze(String name, Raster full, Raster fill) {
  // 1. 絵全体 (光彩込み) の外接矩形 → 切り出し範囲。
  var minX = full.w, maxX = -1, minY = full.h, maxY = -1;
  for (var y = 0; y < full.h; y++) {
    for (var x = 0; x < full.w; x++) {
      if (full.alpha(x, y) > 8) {
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
    }
  }
  const pad = 2;
  final cx0 = minX - pad, cy0 = minY - pad;
  final cw = maxX - minX + 1 + pad * 2, ch = maxY - minY + 1 + pad * 2;

  // 2. 本体の矩形。塗り(縁取りなし)の各行の左端・右端、各列の上端・下端の
  //    「最も多く揃っている位置」。出っ張り・凹みの行は外れ値として無視される。
  final lefts = <int>[], rights = <int>[], tops = <int>[], bottoms = <int>[];
  for (var y = 0; y < fill.h; y++) {
    int? l, r;
    for (var x = 0; x < fill.w; x++) {
      if (fill.alpha(x, y) > 127) {
        l ??= x;
        r = x;
      }
    }
    if (l != null) {
      lefts.add(l);
      rights.add(r! + 1);
    }
  }
  for (var x = 0; x < fill.w; x++) {
    int? t, b;
    for (var y = 0; y < fill.h; y++) {
      if (fill.alpha(x, y) > 127) {
        t ??= y;
        b = y;
      }
    }
    if (t != null) {
      tops.add(t);
      bottoms.add(b! + 1);
    }
  }
  const tol = kExportScale; // 1 単位
  final bodyL = clusterMode(lefts, tol) - cx0;
  final bodyR = clusterMode(rights, tol) - cx0;
  final bodyT = clusterMode(tops, tol) - cy0;
  final bodyB = clusterMode(bottoms, tol) - cy0;

  // 3. 左右の接続部の種類と、文字帯での内側の余白。
  //    文字帯 = 本体の縦の中央から上下 10 単位。
  final bandHalf = 10 * kExportScale;
  final midY = (bodyT + bodyB) ~/ 2 + cy0;
  var minLeft = 1 << 30, maxLeft = -1, minRight = 1 << 30, maxRight = -1;
  for (var y = midY - bandHalf; y < midY + bandHalf; y++) {
    int? l, r;
    for (var x = 0; x < fill.w; x++) {
      if (fill.alpha(x, y) > 127) {
        l ??= x;
        r = x + 1;
      }
    }
    if (l == null) continue;
    minLeft = math.min(minLeft, l);
    maxLeft = math.max(maxLeft, l);
    minRight = math.min(minRight, r!);
    maxRight = math.max(maxRight, r);
  }
  String kind(int lo, int hi, int ref, {required bool left}) {
    // 左: 帯のどこかが本体より外へ出ていれば tab、中へ引っ込んでいれば socket。
    final outward = left ? ref - lo : hi - ref;
    final inward = left ? hi - ref : ref - lo;
    if (outward > 2 * kExportScale) return 'tab';
    if (inward > 2 * kExportScale) return 'socket';
    return 'flat';
  }

  final leftKind = kind(minLeft, maxLeft, bodyL + cx0, left: true);
  final rightKind = kind(minRight, maxRight, bodyR + cx0, left: false);
  final insetL = math.max(0, maxLeft - (bodyL + cx0));
  final insetR = math.max(0, (bodyR + cx0) - minRight);

  // 4. 継ぎ目の角の高さ (本体の左右端から少し内側の列の、上端と下端)。
  int colTop(int x) {
    for (var y = 0; y < fill.h; y++) {
      if (fill.alpha(x, y) > 127) return y;
    }
    return -1;
  }

  int colBottom(int x) {
    for (var y = fill.h - 1; y >= 0; y--) {
      if (fill.alpha(x, y) > 127) return y + 1;
    }
    return -1;
  }

  final cL = bodyL + cx0, cR = bodyR + cx0;
  const cornerX = 2 * kExportScale;
  final leftTop = colTop(cL + cornerX) - cy0;
  final rightTop = colTop(cR - 1 - cornerX) - cy0;
  final leftBottom = colBottom(cL + cornerX) - cy0;
  final rightBottom = colBottom(cR - 1 - cornerX) - cy0;

  // 5. 横に伸ばしてよい列。本体の中で、上端・下端がほぼ水平で、途中に凹みや
  //    出っ張りの根元を含まない列が最も長く続く所。伸ばすときはこの範囲全体を
  //    引き伸ばすので、わずかな傾きがあっても滑らかなままになる。
  const margin = 4 * kExportScale; // 継ぎ目の曲がりに近い列は避ける
  const flatTol = 2; // 上下端のずれの許容 (px)
  const edgeTol = 4 * kExportScale; // 辺のうねり(±数単位)の許容
  // 本体の中央の色 (塗りつぶしの色の基準)
  final refPixel = [
    for (var c = 0; c < 4; c++)
      full.ch((bodyL + bodyR) ~/ 2 + cx0, (bodyT + bodyB) ~/ 2 + cy0, c)
  ];
  final colT = <int, int>{}, colB = <int, int>{};
  final fullT = <int, int>{}, fullB = <int, int>{}; // 光彩を含めた上端・下端
  int fullTop(int x) {
    for (var y = 0; y < full.h; y++) {
      if (full.alpha(x, y) > 4) return y;
    }
    return -1;
  }

  int fullBottom(int x) {
    for (var y = full.h - 1; y >= 0; y--) {
      if (full.alpha(x, y) > 4) return y + 1;
    }
    return -1;
  }

  final solid = <int, bool>{};
  for (var cx = cL + margin; cx < cR - margin; cx++) {
    final t = colTop(cx), b = colBottom(cx);
    colT[cx] = t;
    colB[cx] = b;
    fullT[cx] = fullTop(cx);
    fullB[cx] = fullBottom(cx);
    // 上下の辺が本体の高さにあること (出っ張りの先端や凹みの底を除く)
    var ok = t >= 0 &&
        (t - (bodyT + cy0)).abs() <= edgeTol &&
        (b - (bodyB + cy0)).abs() <= edgeTol;
    for (var y = t; ok && y < b; y++) {
      if (fill.alpha(cx, y) <= 127) ok = false;
    }
    // 本体の内側が一色であること (凹みの縁取りや影を含む列は伸ばすと筋になる)
    final iy0 = bodyT + cy0 + 4 * kExportScale, iy1 = bodyB + cy0 - 4 * kExportScale;
    for (var y = iy0; ok && y < iy1; y++) {
      for (var c = 0; c < 4; c++) {
        if ((full.ch(cx, y, c) - refPixel[c]).abs() > 10) ok = false;
      }
    }
    solid[cx] = ok;
  }
  // 出っ張り・凹みの根元に近い列は、光彩やなだらかな曲がりを含むので避ける
  final featureCols = <int>[];
  for (var cx = cL; cx < cR; cx++) {
    final t = colTop(cx), b = colBottom(cx);
    if (t < 0 ||
        (t - (bodyT + cy0)).abs() > edgeTol ||
        (b - (bodyB + cy0)).abs() > edgeTol) {
      featureCols.add(cx);
    }
  }
  const guard = 3 * kExportScale;
  bool nearFeature(int cx) =>
      featureCols.any((f) => (f - cx).abs() <= guard);
  for (var cx = cL + margin; cx < cR - margin; cx++) {
    if (nearFeature(cx)) solid[cx] = false;
  }
  var bestLen = 0, bestStart = cL + margin;
  final centre = (cL + cR) / 2;
  for (var a = cL + margin; a < cR - margin; a++) {
    if (!solid[a]!) continue;
    var e = a + 1;
    while (e < cR - margin &&
        solid[e]! &&
        (colT[e]! - colT[a]!).abs() <= flatTol &&
        (colB[e]! - colB[a]!).abs() <= flatTol &&
        (fullT[e]! - fullT[a]!).abs() <= 1 &&
        (fullB[e]! - fullB[a]!).abs() <= 1 &&
        // 本体の内側は上下の縁を除いて同じ色であること (凹みの縁の影などを含まない)
        _sameColumn(full, a, e, bodyT + cy0 + 4 * kExportScale,
            bodyB + cy0 - 4 * kExportScale, 8)) {
      e++;
    }
    final len = e - a;
    final better = len > bestLen ||
        (len == bestLen && ((a + e) / 2 - centre).abs() < ((bestStart + bestStart + bestLen) / 2 - centre).abs());
    if (better) {
      bestLen = len;
      bestStart = a;
    }
  }
  final sL = bestStart;
  final sR = bestStart + (bestLen < 1 ? 1 : bestLen);

  return Geometry(
    name: name,
    w: cw,
    h: ch,
    bodyL: bodyL,
    bodyR: bodyR,
    bodyT: bodyT,
    bodyB: bodyB,
    stretchL: sL - cx0,
    stretchR: sR - cx0,
    insetL: insetL,
    insetR: insetR,
    leftKind: leftKind,
    rightKind: rightKind,
    stretchRun: bestLen,
    stretchable: bestLen >= 3,
    leftTop: leftTop,
    rightTop: rightTop,
    leftBottom: leftBottom,
    rightBottom: rightBottom,
  )..cropOrigin = (cx0, cy0);
}

Future<Uint8List> pngBytes(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

/// 横に [extra] px 伸ばしたピースを (dx, dy) に描く。dx,dy は PNG 左上の置き先。
void drawStretched(ui.Canvas canvas, ui.Image img, Geometry g, double dx,
    double dy, double extra) {
  final p = ui.Paint()..filterQuality = ui.FilterQuality.high;
  canvas.drawImageNine(
    img,
    ui.Rect.fromLTRB(g.stretchL.toDouble(), 0, g.stretchR.toDouble(), g.h.toDouble()),
    ui.Rect.fromLTWH(dx, dy, g.w + extra, g.h.toDouble()),
    p,
  );
}

/// 継ぎ目に出っ張りがある側を手前にするための描画順 (奥から手前)。
List<int> drawOrder(List<Geometry> chain) {
  // 隣り合う 2 枚のうち、継ぎ目に出っ張り(tab)を持つ方が手前。
  final behind = <int, Set<int>>{for (var i = 0; i < chain.length; i++) i: {}};
  for (var i = 0; i + 1 < chain.length; i++) {
    final leftOnTop = chain[i].rightKind == 'tab' || chain[i + 1].leftKind != 'tab';
    if (leftOnTop) {
      behind[i]!.add(i + 1); // i+1 は i より奥
    } else {
      behind[i + 1]!.add(i);
    }
  }
  final order = <int>[];
  final done = <int>{};
  while (order.length < chain.length) {
    for (var i = 0; i < chain.length; i++) {
      if (done.contains(i)) continue;
      // 自分より奥にいるべきピースが全部描き終わっていれば描ける
      if (behind[i]!.every(done.contains)) {
        order.add(i);
        done.add(i);
      }
    }
  }
  return order;
}

String geometryDart(Map<String, Geometry> geoms) {
  String kind(String k) => 'PieceConnector.$k';
  final b = StringBuffer()
    ..writeln('// GENERATED FILE - DO NOT EDIT BY HAND.')
    ..writeln('// tools/piece_exporter で SVG 原本から生成する (cd tools/piece_exporter && flutter test)。')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln("import 'piece_geometry.dart';")
    ..writeln()
    ..writeln('/// PNG の 1 SVG 単位あたりのピクセル数。')
    ..writeln('const int kPiecePxPerUnit = $kExportScale;')
    ..writeln()
    ..writeln('/// 画像名 (拡張子なし) → 形状。')
    ..writeln('const Map<String, PieceGeometry> kPieceGeometry = {');
  for (final e in geoms.entries) {
    final g = e.value;
    b
      ..writeln("  '${e.key}': PieceGeometry(")
      ..writeln('    width: ${g.w}, height: ${g.h},')
      ..writeln('    bodyLeft: ${g.bodyL}, bodyRight: ${g.bodyR}, bodyTop: ${g.bodyT}, bodyBottom: ${g.bodyB},')
      ..writeln('    stretchable: ${g.stretchable}, stretchLeft: ${g.stretchL}, stretchRight: ${g.stretchR},')
      ..writeln('    insetLeft: ${g.insetL}, insetRight: ${g.insetR},')
      ..writeln('    leftConnector: ${kind(g.leftKind)}, rightConnector: ${kind(g.rightKind)},')
      ..writeln('    leftTop: ${g.leftTop}, rightTop: ${g.rightTop}, leftBottom: ${g.leftBottom}, rightBottom: ${g.rightBottom},')
      ..writeln('  ),');
  }
  b.writeln('};');
  return b.toString();
}

void main() {
  testWidgets('export pieces', (tester) async {
    await tester.runAsync(() async {
      Directory(outDir).createSync(recursive: true);
      Directory(previewDir).createSync(recursive: true);
      final geoms = <String, Geometry>{};
      final images = <String, ui.Image>{};

      for (final entry in kSources.entries) {
        for (var k = 1; k <= 4; k++) {
          final svgName = '${entry.key}$k';
          final outName = '${entry.value}$k';
          final svg = File('$srcDir/$svgName.svg').readAsStringSync();
          final full = await renderSvg(svg);
          final fill = await renderSvg(fillOnly(svg));
          final g = analyze(outName, full, fill);
          final (cx0, cy0) = g.cropOrigin;
          final img = await encodeImage(
              full,
              ui.Rect.fromLTWH(
                  cx0.toDouble(), cy0.toDouble(), g.w.toDouble(), g.h.toDouble()));
          File('$outDir/$outName.png').writeAsBytesSync(await pngBytes(img));
          geoms[outName] = g;
          images[outName] = img;
          final u = kExportScale.toDouble();
          // ignore: avoid_print
          print('$outName: png=${g.w}x${g.h}px  body=${((g.bodyR - g.bodyL) / u).toStringAsFixed(1)}'
              'x${((g.bodyB - g.bodyT) / u).toStringAsFixed(1)}u  '
              'L=${g.leftKind}(inset ${(g.insetL / u).toStringAsFixed(1)}u) '
              'R=${g.rightKind}(inset ${(g.insetR / u).toStringAsFixed(1)}u)  '
              'stretch=${g.stretchable ? '${g.stretchL}..${g.stretchR}' : 'NONE'} (run ${(g.stretchRun / u).toStringAsFixed(1)}u)');
        }
      }

      File(geometryDartOut).writeAsStringSync(geometryDart(geoms));

      // 目視確認用: 同じ番号の 前置+語幹+後置 を本体どうしで突き合わせて並べる。
      // 上段 = 伸ばさない、下段 = 各ピースを横に伸ばした状態。
      for (var k = 1; k <= 4; k++) {
        for (final stem in ['stem_g_', 'stem_y_']) {
          final chain = ['pre_$k', '$stem$k', 'suf_$k'];
          final rec = ui.PictureRecorder();
          final canvas = ui.Canvas(rec);
          const sheetW = 1500.0, sheetH = 760.0;
          canvas.drawRect(const ui.Rect.fromLTWH(0, 0, sheetW, sheetH),
              ui.Paint()..color = const ui.Color(0xFFFFFFFF));
          final geo = [for (final n in chain) geoms[n]!];
          final order = drawOrder(geo);
          for (var row = 0; row < 2; row++) {
            final extras = row == 0 ? [0.0, 0.0, 0.0] : [90.0, 180.0, 90.0];
            final baseY = 60.0 + row * 360;
            var cursorX = 40.0;
            var yTop = baseY; // 先頭ピースの PNG 上端
            final xs = <double>[], ys = <double>[];
            for (var i = 0; i < chain.length; i++) {
              final g = geo[i];
              if (i > 0) yTop += geo[i - 1].rightTop - g.leftTop;
              xs.add(cursorX - g.bodyL);
              ys.add(yTop);
              cursorX += (g.bodyR - g.bodyL) + extras[i];
            }
            for (final i in order) {
              drawStretched(canvas, images[chain[i]]!, geo[i], xs[i], ys[i], extras[i]);
            }
          }
          final img = await rec.endRecording().toImage(sheetW.round(), sheetH.round());
          File('$previewDir/chain_${stem}$k.png').writeAsBytesSync(await pngBytes(img));
        }
      }
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
