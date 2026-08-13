import 'dart:math';

import 'package:flutter/material.dart';

import '../models/puzzle_word.dart';
import '../widgets/puzzle_piece_shape.dart';

/// 解答欄のスロット数。単語の正解ピース数（2〜3）によらず常にこの数だけ表示する。
/// 使わない末尾のスロットは空欄のままにする。
const int kSlotCount = 3;

/// 1問あたりに混ぜる「おとりピース」の最小・最大個数（この範囲でランダムに決める）。
const int kMinDecoyCount = 3;
const int kMaxDecoyCount = 4;

/// ピースの絵柄（凹凸がはみ出す分の余白）と、解答欄の実際の枠との差分。
const double kSlotMargin = (kPieceSlotWidth - kPieceBoxWidth) / 2;

/// 隣り合うピースの実測余白（[_GameScreenState._overlapBetween]参照）を
/// 打ち消して「絵柄同士がちょうど接する」重なり幅を求めたうえで、そこから
/// さらにこのぶんだけ重ねる。0だと隙間なく接するだけで、パズルのピース同士が
/// 実際にかぶさり合っているようには見えないため、絵柄が一部重なって見える
/// よう追加で寄せる量。
const double kExtraOverlap = 20;

/// 解答欄のピース同士を重ねる量（画像の余白情報がまだ読み込めていないときの
/// 仮の値）。実物画像は縦横比がバラバラで、`BoxFit.contain`で92×92の枠に
/// 収めたときにできる左右の余白は、横長の画像でほぼ0px、縦長の画像で最大
/// 15px超と画像ごとに大きく異なる（実測済み）。そのため重なり量は固定値では
/// なく、隣り合う2枚それぞれの実際の余白＋[kExtraOverlap]から都度計算する
/// （[_GameScreenState._overlapBetween]）。この定数は、その余白情報の
/// 読み込みが完了するまでの間だけ使う暫定値。
const double kDefaultSlotOverlap = 20 + kExtraOverlap;

/// 上記の都度計算によるオーバーラップが取り得る最大値（安全装置）。
const double kMaxSlotOverlap = kPieceBoxWidth * 0.6;

/// 選択肢に並ぶ1ピース分。正解ピースか、おとりピースかを区別する。
class _PieceOption {
  _PieceOption({
    required this.text,
    required this.assetPath,
    required this.correctSlotIndex,
  });

  final String text;

  /// このピースの見た目に使う画像（完全なアセットパス）。
  final String assetPath;

  /// このピースが正しく入るべきスロット番号。おとりピースの場合はnull（どこに置いても不正解）。
  final int? correctSlotIndex;

  bool get isDecoy => correctSlotIndex == null;
}

/// 1つの単語のパズル操作（ドラッグ＆ドロップ・正誤判定への回答）のみを担当するウィジェット。
/// 結果画面への遷移や「次の問題へ」の進行は、呼び出し元（[onAnswer]）に委ねる。
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.puzzle,
    required this.onAnswer,
    this.progressLabel,
    this.backgroundImagePath,
    this.revealedCount = 0,
    this.totalCount = 1,
  });

  final PuzzleWord puzzle;
  final ValueChanged<bool> onAnswer;
  final String? progressLabel;

  /// レベルの進行演出（設計書3.5）用の背景画像。nullなら何も表示しない。
  final String? backgroundImagePath;

  /// そのレベルで、これまでに正解した問題数（背景がどこまで見えているか）。
  final int revealedCount;

  /// そのレベルの全問題数。
  final int totalCount;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late List<_PieceOption> _options;
  late List<int> _tray;
  late List<int?> _slots;

  /// 選択肢ピースの散らし配置。盤面の大きさに対する割合（0.0〜1.0、相対座標）で
  /// 保持し、描画のたびに現在の盤面サイズに合わせてピクセル位置へ変換する。
  /// こうすることで、ウィンドウサイズが変わってもピース同士の相対的な配置関係が保たれる。
  /// ユーザーが選択肢エリア内でピースをドラッグして置き直したときは、その場所の
  /// 割合で該当ピースの値を更新する（＝置いた場所にそのまま留まる）。
  List<Offset>? _scatterFractions;
  final GlobalKey _trayAreaKey = GlobalKey();

  /// 各ピース画像の左右の余白（[loadPieceHorizontalMargins]の結果）。
  /// 解答欄のピース同士をどれだけ重ねるかの計算に使う。読み込みが終わるまでは
  /// 空のままで、その間は[kDefaultSlotOverlap]を仮の重なり幅として使う。
  final Map<String, PieceHorizontalMargins> _margins = {};

  @override
  void initState() {
    super.initState();
    _options = _buildOptions();
    _tray = List.generate(_options.length, (i) => i);
    _slots = List<int?>.filled(kSlotCount, null);
    _loadMargins();
  }

  Future<void> _loadMargins() async {
    final assetPaths = _options.map((o) => o.assetPath).toSet();
    final entries = await Future.wait(
      assetPaths.map((path) async => MapEntry(path, await loadPieceHorizontalMargins(path))),
    );
    if (!mounted) return;
    setState(() => _margins.addEntries(entries));
  }

  /// スロット[leftSlot]・[rightSlot]（左右に隣接する2枠）に置かれた絵柄同士が
  /// ちょうど接する（重ならない）重なり幅。それぞれの実測余白（右余白＋左余白）
  /// を打ち消す値。どちらかの余白がまだ読み込めていない・スロットが空の場合は
  /// [kDefaultSlotOverlap] - [kExtraOverlap]（＝見た目調整前の暫定値）を使う。
  ///
  /// この「接する」位置は、[_SlotTarget]（ドラッグの受け皿）自体の配置に使う。
  /// スロット同士のドラッグ受付範囲（[kPieceSlotWidth]＝絵柄の枠より一回り
  /// 大きい）が過剰に重なると、隣のスロットのつもりで置いたピースが手前の
  /// スロットに取られてしまう不具合が起きるため、当たり判定はここで計算する
  /// 値（＝絵柄が重ならない範囲）を超えて詰めない。
  double _touchOverlapBetween(int leftSlot, int rightSlot) {
    final leftOptionIndex = _slots[leftSlot];
    final rightOptionIndex = _slots[rightSlot];
    if (leftOptionIndex == null || rightOptionIndex == null) {
      return kDefaultSlotOverlap - kExtraOverlap;
    }

    final leftMargins = _margins[_options[leftOptionIndex].assetPath];
    final rightMargins = _margins[_options[rightOptionIndex].assetPath];
    if (leftMargins == null || rightMargins == null) {
      return kDefaultSlotOverlap - kExtraOverlap;
    }

    return (leftMargins.right + rightMargins.left).clamp(0, kMaxSlotOverlap);
  }

  /// [_touchOverlapBetween]に[kExtraOverlap]を足した、絵柄を実際に見た目上
  /// 重ねる幅。[_SlotTarget]内の絵柄・文字の表示位置（当たり判定には影響しない
  /// 見た目だけのズラし、[_GameScreenState.build]の`visualShift`参照）に使う。
  ///
  /// 手前（左）のピースに覆われるのは常に奥（右）のピースなので、追加で
  /// 重ねてよい幅は、右ピース自身の文字が隠れない範囲（文字の中心位置から
  /// 実際の描画幅の半分を引いた、絵柄の左端までの余裕）を超えない。
  /// `un`・`re`のような短い接頭辞は[kExtraOverlap]までそのまま重ねられるが、
  /// `fortunate`・`comfort`のような長い語幹・接尾辞は、その分だけ重なりを
  /// 弱めて文字を隠さないようにする。
  double _visualOverlapBetween(int leftSlot, int rightSlot) {
    final touch = _touchOverlapBetween(leftSlot, rightSlot);

    final rightOptionIndex = _slots[rightSlot];
    if (rightOptionIndex == null) return (touch + kExtraOverlap).clamp(0, kMaxSlotOverlap);

    final rightOption = _options[rightOptionIndex];
    final rightMargins = _margins[rightOption.assetPath];
    if (rightMargins == null) return (touch + kExtraOverlap).clamp(0, kMaxSlotOverlap);

    final textHalfWidth = measurePieceLabelWidth(rightOption.text) / 2;
    final distanceToTextEdge = rightMargins.textCenterX - rightMargins.left - textHalfWidth;
    final safeExtra = distanceToTextEdge.clamp(0, kExtraOverlap);

    return (touch + safeExtra).clamp(0, kMaxSlotOverlap);
  }

  /// 解答欄の各スロット（ドラッグの受け皿）のx座標（左端からの距離）を、
  /// 隣接ペアごとの「絵柄が接する」重なり幅を積み上げて計算する。
  List<double> _hitLefts() {
    final lefts = <double>[0];
    for (var i = 0; i < kSlotCount - 1; i++) {
      lefts.add(lefts[i] + kPieceBoxWidth - _touchOverlapBetween(i, i + 1));
    }
    return lefts;
  }

  /// 各スロットの絵柄を、実際にどれだけ見た目上重なって見せるかを踏まえた
  /// x座標。[_hitLefts]と同じ考え方だが、[_visualOverlapBetween]（接する幅＋
  /// [kExtraOverlap]）を使う分だけ間隔が詰まる。
  List<double> _visualLefts() {
    final lefts = <double>[0];
    for (var i = 0; i < kSlotCount - 1; i++) {
      lefts.add(lefts[i] + kPieceBoxWidth - _visualOverlapBetween(i, i + 1));
    }
    return lefts;
  }

  List<_PieceOption> _buildOptions() {
    final presetChoices = widget.puzzle.presetChoices;
    if (presetChoices != null) {
      return _buildOptionsFromPreset(presetChoices);
    }
    return _buildOptionsProcedurally();
  }

  /// あらかじめ人手で用意された選択肢（テキスト・画像とも固定）をそのまま使う。
  /// 表示順だけはシャッフルする（正誤の並びが常に同じにならないようにするため）。
  List<_PieceOption> _buildOptionsFromPreset(List<ChoicePiece> choices) {
    final random = Random.secure();
    final partTexts = widget.puzzle.parts.map((p) => p.text).toList();
    final order = List.generate(choices.length, (i) => i)..shuffle(random);

    return [
      for (final i in order)
        _PieceOption(
          text: choices[i].text,
          assetPath: choices[i].assetPath,
          correctSlotIndex: () {
            final slotIndex = partTexts.indexOf(choices[i].text);
            return slotIndex == -1 ? null : slotIndex;
          }(),
        ),
    ];
  }

  /// 正解ピースに加え、おとり・使用画像をランダムに生成する（従来の方式）。
  List<_PieceOption> _buildOptionsProcedurally() {
    final parts = widget.puzzle.parts;
    final correctTexts = parts.map((p) => p.text).toSet();
    // Random()（種指定なし）は、環境によっては短時間に連続生成すると
    // 似た乱数列になりやすい弱いシード方式に頼ることがある。
    // ここでは正誤に関わる抽選（おとり選び・表示順・画像選び）を全て
    // 1つのRandom.secure()（暗号論的に安全な乱数源）に統一し、
    // 文字色などの見た目が正誤のヒントにならないようにする。
    final random = Random.secure();

    final decoyPool = kAffixPool.where((affix) => !correctTexts.contains(affix)).toList()
      ..shuffle(random);
    final decoyCount = kMinDecoyCount + random.nextInt(kMaxDecoyCount - kMinDecoyCount + 1);
    final decoyTexts = decoyPool.take(decoyCount);

    final texts = <String>[for (final p in parts) p.text, ...decoyTexts];
    final correctSlotIndices = <int?>[for (var i = 0; i < parts.length; i++) i, for (var _ in decoyTexts) null];

    final order = List.generate(texts.length, (i) => i)..shuffle(random);

    // 使う画像は、テキストの割り当てとは別に独立してシャッフルする
    // （画像から正解を推測できないようにするため）。kBasicPieceAssetsは
    // 全て同じ凹凸パターンの色違い（6色）なので、どれを選んでも必ずかみ合う。
    // 1問に必要な数が6を超える場合は色が重複するが、ピースの文字が異なる
    // ので区別はできる（6色ぶんをまとめて1周とし、周ごとにシャッフルし直す
    // ことで、同じ色が偏って連続しないようにする）。
    final cycles = (texts.length / kBasicPieceAssets.length).ceil();
    final assets = <String>[
      for (var i = 0; i < cycles; i++) ...(List<String>.from(kBasicPieceAssets)..shuffle(random)),
    ].take(texts.length).toList();

    return [
      for (var displayIndex = 0; displayIndex < order.length; displayIndex++)
        _PieceOption(
          text: texts[order[displayIndex]],
          correctSlotIndex: correctSlotIndices[order[displayIndex]],
          assetPath: assets[displayIndex],
        ),
    ];
  }

  /// 選択肢エリアを大まかなマス目に分け、各ピースを別々のマスの中でランダムにずらして
  /// 配置する（「ジッタード・グリッド」方式）。ランダムに座標を抽選して重なりを都度
  /// 判定する方式だと、ピース数が多いときに間隔を保証できないことがあるため、
  /// マス単位で確実に間隔を確保する。結果は、生成時点の盤面サイズに対する割合
  /// （0.0〜1.0）で返す。
  List<Offset> _generateScatterFractions(Size area) {
    final random = Random();
    final count = _options.length;
    final cols = max(1, sqrt(count).ceil());
    final rows = max(1, (count / cols).ceil());
    final cellWidth = area.width / cols;
    final cellHeight = area.height / rows;
    final jitterX = max(0.0, cellWidth - kPieceSlotWidth);
    final jitterY = max(0.0, cellHeight - kPieceSlotHeight);
    final maxX = max(1.0, area.width - kPieceSlotWidth);
    final maxY = max(1.0, area.height - kPieceSlotHeight);

    final cells = List.generate(cols * rows, (i) => i)..shuffle(random);

    return [
      for (var i = 0; i < count; i++)
        Offset(
          ((cells[i] % cols) * cellWidth + random.nextDouble() * jitterX) / maxX,
          ((cells[i] ~/ cols) * cellHeight + random.nextDouble() * jitterY) / maxY,
        ),
    ];
  }

  void _placeInSlot(int optionIndex, int slotIndex) {
    setState(() {
      _tray.remove(optionIndex);
      for (var j = 0; j < _slots.length; j++) {
        if (_slots[j] == optionIndex) _slots[j] = null;
      }
      final displaced = _slots[slotIndex];
      if (displaced != null) _tray.add(displaced);
      _slots[slotIndex] = optionIndex;
    });
  }

  /// スロットに置かれたピースをタップして選択肢に戻す場合など、ドロップ位置の
  /// 情報がないときに使う（今の散らし位置はそのまま維持する）。
  void _returnToTray(int optionIndex) {
    setState(() {
      for (var j = 0; j < _slots.length; j++) {
        if (_slots[j] == optionIndex) _slots[j] = null;
      }
      if (!_tray.contains(optionIndex)) {
        _tray.add(optionIndex);
      }
    });
  }

  /// 解答欄の外側（選択肢エリアを含む画面全体）にドラッグ＆ドロップしたときに使う。
  /// ドロップした実際の場所を、選択肢エリアに対する割合に変換して保存するので、
  /// 次の描画でもその場所にそのまま留まる。
  void _returnToTrayAt(int optionIndex, Offset globalDropOffset) {
    setState(() {
      final box = _trayAreaKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize && _scatterFractions != null) {
        final local = box.globalToLocal(globalDropOffset);
        final maxX = max(1.0, box.size.width - kPieceSlotWidth);
        final maxY = max(1.0, box.size.height - kPieceSlotHeight);
        _scatterFractions![optionIndex] = Offset(
          (local.dx / maxX).clamp(0.0, 1.0),
          (local.dy / maxY).clamp(0.0, 1.0),
        );
      }

      for (var j = 0; j < _slots.length; j++) {
        if (_slots[j] == optionIndex) _slots[j] = null;
      }
      if (!_tray.contains(optionIndex)) {
        _tray.add(optionIndex);
      }
    });
  }

  void _onAnswerPressed() {
    final partsLength = widget.puzzle.parts.length;
    final isCorrect = List.generate(kSlotCount, (i) {
      final placed = _slots[i];
      if (i >= partsLength) {
        // 使わない末尾スロットは、空のままであることが正解。
        return placed == null;
      }
      if (placed == null) return false;
      final option = _options[placed];
      return !option.isDecoy && option.correctSlotIndex == i;
    }).every((ok) => ok);

    widget.onAnswer(isCorrect);
  }

  void _onHintPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ヒント機能は準備中です')),
    );
  }

  void _onMenuPressed() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    // 解答欄（上部の3枠）の外側であれば、画面のどこにドロップしても選択肢に戻る。
    // スロット自身のDragTarget（より内側）が優先されるので、スロットの上に落とせば
    // ちゃんとそちらが先に受け取る。
    return DragTarget<int>(
      key: const ValueKey('tray_drop_zone'),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => _returnToTrayAt(details.data, details.offset),
      builder: (context, candidateData, rejectedData) {
        return Scaffold(
          backgroundColor: const Color(0xFFFFF8E1),
          body: Stack(
            children: [
              if (widget.backgroundImagePath != null)
                Positioned.fill(
                  child: _ProgressiveRevealBackground(
                    imagePath: widget.backgroundImagePath!,
                    revealedCount: widget.revealedCount,
                    totalCount: widget.totalCount,
                  ),
                ),
              SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Text(
                  '単語を組み立てよう',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF37474F),
                      ),
                ),
                if (widget.progressLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.progressLabel!,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF78909C)),
                  ),
                ],
                const SizedBox(height: 24),
                // 上部：完成形スロット（常に kSlotCount 枠）
                Builder(
                  builder: (context) {
                    // ドラッグの受け皿（当たり判定）は「絵柄が接する」間隔のまま配置する
                    // （hitLefts）。見た目上さらに重ねる分（kExtraOverlap）は、受け皿の
                    // 位置には反映せず、中の絵柄・文字だけをTransform.translateで
                    // ズラして見せる（transformHitTests: falseで当たり判定には影響させない）。
                    // これにより、見た目は重なって見えつつ、隣のスロットのつもりで置いた
                    // ピースが手前のスロットに取られる誤動作を防ぐ。
                    final hitLefts = _hitLefts();
                    final visualLefts = _visualLefts();
                    final rowWidth = hitLefts.last + kPieceSlotWidth;
                    final backgroundWidth = visualLefts.last + kPieceBoxWidth;
                    return SizedBox(
                      height: kPieceSlotHeight,
                      width: rowWidth,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 背景：外枠線を1枚だけ描く。ピースはこの上に重ねて表示する。
                          Positioned(
                            left: kSlotMargin,
                            top: kSlotMargin,
                            child: _SlotRowBackground(width: backgroundWidth),
                          ),
                          // 手前・奥の関係が常に同じになるよう、左のピースが常に手前
                          // （上）に来る順で描画する（Stackは後に描画したものが手前に
                          // なるため、番号の大きい方＝右のピースから先に描画する）。
                          for (var i = kSlotCount - 1; i >= 0; i--)
                            Positioned(
                              left: hitLefts[i],
                              top: 0,
                              child: _SlotTarget(
                                key: ValueKey('slot_$i'),
                                slotIndex: i,
                                placedIndex: _slots[i],
                                placedOption: _slots[i] != null ? _options[_slots[i]!] : null,
                                visualShift: visualLefts[i] - hitLefts[i],
                                onAccept: _placeInSlot,
                                onReturnToTray: _returnToTray,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                // 中央：選択肢（正解ピース＋おとりピース）を、あいているスペースに散らして配置。
                Expanded(
                  key: const ValueKey('piece_tray_area'),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final area = constraints.biggest;
                      _scatterFractions ??= _generateScatterFractions(area);
                      final fractions = _scatterFractions!;
                      final maxX = max(0.0, area.width - kPieceSlotWidth);
                      final maxY = max(0.0, area.height - kPieceSlotHeight);
                      final positions = [
                        for (final f in fractions) Offset(f.dx * maxX, f.dy * maxY),
                      ];
                      return Stack(
                        key: _trayAreaKey,
                        clipBehavior: Clip.none,
                        children: [
                          for (final optionIndex in _tray)
                            Positioned(
                              left: positions[optionIndex].dx,
                              top: positions[optionIndex].dy,
                              child: Draggable<int>(
                                data: optionIndex,
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: PuzzlePieceShape(
                                    text: _options[optionIndex].text,
                                    assetPath: _options[optionIndex].assetPath,
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.3,
                                  child: PuzzlePieceShape(
                                    text: _options[optionIndex].text,
                                    assetPath: _options[optionIndex].assetPath,
                                  ),
                                ),
                                child: PuzzlePieceShape(
                                  text: _options[optionIndex].text,
                                  assetPath: _options[optionIndex].assetPath,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                // 下部ボタン
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Builder(
                    builder: (context) {
                      final buttons = [
                        _BottomButton(
                          label: '?',
                          color: const Color(0xFFB0BEC5),
                          onTap: _onHintPressed,
                          width: 64,
                        ),
                        _BottomButton(
                          label: 'Answer!',
                          color: const Color(0xFFFFB74D),
                          onTap: _onAnswerPressed,
                          width: 140,
                        ),
                        _BottomButton(
                          label: 'Menu',
                          color: const Color(0xFF90A4AE),
                          onTap: _onMenuPressed,
                          width: 96,
                        ),
                      ];
                      // ボタン3つ分の固定幅（64+140+96）より画面が狭いと、通常のRowでは
                      // レイアウトが収まりきらずFlutterのオーバーフロー警告（黄黒の
                      // 縞模様の帯）が表示されてしまう（ウィンドウ幅を狭めたときに再現）。
                      // 十分な幅があるときはこれまで通り均等配置、収まらないときだけ
                      // 横スクロール可能にしてオーバーフローを避ける。
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          const buttonsWidth = 64 + 140 + 96;
                          if (constraints.maxWidth >= buttonsWidth) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: buttons,
                            );
                          }
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 16,
                              children: buttons,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 解答欄ぶんの背景（外枠線のみ）を1枚だけ描く。ピースはこの背景の上に
/// 少しずつ重ねて表示するので、ピース自体には枠を持たせない。ピース同士が
/// 重なって表示されるようになったため、以前あった内側の仕切り線は
/// （重なり位置と合わなくなるため）廃止した。
class _SlotRowBackground extends StatelessWidget {
  const _SlotRowBackground({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, kPieceBoxHeight),
      painter: _SlotRowBackgroundPainter(),
    );
  }
}

class _SlotRowBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(8),
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFFECEFF1));

    final linePaint = Paint()
      ..color = const Color(0xFF37474F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(rrect, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SlotRowBackgroundPainter oldDelegate) => false;
}

class _SlotTarget extends StatelessWidget {
  const _SlotTarget({
    super.key,
    required this.slotIndex,
    required this.placedIndex,
    required this.placedOption,
    required this.visualShift,
    required this.onAccept,
    required this.onReturnToTray,
  });

  final int slotIndex;
  final int? placedIndex;
  final _PieceOption? placedOption;

  /// 絵柄・文字を、当たり判定の位置から見た目だけどれだけ左右にズラして
  /// 見せるか（px）。隣のピースと実際にかぶさって見えるようにするための
  /// 調整で、ドラッグの開始・ドロップ判定の位置には影響しない
  /// （[Transform.translate]の`transformHitTests: false`で分離している）。
  final double visualShift;

  final void Function(int optionIndex, int slotIndex) onAccept;
  final void Function(int optionIndex) onReturnToTray;

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data, slotIndex),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        final option = placedOption;
        final index = placedIndex;

        if (option != null && index != null) {
          final piece = PuzzlePieceShape(
            text: option.text,
            assetPath: option.assetPath,
            highlighted: isHovering,
          );
          final draggingFeedback = PuzzlePieceShape(
            text: option.text,
            assetPath: option.assetPath,
          );
          return Draggable<int>(
            data: index,
            feedback: Material(color: Colors.transparent, child: draggingFeedback),
            childWhenDragging: Opacity(opacity: 0.3, child: piece),
            child: Transform.translate(
              offset: Offset(visualShift, 0),
              transformHitTests: false,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onReturnToTray(index),
                child: piece,
              ),
            ),
          );
        }

        // 空欄のときは背景（外枠線のみ）がそのまま見える。
        // ドラッグ中だけ、その区画に軽くハイライトを重ねる。
        if (!isHovering) {
          return const SizedBox(width: kPieceSlotWidth, height: kPieceSlotHeight);
        }
        return SizedBox(
          width: kPieceSlotWidth,
          height: kPieceSlotHeight,
          child: Padding(
            padding: const EdgeInsets.all(kSlotMargin),
            child: Container(color: const Color(0xFFFFE0B2).withValues(alpha: 0.6)),
          ),
        );
      },
    );
  }
}

class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.label,
    required this.color,
    required this.onTap,
    required this.width,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: const Color(0xFF263238),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
        ),
        child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

/// レベルの背景画像（設計書3.5「進行演出」）を、正解した問題数に応じて
/// マス目単位で少しずつ見せていく。全問正解すると画像が完全に見える。
class _ProgressiveRevealBackground extends StatelessWidget {
  const _ProgressiveRevealBackground({
    required this.imagePath,
    required this.revealedCount,
    required this.totalCount,
  });

  final String imagePath;
  final int revealedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final cols = max(1, sqrt(totalCount).ceil());
    final rows = max(1, (totalCount / cols).ceil());
    final totalCells = cols * rows;
    final revealedCells =
        revealedCount >= totalCount ? totalCells : revealedCount.clamp(0, totalCells);

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(imagePath, fit: BoxFit.cover),
        CustomPaint(
          painter: _RevealMaskPainter(cols: cols, rows: rows, revealedCells: revealedCells),
          size: Size.infinite,
        ),
      ],
    );
  }
}

class _RevealMaskPainter extends CustomPainter {
  _RevealMaskPainter({required this.cols, required this.rows, required this.revealedCells});

  final int cols;
  final int rows;
  final int revealedCells;

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / cols;
    final cellHeight = size.height / rows;
    final maskPaint = Paint()..color = const Color(0xFFFFF8E1);

    // マス目ごとに独立してdrawRectすると、cellWidth/cellHeightが割り切れない
    // 端数を持つ場合に、隣接するマス同士の境界がピクセル単位でぴったり
    // 合わず、同じ色で塗っているにもかかわらず継ぎ目が細い線として見えて
    // しまう（背景の風景画像がそこだけ透けて見える）。各マスを少しだけ
    // 大きめに描く（隣と重ねる）ことで、この継ぎ目をなくす。
    const overlap = 1.0;
    var index = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (index >= revealedCells) {
          canvas.drawRect(
            Rect.fromLTWH(
              c * cellWidth - overlap,
              r * cellHeight - overlap,
              cellWidth + overlap * 2,
              cellHeight + overlap * 2,
            ),
            maskPaint,
          );
        }
        index++;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RevealMaskPainter oldDelegate) =>
      oldDelegate.cols != cols ||
      oldDelegate.rows != rows ||
      oldDelegate.revealedCells != revealedCells;
}
