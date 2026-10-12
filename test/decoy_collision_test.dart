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
/// - 解答欄に空きがあるときは「Answer!」が判定されない（2026年10月〜）ので、3 ピースの
///   問題の「一部の枠だけ埋めた状態」は検査しない。
/// - 正解と同じ綴りになる別の分割も、判定上は不正解になるため禁止。
///
/// 辞書を使わない、次の2つの検査も直接行う（検査用データを経由しない）:
/// - `tools/forbidden_words.json`（リーダーが個別に「作れてはいけない」と判断した語）。
/// - 出題中の全ての正解語と、全ての語幹（画像名が `stem_` のピース）のうち、
///   「別の問題の選択肢から作れてはいけない」もの。語幹は、辞書にある語だけを
///   守る（capa・judice のような断片は対象外。`tools/decoy_check.py` の
///   `protected_words()` と同じ基準）。辞書が必要なこの絞り込みはテストでは行えないので、
///   語幹は「正解語そのもの」と、`decoy_check_data.json` の `protectedStems` に
///   書き出した語に限る。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<PuzzleWord> words;
  late Set<String> forbidden;
  late Set<String> checked;
  late Set<String> protectedStems;
  late Set<String> leaderForbidden;

  setUpAll(() async {
    final byLevel = await WordRepository.loadByLevel();
    words = [for (final level in byLevel.values) ...level];
    final data = jsonDecode(File('test/data/decoy_check_data.json').readAsStringSync())
        as Map<String, dynamic>;
    forbidden = {for (final s in data['forbidden'] as List) s as String};
    checked = {for (final s in data['checked'] as List) s as String};
    protectedStems = {for (final s in data['protectedStems'] as List) s as String};
    final leader = jsonDecode(File('tools/forbidden_words.json').readAsStringSync())
        as Map<String, dynamic>;
    leaderForbidden = {
      for (final w in leader['words'] as List) ((w as Map)['word'] as String).toLowerCase(),
    };
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

  test('リーダーが禁止した語（tools/forbidden_words.json）は、どの問題でも作れない', () {
    expect(leaderForbidden, containsAll(['arity', 'inventful']));
    final problems = <String>[];
    for (final word in words) {
      for (final perm in combosOf(word)) {
        final spelling = perm.join();
        if (leaderForbidden.contains(spelling)) {
          problems.add('${word.id}: ${perm.join('+')} = $spelling');
        }
      }
    }
    expect(problems, isEmpty,
        reason: '禁止語が作れてしまう。おとりを選び直すこと(python tools/reselect_decoys.py)。');
  });

  test('出題中の全ての正解語と、辞書にある語幹は、別の問題の選択肢から作れない', () {
    final protected = {
      for (final w in words) w.word.toLowerCase(),
      ...protectedStems,
    };
    final problems = <String>[];
    for (final word in words) {
      for (final perm in combosOf(word)) {
        final spelling = perm.join();
        if (protected.contains(spelling)) {
          problems.add('${word.id}: ${perm.join('+')} = $spelling');
        }
      }
    }
    expect(problems, isEmpty,
        reason: '別の問題の正解語・語幹が作れてしまう。おとりを選び直すこと。');
  });
}
