import 'package:flutter/material.dart';

/// 案内役の羊キャラクター。タップすると吹き出しでメッセージを表示する。
class SheepGuide extends StatefulWidget {
  const SheepGuide({
    super.key,
    this.messages = const [
      'やあ！いっしょに単語パズルに挑戦しよう！',
      'STARTボタンを押すとレベルが選べるよ。',
      '困ったときは「?」ヒントを使ってね。',
    ],
    this.size = 140,
  });

  final List<String> messages;
  final double size;

  @override
  State<SheepGuide> createState() => _SheepGuideState();
}

class _SheepGuideState extends State<SheepGuide> {
  bool _showBubble = false;
  int _messageIndex = 0;

  void _onTap() {
    setState(() {
      _showBubble = true;
      _messageIndex = (_messageIndex + 1) % widget.messages.length;
    });
  }

  void _dismissBubble() {
    if (_showBubble) {
      setState(() => _showBubble = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_showBubble)
          GestureDetector(
            onTap: _dismissBubble,
            child: Container(
              constraints: BoxConstraints(maxWidth: widget.size * 1.8),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF5B9BD5), width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Text(
                widget.messages[_messageIndex],
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
          ),
        GestureDetector(
          onTap: _onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/characters/image2.png',
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ],
    );
  }
}
