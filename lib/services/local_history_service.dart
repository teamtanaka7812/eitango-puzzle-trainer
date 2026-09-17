import 'package:shared_preferences/shared_preferences.dart';

/// Level 1〜3、それぞれの解答数・正解数。
class LevelHistoryStats {
  const LevelHistoryStats({required this.answered, required this.correct});

  final int answered;
  final int correct;

  /// 正答率（0.0〜1.0）。1問も解いていなければnull。
  double? get accuracy => answered == 0 ? null : correct / answered;
}

/// HISTORY画面に表示する集計値一式。
class HistoryStats {
  const HistoryStats({required this.totalAnswered, required this.totalCorrect, required this.byLevel});

  final int totalAnswered;
  final int totalCorrect;

  /// レベル番号（1〜3）ごとの内訳。
  final Map<int, LevelHistoryStats> byLevel;

  double? get totalAccuracy => totalAnswered == 0 ? null : totalCorrect / totalAnswered;
}

/// 学習履歴（解答数・正解数）を端末内（[SharedPreferences]）に集計値として
/// 保存する。HISTORY画面はネットワーク接続がなくても表示できるよう、
/// これを主なデータ源として使う（Firestoreへの送信は研究データ収集用の
/// 別経路であり、HISTORY画面の表示には使わない。
/// [LearningRecordService]を参照）。
///
/// 1件ずつの解答履歴（いつ・どの単語を、など）ではなく、レベルごとの
/// 「解答数」「正解数」の合計だけを持つ（HISTORY画面の表示要件が
/// 集計値のみのため。データ量が増え続けないという利点もある）。
class LocalHistoryService {
  static String _answeredKey(int level) => 'history_level_${level}_answered';
  static String _correctKey(int level) => 'history_level_${level}_correct';

  static const _levels = [1, 2, 3];

  /// 1問答えるたびに呼ぶ。レベル別・合計の集計値を1つずつ加算する。
  static Future<void> recordAttempt({required int level, required bool isCorrect}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_answeredKey(level), (prefs.getInt(_answeredKey(level)) ?? 0) + 1);
    if (isCorrect) {
      await prefs.setInt(_correctKey(level), (prefs.getInt(_correctKey(level)) ?? 0) + 1);
    }
  }

  /// HISTORY画面表示用に、集計値をまとめて読み出す。
  static Future<HistoryStats> loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    var totalAnswered = 0;
    var totalCorrect = 0;
    final byLevel = <int, LevelHistoryStats>{};
    for (final level in _levels) {
      final answered = prefs.getInt(_answeredKey(level)) ?? 0;
      final correct = prefs.getInt(_correctKey(level)) ?? 0;
      byLevel[level] = LevelHistoryStats(answered: answered, correct: correct);
      totalAnswered += answered;
      totalCorrect += correct;
    }
    return HistoryStats(totalAnswered: totalAnswered, totalCorrect: totalCorrect, byLevel: byLevel);
  }
}
