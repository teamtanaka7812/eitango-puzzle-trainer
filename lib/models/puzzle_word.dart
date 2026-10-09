import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// パズルの1ピース（接頭辞・語根・接尾辞のいずれか）。色は表示直前（GameScreen側）で
/// シャッフル後の並び順に応じて割り当てるため、ここではテキストのみを持つ。
class WordPiecePart {
  const WordPiecePart({required this.text});

  final String text;
}

/// あらかじめ用意された選択肢の1ピース分（テキストと、使う画像ファイルの組）。
/// 正解・おとりを問わず、この単語の選択肢エリアに表示する全ピースをここに列挙する。
class ChoicePiece {
  const ChoicePiece({required this.text, required this.assetPath});

  final String text;

  /// 完全なアセットパス（例: assets/puzzle_pieces_v3/stem_g_1.png）。
  final String assetPath;
}

/// 出題される単語データ。ピース数は単語によって2つ・3つと可変。
class PuzzleWord {
  const PuzzleWord({
    required this.id,
    required this.word,
    required this.level,
    required this.parts,
    required this.meaning,
    required this.exampleEn,
    required this.exampleJa,
    required this.presetChoices,
  });

  final String id;
  final String word;
  final int level;
  final List<WordPiecePart> parts;
  final String meaning;
  final String exampleEn;
  final String exampleJa;

  /// この単語の選択肢一式（正解ピース・おとりピース。テキスト・画像とも固定）。
  /// 全参加者が同じ刺激を見るよう、実行時に抽選せずデータ側で決めてある。
  /// 画像名には役割と形の番号が含まれる（`pre_1.png`・`stem_g_1.png`・
  /// `suf_1.png`など）。おとりにも役割を均等に割り当て、形から正解が
  /// 分からないようにしてある。
  final List<ChoicePiece> presetChoices;
}

/// assets/data/words.json を読み込み、レベルごとの単語リストに変換する。
class WordRepository {
  static Map<int, List<PuzzleWord>>? _cache;

  static Future<Map<int, List<PuzzleWord>>> loadByLevel() async {
    if (_cache != null) return _cache!;

    final jsonString = await rootBundle.loadString('assets/data/words.json');
    final List<dynamic> rawList = jsonDecode(jsonString);

    final result = <int, List<PuzzleWord>>{};
    for (final raw in rawList) {
      final map = raw as Map<String, dynamic>;
      // 出題から外した問題（`"retired": true`）は読み込まない。番号・形の割り当てを
      // 変えないよう、データ自体は words.json に残してある。
      if (map['retired'] == true) continue;
      final parts = <WordPiecePart>[
        for (final text in map['parts'] as List) WordPiecePart(text: text as String),
      ];
      final presetChoices = <ChoicePiece>[
        for (final c in map['choices'] as List<dynamic>)
          ChoicePiece(
            text: (c as Map<String, dynamic>)['text'] as String,
            assetPath: 'assets/puzzle_pieces_v3/${c['image']}',
          ),
      ];
      final puzzleWord = PuzzleWord(
        id: map['id'] as String,
        word: map['word'] as String,
        level: map['level'] as int,
        parts: parts,
        meaning: map['meaningJa'] as String,
        exampleEn: map['exampleEn'] as String,
        exampleJa: map['exampleJa'] as String,
        presetChoices: presetChoices,
      );
      result.putIfAbsent(puzzleWord.level, () => []).add(puzzleWord);
    }
    _cache = result;
    return result;
  }
}
