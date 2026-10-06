import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:word_puzzle_trainer/models/puzzle_word.dart';

/// 「答えが2つある問題」を防ぐ回帰テスト。
///
/// 各問題の選択肢(正解 + おとり)から作れる組み合わせの綴りが、正解以外の実在語に
/// ならないことを確認する。実在語かどうかの判定は、辞書が必要なため Python 側
/// (`tools/decoy_check.py`)で行い、その結果を `test/data/decoy_check_data.json` に
/// 書き出してある。このテストはそのデータと突き合わせるだけなので、Python も辞書も
/// 必要ない。アプリ本体にはこのデータを同梱していない。
///
/// 検査する組み合わせは tools/decoy_check.py と同じ:
/// - 解答欄が k 枠なら、選択肢から k 枚を選んだ全ての順列(正解の並びは除く)。
/// - 3 ピースの問題は、一部の枠だけ埋めた状態として、2 枚の全順列も含む。
/// - 正解と同じ綴りになる別の分割も、判定上は不正解になるため禁止。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<PuzzleWord> words;
  late Set<String> forbidden;
  late Set<String> checked;

  setUpAll(() async {
    final byLevel = await WordRepository.loadByLevel();
    words = [for (final level in byLevel.values) ...level];
    final data = jsonDecode(File('test/data/decoy_check_data.json').readAsStringSync())
        as Map<String, dynamic>;
    forbidden = {for (final s in data['forbidden'] as List) s as String};
    checked = {for (final s in data['checked'] as List) s as String};
  });

  /// [items] から [k] 個を選んだ全ての順列。
  Iterable<List<String>> permutations(List<String> items, int k) sync* {
    if (k == 0) {
      yield const [];
      return;
    }
    for (var i = 0; i < items.length; i++) {
      final rest = [...items.sublist(0, i), ...items.sublist(i + 1)];
      for (final tail in permutations(rest, k - 1)) {
        yield [items[i], ...tail];
      }
    }
  }

  /// 問題 [word] で検査する組み合わせ。
  Iterable<List<String>> combosOf(PuzzleWord word) sync* {
    final texts = [for (final c in word.presetChoices) c.text];
    final parts = [for (final p in word.parts) p.text];
    for (final perm in permutations(texts, parts.length)) {
      if (perm.join('|') != parts.join('|')) yield perm;
    }
    if (parts.length == 3) yield* permutations(texts, 2);
  }

  test('おとりを含む選択肢から、正解以外の実在語(区分A/B/D)は作れない', () {
    final problems = <String>[];
    for (final word in words) {
      for (final perm in combosOf(word)) {
        final spelling = perm.join();
        if (spelling == word.word.toLowerCase() || forbidden.contains(spelling)) {
          problems.add('${word.id}: ${perm.join('+')} = $spelling');
        }
      }
    }
    expect(problems, isEmpty,
        reason: '正解以外の実在語ができてしまう組み合わせがある。おとりを選び直すこと'
            '(python tools/reselect_decoys.py)。');
  });

  test('検査用データが最新である(words.jsonの全ての組み合わせが検査済み)', () {
    final unchecked = <String>{};
    for (final word in words) {
      for (final perm in combosOf(word)) {
        if (!checked.contains(perm.join())) unchecked.add('${word.id}: ${perm.join('+')}');
      }
    }
    expect(unchecked, isEmpty,
        reason: 'words.json を変えたのに検査用データが古い。'
            'python tools/decoy_check.py --write-test-data で作り直し、'
            '衝突が出たらおとりを選び直すこと。');
  });
}
