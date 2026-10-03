import 'package:word_puzzle_trainer/models/puzzle_word.dart';

const _dir = 'assets/puzzle_pieces_v3';

/// 2ピースの単語（前置 + 語幹）。おとりは前置・語幹・後置の形を1個ずつ。
const twoPiecePuzzle = PuzzleWord(
  id: 'test-unhappy',
  word: 'unhappy',
  level: 1,
  parts: [
    WordPiecePart(text: 'un'),
    WordPiecePart(text: 'happy'),
  ],
  meaning: '不幸な',
  exampleEn: 'example sentence',
  exampleJa: '例文',
  presetChoices: [
    ChoicePiece(text: 'un', assetPath: '$_dir/pre_1.png'),
    ChoicePiece(text: 'happy', assetPath: '$_dir/stem_g_1.png'),
    ChoicePiece(text: 'dis', assetPath: '$_dir/pre_1.png'),
    ChoicePiece(text: 'kind', assetPath: '$_dir/stem_y_1.png'),
    ChoicePiece(text: 'ful', assetPath: '$_dir/suf_1.png'),
  ],
);

/// 3ピースの単語（前置 + 語幹 + 後置）。おとりは各役割1個 + 前置1個の4個。
const threePiecePuzzle = PuzzleWord(
  id: 'test-combination',
  word: 'combination',
  level: 1,
  parts: [
    WordPiecePart(text: 'com'),
    WordPiecePart(text: 'bina'),
    WordPiecePart(text: 'tion'),
  ],
  meaning: '結合',
  exampleEn: 'example sentence',
  exampleJa: '例文',
  presetChoices: [
    ChoicePiece(text: 'com', assetPath: '$_dir/pre_3.png'),
    ChoicePiece(text: 'bina', assetPath: '$_dir/stem_g_3.png'),
    ChoicePiece(text: 'tion', assetPath: '$_dir/suf_3.png'),
    ChoicePiece(text: 'pro', assetPath: '$_dir/pre_3.png'),
    ChoicePiece(text: 'vent', assetPath: '$_dir/stem_y_3.png'),
    ChoicePiece(text: 'ment', assetPath: '$_dir/suf_3.png'),
    ChoicePiece(text: 're', assetPath: '$_dir/pre_3.png'),
  ],
);
