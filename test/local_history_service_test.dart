import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:word_puzzle_trainer/services/local_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('記録がなければ、全項目が0・正答率はnullになる', () async {
    final stats = await LocalHistoryService.loadStats();

    expect(stats.totalAnswered, 0);
    expect(stats.totalCorrect, 0);
    expect(stats.totalAccuracy, isNull);
    for (final level in [1, 2, 3]) {
      expect(stats.byLevel[level]!.answered, 0);
      expect(stats.byLevel[level]!.accuracy, isNull);
    }
  });

  test('recordAttemptで、レベル別・合計の解答数と正解数が正しく積み上がる', () async {
    await LocalHistoryService.recordAttempt(level: 1, isCorrect: true);
    await LocalHistoryService.recordAttempt(level: 1, isCorrect: false);
    await LocalHistoryService.recordAttempt(level: 2, isCorrect: true);

    final stats = await LocalHistoryService.loadStats();

    expect(stats.totalAnswered, 3);
    expect(stats.totalCorrect, 2);
    expect(stats.totalAccuracy, closeTo(2 / 3, 0.0001));

    expect(stats.byLevel[1]!.answered, 2);
    expect(stats.byLevel[1]!.correct, 1);
    expect(stats.byLevel[1]!.accuracy, 0.5);

    expect(stats.byLevel[2]!.answered, 1);
    expect(stats.byLevel[2]!.correct, 1);
    expect(stats.byLevel[2]!.accuracy, 1.0);

    expect(stats.byLevel[3]!.answered, 0);
    expect(stats.byLevel[3]!.accuracy, isNull);
  });
}
