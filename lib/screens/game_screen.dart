import 'dart:math';

import 'package:flutter/material.dart';

import '../models/puzzle_word.dart';
import '../services/learning_record_service.dart';
import '../services/local_history_service.dart';
import '../widgets/piece_row_layout.dart';
import '../widgets/puzzle_piece_shape.dart';

/// ドラッグ中のピースが近づいた解答欄の枠をハイライトする色（塗り・縁取り）。
const Color kDropHighlightColor = Color(0xFFFFA726);
const Color kDropHighlightBorderColor = Color(0xFFE65100);

/// 選択肢に並ぶ1ピース分。正解ピースか、おとりピースかを区別する。
class _PieceOption {
  _PieceOption({
    required this.text,
    required this.assetPath,
    required this.correctSlotIndex,
  }) : fit = PieceFit.of(assetPath, text);

  final String text;

  /// 文字の長さに合わせて横に伸ばした、このピースの表示寸法。
  final PieceFit fit;

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

  /// 解答欄の外枠の寸法 (問題に登場する全ピースの形から1度だけ求める)。
  late final RowMetrics _rowMetrics;

  /// 選択肢エリアで1ピースが占める最大の大きさ (全ピースの最大の幅・高さ)。
  /// 文字が長いほどピースは横に伸びるので、問題ごとに決まる。
  late final Size _trayCell;

  /// この問題の画面が表示され始めた日時（研究データ用、2026年9月追加）。
  /// [GameScreen]は新しい問題に進む・再挑戦するたびに`LevelPlayScreen`側で
  /// 新しいインスタンスとして作り直される（`key`にインデックス・挑戦回数を
  /// 含めている）ため、`initState()`の時点を「その問題の開始時刻」として
  /// 扱う。[LearningRecordService.recordAttempt]の`startedAt`・
  /// `durationSeconds`の算出に使う。
  late final DateTime _startedAt;

  /// この問題を解いている間に、ピースをドラッグしてどこかに離した回数
  /// （研究データ用、2026年9月追加）。解答欄への設置・盤面内での置き直し・
  /// トレイへの取り出しのいずれでも、ドラッグ操作1回につき1加算する
  /// （[Draggable.onDragEnd]は結果によらず必ず1回呼ばれるため、これを使う）。
  /// 画面には表示しないため、加算のたびに[setState]は呼ばない。
  int _dragCount = 0;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _options = _buildOptions();
    _rowMetrics = RowMetrics.of(_options.map((o) => o.fit));
    _trayCell = maxPieceSize(_options.map((o) => o.fit));
    _tray = List.generate(_options.length, (i) => i);
    // 解答欄の枠数は、その問題の正解ピース数（2または3）に合わせる。
    _slots = List<int?>.filled(widget.puzzle.parts.length, null);
  }

  /// 単語データに用意された選択肢（正解ピース・おとりピース。テキスト・画像とも
  /// 固定）をそのまま使う。全参加者が同じ刺激（形・色・文字）を見るよう、
  /// おとりや画像は実行時に抽選せずデータ側で決めてある。表示順だけは
  /// シャッフルする（正誤の並びが常に同じにならないようにするため）。
  List<_PieceOption> _buildOptions() {
    final choices = widget.puzzle.presetChoices;
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

  /// 選択肢エリアの横幅から、ピース同士が重ならないマス目の列数・行数を決める。
  /// 1マスの大きさは、この問題で最も大きい（＝文字が最も長い）ピースに合わせる
  /// （[_trayCell]）。ピースは画像読み込み前後を問わずドラッグを取りこぼさない
  /// よう、出っ張りまで含む透明な当たり判定を常に持っている
  /// （`puzzle_piece_shape.dart`）ため、マスが詰まると隣のピースの当たり判定が
  /// 絵柄に覆いかぶさり、クリックしたピースとは別のピースがドラッグされて
  /// しまう（2026年時点で発見・修正）。そのため列数は横幅を[_trayCell]の幅で
  /// 割り切れる数までしか作らず、行の高さは常に[_trayCell]の高さ以上を確保する
  /// （縦に収まりきらない分は、選択肢エリア全体を縦スクロール可能にして表示する。
  /// [_trayContentHeight]参照）。
  int _trayColumnCount(double areaWidth) {
    return max(1, (areaWidth / _trayCell.width).floor());
  }

  /// [_trayColumnCount]の列数で選択肢[count]個を並べたときに必要な行数。
  int _trayRowCount(double areaWidth, int count) {
    return max(1, (count / _trayColumnCount(areaWidth)).ceil());
  }

  /// 選択肢エリアの実際の描画高さ。選択肢を並べるのに必要な高さ（行数×
  /// [_trayCell]の高さ）が表示エリアの高さより大きい場合は、その必要な高さを
  /// 使う（＝縦スクロールで全ピースに届くようにする）。
  double _trayContentHeight(Size area, int count) {
    final rows = _trayRowCount(area.width, count);
    return max(area.height, rows * _trayCell.height);
  }

  /// 選択肢エリアを大まかなマス目に分け、各ピースを別々のマスの中でランダムにずらして
  /// 配置する（「ジッタード・グリッド」方式）。ランダムに座標を抽選して重なりを都度
  /// 判定する方式だと、ピース数が多いときに間隔を保証できないことがあるため、
  /// マス単位で確実に間隔を確保する。結果は、生成時点の盤面サイズ（横幅は表示
  /// エリアそのまま、縦は[_trayContentHeight]）に対する割合（0.0〜1.0）で返す。
  List<Offset> _generateScatterFractions(Size area) {
    final random = Random();
    final count = _options.length;
    final cols = _trayColumnCount(area.width);
    final rows = _trayRowCount(area.width, count);
    final contentHeight = _trayContentHeight(area, count);
    final cellWidth = area.width / cols;
    final cellHeight = contentHeight / rows;
    final jitterX = max(0.0, cellWidth - _trayCell.width);
    final jitterY = max(0.0, cellHeight - _trayCell.height);
    final maxX = max(1.0, area.width - _trayCell.width);
    final maxY = max(1.0, contentHeight - _trayCell.height);

    final cells = List.generate(cols * rows, (i) => i)..shuffle(random);

    return [
      for (var i = 0; i < count; i++)
        Offset(
          ((cells[i] % cols) * cellWidth + random.nextDouble() * jitterX) /
              maxX,
          ((cells[i] ~/ cols) * cellHeight + random.nextDouble() * jitterY) /
              maxY,
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
        final maxX = max(1.0, box.size.width - _trayCell.width);
        final maxY = max(1.0, box.size.height - _trayCell.height);
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
    final isCorrect = List.generate(_slots.length, (i) {
      final placed = _slots[i];
      if (placed == null) return false;
      final option = _options[placed];
      return !option.isDecoy && option.correctSlotIndex == i;
    }).every((ok) => ok);

    // 学習記録の保存は、結果を待たずに裏側で行う（通信状況・端末保存の
    // 遅延に関わらず、正誤判定・画面遷移といったゲーム本体の動作を
    // 止めたり遅らせたりしないため）。
    LocalHistoryService.recordAttempt(level: widget.puzzle.level, isCorrect: isCorrect);
    LearningRecordService.recordAttempt(
      puzzle: widget.puzzle,
      isCorrect: isCorrect,
      startedAt: _startedAt,
      durationSeconds:
          DateTime.now().difference(_startedAt).inMilliseconds / 1000,
      dragCount: _dragCount,
    );

    widget.onAnswer(isCorrect);
  }

  void _onHintPressed() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ヒント機能は準備中です')));
  }

  void _onMenuPressed() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 空欄のスロットが連続する区間 (背景の枠を描く単位)。
  List<_EmptyRun> _emptyRuns(RowLayout layout) {
    final runs = <_EmptyRun>[];
    var i = 0;
    while (i < _slots.length) {
      if (_slots[i] != null) {
        i++;
        continue;
      }
      final start = i;
      while (i < _slots.length && _slots[i] == null) {
        i++;
      }
      final first = layout.slots[start];
      final last = layout.slots[i - 1];
      runs.add(_EmptyRun(
        left: first.bodyLeft,
        width: last.bodyLeft + last.bodyWidth - first.bodyLeft,
        startsAtRowEdge: start == 0,
        endsAtRowEdge: i == _slots.length,
        // 空欄が連続しているときは、枠の数が分かるように枠の境目に仕切り線を引く。
        dividers: [
          for (var k = start + 1; k < i; k++) layout.slots[k].bodyLeft - first.bodyLeft,
        ],
      ));
    }
    return runs;
  }

  /// 解答欄（枠数は正解ピース数と同じ、2または3枠）。
  ///
  /// 隣り合うピースは、本体（四角い部分）の左右の端をぴったり突き合わせて並べる。
  /// 出っ張りと凹みはこれでかみ合うので、重なり幅を調整する必要はない。文字の
  /// 長いピースは本体が横に伸びる（[PieceFit.extra]）ぶん、右隣以降が押し出される。
  /// ドラッグの受け皿（当たり判定）も本体の矩形そのもので、スロット同士は
  /// 重ならない（出っ張りの部分は隣のスロットの範囲に入る）。
  ///
  /// 3枠とも長いピースが入ると画面幅を超えることがある。その場合は
  /// 全体を縮小して収める（[FittedBox]。当たり判定も一緒に縮小される）。
  Widget _buildAnswerRow() {
    final fits = [
      for (final i in _slots) i == null ? null : _options[i].fit,
    ];
    final layout = layoutRow(fits, _rowMetrics);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: layout.width,
        height: _rowMetrics.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 背景：空欄のスロットの区画だけに枠を描く（ピースが半透明なので、
            // ピースの下にも枠を描くと線が透けて見える）。空欄が連続する区間は
            // 1つの枠にまとめる。
            for (final run in _emptyRuns(layout))
              Positioned(
                left: run.left,
                top: _rowMetrics.topPad,
                child: _SlotRowBackground(
                  width: run.width,
                  height: kEmptySlotBodyHeight,
                  roundLeft: run.startsAtRowEdge,
                  roundRight: run.endsAtRowEdge,
                  dividers: run.dividers,
                ),
              ),
            // 継ぎ目で出っ張りを持つ方が手前になる順に描画する。
            for (final i in layout.paintOrder)
              Positioned(
                key: ValueKey('slot_position_$i'),
                left: layout.slots[i].bodyLeft,
                top: 0,
                child: _SlotTarget(
                  key: ValueKey('slot_$i'),
                  slotIndex: i,
                  placedIndex: _slots[i],
                  placedOption: _slots[i] != null ? _options[_slots[i]!] : null,
                  width: layout.slots[i].bodyWidth,
                  height: _rowMetrics.height,
                  emptyTop: _rowMetrics.topPad,
                  // ピース画像の左上の、スロット(本体の左端・行の上端)から見た位置。
                  pieceOffset: _slots[i] == null
                      ? Offset.zero
                      : Offset(
                          -_options[_slots[i]!].fit.geometry.bodyLeftPx,
                          layout.slots[i].pieceTop!,
                        ),
                  onAccept: _placeInSlot,
                  onReturnToTray: _returnToTray,
                  onDragCompleted: () => _dragCount++,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 解答欄（上部の3枠）の外側であれば、画面のどこにドロップしても選択肢に戻る。
    // スロット自身のDragTarget（より内側）が優先されるので、スロットの上に落とせば
    // ちゃんとそちらが先に受け取る。
    return DragTarget<int>(
      key: const ValueKey('tray_drop_zone'),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) =>
          _returnToTrayAt(details.data, details.offset),
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
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF78909C),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    // 上部：完成形スロット（正解ピース数と同じ枠数）
                    _buildAnswerRow(),
                    const SizedBox(height: 8),
                    // 中央：選択肢（正解ピース＋おとりピース）を、あいているスペースに散らして配置。
                    Expanded(
                      key: const ValueKey('piece_tray_area'),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final area = constraints.biggest;
                          _scatterFractions ??= _generateScatterFractions(area);
                          final fractions = _scatterFractions!;
                          final contentHeight = _trayContentHeight(
                            area,
                            _options.length,
                          );
                          final maxX = max(0.0, area.width - _trayCell.width);
                          final maxY = max(
                            0.0,
                            contentHeight - _trayCell.height,
                          );
                          final positions = [
                            for (final f in fractions)
                              Offset(f.dx * maxX, f.dy * maxY),
                          ];
                          // 選択肢の数が多い・画面が縦に狭いなどの理由でピースが
                          // 重ならずに収まりきらない場合は、縦スクロールで全ピースに
                          // 届くようにする（contentHeightがareaの高さを上回るとき）。
                          return SingleChildScrollView(
                            physics: contentHeight > area.height
                                ? const ClampingScrollPhysics()
                                : const NeverScrollableScrollPhysics(),
                            child: SizedBox(
                              width: area.width,
                              height: contentHeight,
                              child: Stack(
                                key: _trayAreaKey,
                                clipBehavior: Clip.none,
                                children: [
                                  for (final optionIndex in _tray)
                                    Positioned(
                                      key: ValueKey('tray_piece_$optionIndex'),
                                      left: positions[optionIndex].dx,
                                      top: positions[optionIndex].dy,
                                      child: Draggable<int>(
                                        data: optionIndex,
                                        onDragEnd: (_) => _dragCount++,
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: PuzzlePieceShape(
                                            text: _options[optionIndex].text,
                                            assetPath:
                                                _options[optionIndex].assetPath,
                                          ),
                                        ),
                                        childWhenDragging: Opacity(
                                          opacity: 0.3,
                                          child: PuzzlePieceShape(
                                            text: _options[optionIndex].text,
                                            assetPath:
                                                _options[optionIndex].assetPath,
                                          ),
                                        ),
                                        child: PuzzlePieceShape(
                                          text: _options[optionIndex].text,
                                          assetPath:
                                              _options[optionIndex].assetPath,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // 下部ボタン
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
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

/// 空欄のスロットが連続する区間。
class _EmptyRun {
  const _EmptyRun({
    required this.left,
    required this.width,
    required this.startsAtRowEdge,
    required this.endsAtRowEdge,
    required this.dividers,
  });

  final double left;
  final double width;
  final bool startsAtRowEdge;
  final bool endsAtRowEdge;

  /// 区間の左端から、枠の境目までの距離。
  final List<double> dividers;
}

/// 空欄のスロット区間の背景（枠線つき）。ピースと接する側は角を丸めず、
/// 解答欄の左右の端にあたる側だけ丸める。
class _SlotRowBackground extends StatelessWidget {
  const _SlotRowBackground({
    required this.width,
    required this.height,
    required this.roundLeft,
    required this.roundRight,
    required this.dividers,
  });

  final double width;
  final double height;
  final bool roundLeft;
  final bool roundRight;
  final List<double> dividers;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _SlotRowBackgroundPainter(
        roundLeft: roundLeft,
        roundRight: roundRight,
        dividers: dividers,
      ),
    );
  }
}

class _SlotRowBackgroundPainter extends CustomPainter {
  _SlotRowBackgroundPainter({
    required this.roundLeft,
    required this.roundRight,
    required this.dividers,
  });

  final bool roundLeft;
  final bool roundRight;
  final List<double> dividers;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(8);
    final rrect = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, size.width, size.height),
      topLeft: roundLeft ? radius : Radius.zero,
      bottomLeft: roundLeft ? radius : Radius.zero,
      topRight: roundRight ? radius : Radius.zero,
      bottomRight: roundRight ? radius : Radius.zero,
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFFECEFF1));

    final linePaint = Paint()
      ..color = const Color(0xFF37474F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(rrect, linePaint);
    for (final x in dividers) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SlotRowBackgroundPainter old) =>
      old.roundLeft != roundLeft ||
      old.roundRight != roundRight ||
      old.dividers.length != dividers.length ||
      old.dividers.indexed.any((e) => e.$2 != dividers[e.$1]);
}

class _SlotTarget extends StatefulWidget {
  const _SlotTarget({
    super.key,
    required this.slotIndex,
    required this.placedIndex,
    required this.placedOption,
    required this.width,
    required this.height,
    required this.emptyTop,
    required this.pieceOffset,
    required this.onAccept,
    required this.onReturnToTray,
    required this.onDragCompleted,
  });

  final int slotIndex;
  final int? placedIndex;
  final _PieceOption? placedOption;

  /// このスロットの当たり判定（クリック・ドラッグ開始・ドロップを受け付ける範囲）。
  /// 幅はピースの本体の幅そのもので、隣のスロットとは重ならない。高さは
  /// 上下の出っ張りまで含む解答欄の高さいっぱい。
  ///
  /// 以前は隣のピースと絵柄を重ねて見せていたため、当たり判定を絵柄の重なりに
  /// 合わせて細かく調整する必要があった（隣のピースを掴もうとして手前のピースを
  /// 掴んでしまう不具合が繰り返し起きた）。本体どうしを突き合わせる方式にして、
  /// 当たり判定は単純に「自分の本体の矩形」だけで済む。
  final double width;
  final double height;

  /// 空欄のとき、ドロップ候補をハイライトする枠の上端（解答欄の上端から）。
  final double emptyTop;

  /// ピース画像の左上の位置（このスロットの左上から見た座標）。左の出っ張りの
  /// ぶん x は負になり、画像の一部が左隣のスロットの範囲に入ることがある。
  final Offset pieceOffset;

  final void Function(int optionIndex, int slotIndex) onAccept;
  final void Function(int optionIndex) onReturnToTray;

  /// このスロットのピースを1回ドラッグして離すたびに呼ぶ（研究データ用の
  /// 操作回数カウント、[_GameScreenState._dragCount]参照）。結果（解答欄への
  /// 設置・盤面内での置き直し・トレイへの取り出し）によらず呼ぶ。
  final VoidCallback onDragCompleted;

  @override
  State<_SlotTarget> createState() => _SlotTargetState();
}

class _SlotTargetState extends State<_SlotTarget> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) =>
          widget.onAccept(details.data, widget.slotIndex),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        final option = widget.placedOption;
        final index = widget.placedIndex;

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
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 見た目専用レイヤー：出っ張りの部分は隣のスロットの範囲に
                // はみ出して描画される。当たり判定は持たせない（IgnorePointer）。
                // 自分自身のドラッグ中は、以前と同じく薄く表示する。
                Positioned(
                  left: widget.pieceOffset.dx,
                  top: widget.pieceOffset.dy,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: _isDragging ? 0.3 : 1.0,
                      child: piece,
                    ),
                  ),
                ),
                // 当たり判定専用レイヤー：本体の矩形ぶん。
                Positioned.fill(
                  child: Draggable<int>(
                    data: index,
                    onDragStarted: () => setState(() => _isDragging = true),
                    onDragEnd: (_) {
                      setState(() => _isDragging = false);
                      widget.onDragCompleted();
                    },
                    onDraggableCanceled: (_, _) =>
                        setState(() => _isDragging = false),
                    feedback: Material(
                      color: Colors.transparent,
                      child: draggingFeedback,
                    ),
                    childWhenDragging: const SizedBox.shrink(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onReturnToTray(index),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // 空欄のときは背景（外枠線のみ）がそのまま見える。
        // ドラッグ中だけ、その区画に軽くハイライトを重ねる。
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: isHovering
              ? Padding(
                  padding: EdgeInsets.only(
                    top: widget.emptyTop,
                    bottom: widget.height - widget.emptyTop - kEmptySlotBodyHeight,
                  ),
                  // 「ここに置けます」の表示。灰色の枠・クリーム色の背景・ピースの色
                  // （赤・緑・黄・水色）のどれとも見分けがつくよう、濃いオレンジの
                  // 塗りと太い縁取りにしている。
                  child: Container(
                    decoration: BoxDecoration(
                      color: kDropHighlightColor.withValues(alpha: 0.85),
                      border: Border.all(color: kDropHighlightBorderColor, width: 3),
                      // ドラッグ中のピースは枠より大きく、真上に来ると枠が隠れるので、
                      // 外側にも光がはみ出して見えるようにする。
                      boxShadow: [
                        BoxShadow(
                          color: kDropHighlightColor.withValues(alpha: 0.9),
                          blurRadius: 10,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                )
              : null,
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 3,
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
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
    final revealedCells = revealedCount >= totalCount
        ? totalCells
        : revealedCount.clamp(0, totalCells);

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(imagePath, fit: BoxFit.cover),
        CustomPaint(
          painter: _RevealMaskPainter(
            cols: cols,
            rows: rows,
            revealedCells: revealedCells,
          ),
          size: Size.infinite,
        ),
      ],
    );
  }
}

class _RevealMaskPainter extends CustomPainter {
  _RevealMaskPainter({
    required this.cols,
    required this.rows,
    required this.revealedCells,
  });

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
