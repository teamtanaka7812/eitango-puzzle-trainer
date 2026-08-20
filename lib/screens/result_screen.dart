import 'package:flutter/material.dart';

import '../models/puzzle_word.dart';
import '../services/sound_service.dart';

/// 結果画面のボタン操作を呼び出し元（LevelPlayScreen）に伝えるための戻り値。
enum ResultAction { retry, next }

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.puzzle,
    required this.isCorrect,
    required this.isLastWord,
  });

  final PuzzleWord puzzle;
  final bool isCorrect;

  /// そのレベルの最後の単語かどうか。trueの場合、主ボタンの表示を「レベル選択に戻る」に変える。
  final bool isLastWord;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();

    if (widget.isCorrect) {
      playCorrectSound();
    } else {
      playIncorrectSound();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCorrect = widget.isCorrect;
    final puzzle = widget.puzzle;
    final accentColor = isCorrect ? const Color(0xFF42A5F5) : const Color(0xFFEF5350);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      isCorrect ? 'assets/characters/image20.png' : 'assets/characters/image21.png',
                      width: 140,
                      height: 140,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 12),
                    Icon(
                      isCorrect ? Icons.circle_outlined : Icons.close,
                      color: accentColor,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isCorrect ? 'Correct!' : 'Incorrect!',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isCorrect ? 'Good job!' : 'Keep going!',
                      style: const TextStyle(fontSize: 18, color: Color(0xFF37474F)),
                    ),
                    const SizedBox(height: 28),
                    _SpeakableText(
                      text: puzzle.word,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF37474F),
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFFB0BEC5),
                      ),
                      iconSize: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      puzzle.meaning,
                      style: const TextStyle(fontSize: 18, color: Color(0xFF546E7A)),
                    ),
                    const SizedBox(height: 20),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SpeakableText(
                          text: puzzle.exampleEn,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFFB0BEC5),
                          ),
                          iconSize: 18,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          puzzle.exampleJa,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF78909C), height: 1.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 220,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(ResultAction.next),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB74D),
                          foregroundColor: const Color(0xFF263238),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          widget.isLastWord ? 'レベル選択に戻る' : '次の問題へ',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 220,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(ResultAction.retry),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF90CAF9),
                          foregroundColor: const Color(0xFF263238),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('もう一度挑戦する', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                      child: const Text('ホームに戻る'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// タップすると英語の音声合成で読み上げるテキスト。タップできる範囲が分かる
/// よう、下線とスピーカーアイコンを添える。
class _SpeakableText extends StatelessWidget {
  const _SpeakableText({
    required this.text,
    required this.style,
    required this.iconSize,
  });

  final String text;
  final TextStyle style;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => speak(text),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Row(
          // 長い単語・例文でも折り返しが効くよう、テキストはExpandedで
          // 幅を確保する（Flexible+mainAxisSize.minだと、Rowの子には
          // 主軸方向に無制限の幅が渡ってしまい折り返さないため）。
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(text, style: style)),
            const SizedBox(width: 6),
            Icon(Icons.volume_up_rounded, size: iconSize, color: const Color(0xFF78909C)),
          ],
        ),
      ),
    );
  }
}
