import 'package:flutter/material.dart';

import '../models/puzzle_word.dart';
import 'game_screen.dart';
import 'result_screen.dart';

/// レベルごとの進行演出（設計書3.5）用の背景画像。
/// image31=タージマハル、image33=雪の村、image35=モアイ像。
const Map<int, String> kLevelBackgroundImages = {
  1: 'assets/backgrounds/image31.png',
  2: 'assets/backgrounds/image33.png',
  3: 'assets/backgrounds/image35.png',
};

/// 指定レベルの単語リストを管理し、1問ずつGameScreenに渡して進行させる画面。
/// 全問終わったら、レベル選択画面（1つ前の画面）に戻る。
class LevelPlayScreen extends StatefulWidget {
  const LevelPlayScreen({super.key, required this.level});

  final int level;

  @override
  State<LevelPlayScreen> createState() => _LevelPlayScreenState();
}

class _LevelPlayScreenState extends State<LevelPlayScreen> {
  List<PuzzleWord>? _words;
  int _currentIndex = 0;
  int _attempt = 0;

  /// これまでに正解した問題の番号（インデックス）。背景の進行演出に使う。
  /// 同じ問題を再挑戦して正解しても増えない（Setなので重複しない）。
  final Set<int> _correctWordIndices = {};

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    final byLevel = await WordRepository.loadByLevel();
    if (!mounted) return;
    setState(() {
      _words = byLevel[widget.level] ?? [];
    });
  }

  Future<void> _handleAnswer(bool isCorrect) async {
    final words = _words!;
    final isLastWord = _currentIndex == words.length - 1;

    if (isCorrect) {
      setState(() => _correctWordIndices.add(_currentIndex));
    }

    final action = await Navigator.of(context).push<ResultAction>(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          puzzle: words[_currentIndex],
          isCorrect: isCorrect,
          isLastWord: isLastWord,
        ),
      ),
    );

    if (!mounted) return;

    if (action == ResultAction.retry) {
      setState(() => _attempt++);
    } else if (action == ResultAction.next) {
      if (isLastWord) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _currentIndex++;
          _attempt = 0;
        });
      }
    }
    // action == null（「ホームに戻る」で全画面をpopUntilした場合など）は何もしない。
  }

  @override
  Widget build(BuildContext context) {
    final words = _words;
    if (words == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (words.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Level ${widget.level}')),
        body: const Center(child: Text('このレベルにはまだ単語が登録されていません')),
      );
    }

    return GameScreen(
      key: ValueKey('word_${_currentIndex}_attempt_$_attempt'),
      puzzle: words[_currentIndex],
      onAnswer: _handleAnswer,
      progressLabel: 'Level ${widget.level} － ${_currentIndex + 1} / ${words.length} 問目',
      backgroundImagePath: kLevelBackgroundImages[widget.level],
      revealedCount: _correctWordIndices.length,
      totalCount: words.length,
    );
  }
}
