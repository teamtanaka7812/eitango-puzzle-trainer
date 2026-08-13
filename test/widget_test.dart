import 'package:flutter_test/flutter_test.dart';

import 'package:word_puzzle_trainer/main.dart';

void main() {
  testWidgets('Home screen shows title and menu buttons', (WidgetTester tester) async {
    await tester.pumpWidget(const WordPuzzleTrainerApp());

    expect(find.text('英単語パズルトレーナー'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);
    expect(find.text('HISTORY'), findsOneWidget);
    expect(find.text('WORD BOOK'), findsOneWidget);
    expect(find.text('ENCYCLOPEDIA'), findsOneWidget);
  });

  testWidgets('Tapping START navigates to level select screen', (WidgetTester tester) async {
    await tester.pumpWidget(const WordPuzzleTrainerApp());

    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();

    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('Level 3'), findsOneWidget);
  });
}
