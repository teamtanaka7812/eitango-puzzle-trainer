import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:word_puzzle_trainer/models/puzzle_word.dart';
import 'package:word_puzzle_trainer/widgets/piece_geometry.dart';

/// ピース画像の名前（`pre_1`・`stem_g_3`など）から役割と形の番号を取り出す。
({String role, int variant}) _parse(String assetPath) {
  final name = assetPath.split('/').last.replaceAll('.png', '');
  final role = name.startsWith('pre_')
      ? 'pre'
      : name.startsWith('stem_')
          ? 'stem'
          : 'suf';
  return (role: role, variant: int.parse(name.split('_').last));
}

const _roleOrder = ['pre', 'stem', 'suf'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<PuzzleWord> words;

  setUpAll(() async {
    final byLevel = await WordRepository.loadByLevel();
    words = [for (final level in byLevel.values) ...level];
  });

  test('出題されるのは56問（Level 1: 19、Level 2: 26、Level 3: 11）で、2ピース44問・3ピース12問', () {
    expect(words.length, 56);
    expect(words.where((w) => w.level == 1).length, 19);
    expect(words.where((w) => w.level == 2).length, 26);
    expect(words.where((w) => w.level == 3).length, 11);
    expect(words.where((w) => w.parts.length == 2).length, 44);
    expect(words.where((w) => w.parts.length == 3).length, 12);
  });

  test('出題から外した問題（retired）は出題されず、そのピースは他の問題のおとりに使われない', () {
    final raw = jsonDecode(File('assets/data/words.json').readAsStringSync()) as List<dynamic>;
    final retired = [for (final w in raw) if ((w as Map)['retired'] == true) w];
    expect([for (final w in retired) w['word']], ['accurate', 'offense', 'defense']);

    final loadedIds = {for (final w in words) w.id};
    for (final w in retired) {
      expect(loadedIds, isNot(contains(w['id'])), reason: '${w['id']} が出題されている');
    }

    // 外した問題にしか無いピース（他の出題中の問題の正解ピースでないもの）は、
    // おとりに使わない。
    final activeParts = {for (final w in words) for (final p in w.parts) p.text};
    final retiredOnly = {
      for (final w in retired) for (final p in w['parts'] as List) p as String,
    }.difference(activeParts);
    expect(retiredOnly, containsAll(['fen', 'curate']));
    for (final w in words) {
      final partTexts = w.parts.map((p) => p.text).toSet();
      for (final c in w.presetChoices) {
        if (partTexts.contains(c.text)) continue;
        expect(retiredOnly, isNot(contains(c.text)),
            reason: '${w.id} のおとり ${c.text} は、外した問題のピース');
      }
    }
  });

  test('全問題の選択肢が、実在するピース画像と形状データを指している', () {
    expect(words.length, 56);
    for (final word in words) {
      for (final choice in word.presetChoices) {
        expect(pieceGeometryOf(choice.assetPath), isNotNull,
            reason: '${word.id}: ${choice.assetPath}');
        expect(File(choice.assetPath).existsSync(), isTrue,
            reason: '${word.id}: ${choice.assetPath}');
      }
    }
  });

  test('1問の全ピースは同じ形の番号で、文字の長さに合わせて横に伸ばせる形である', () {
    for (final word in words) {
      final variants = {for (final c in word.presetChoices) _parse(c.assetPath).variant};
      expect(variants.length, 1, reason: '${word.id} の形の番号がそろっていない: $variants');
      for (final c in word.presetChoices) {
        expect(pieceGeometryOf(c.assetPath)!.stretchable, isTrue,
            reason: '${word.id}: ${c.assetPath} は横に伸ばせない形');
      }
    }
  });

  test('選択肢は「正解 + おとり3〜4個」で、文字は重複しない', () {
    for (final word in words) {
      final texts = word.presetChoices.map((c) => c.text).toList();
      expect(texts.toSet().length, texts.length, reason: '${word.id} に同じ文字のピースがある');
      expect(texts.length - word.parts.length, inInclusiveRange(3, 4), reason: word.id);
      for (final part in word.parts) {
        expect(texts, contains(part.text), reason: '${word.id} の正解 ${part.text} が選択肢にない');
      }
    }
  });

  test('正解ピースは 前置→語幹→後置 の順の形で、各役割に同じ形のおとりが1個以上ある', () {
    for (final word in words) {
      final roleOf = {
        for (final c in word.presetChoices) c.text: _parse(c.assetPath).role,
      };
      final correctRoles = [for (final p in word.parts) roleOf[p.text]!];

      // 2ピースは 前置+語幹 か 語幹+後置、3ピースは 前置+語幹+後置。
      final indices = correctRoles.map(_roleOrder.indexOf).toList();
      for (var i = 1; i < indices.length; i++) {
        expect(indices[i], greaterThan(indices[i - 1]),
            reason: '${word.id}: 正解の形の並びが $correctRoles');
      }

      // 形から正解を絞り込めないよう、正解と同じ役割の形のおとりが必ずある。
      final partTexts = word.parts.map((p) => p.text).toSet();
      final decoyRoles = [
        for (final c in word.presetChoices)
          if (!partTexts.contains(c.text)) roleOf[c.text]!,
      ];
      for (final role in correctRoles) {
        expect(decoyRoles, contains(role), reason: '${word.id}: $role の形のおとりがない');
      }
    }
  });

  test('おとりの形は特定の役割に偏っていない（どの役割も、おとりの過半数を超えない）', () {
    for (final word in words) {
      final partTexts = word.parts.map((p) => p.text).toSet();
      final counts = <String, int>{};
      for (final c in word.presetChoices) {
        if (partTexts.contains(c.text)) continue;
        counts.update(_parse(c.assetPath).role, (n) => n + 1, ifAbsent: () => 1);
      }
      final decoys = counts.values.fold(0, (a, b) => a + b);
      for (final entry in counts.entries) {
        expect(entry.value * 2, lessThanOrEqualTo(decoys + 1),
            reason: '${word.id}: おとりの形が ${entry.key} に偏っている $counts');
      }
    }
  });
}
