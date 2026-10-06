# -*- coding: utf-8 -*-
"""おとりを含む選択肢から、正解以外の「実在する英単語」が作れないかを調べる。

背景: ピースの文字を並べ替えて、正解とは別の実在語(例: observe の問題で
minister が作れる)が完成してしまうと、「答えが2つある問題」になる。これを
防ぐため、全問題について、選択肢から作れる組み合わせの文字列を辞書で判定する。

使い方 (リポジトリ直下から):
    python tools/decoy_check.py              # words.json を検査し、衝突を一覧表示
    python tools/decoy_check.py --write-test-data
                                              # test/data/decoy_check_data.json を作り直す
                                              # (Dart のテストはこのファイルだけを使う)

必要な Python パッケージ (検査用データを作るときだけ必要。テスト自体には不要):
    pip install english-words wordfreq

「実在語」とみなす基準 (固定):
- 辞書 = english_words の web2 と gcide。頻度 = wordfreq の zipf 値。
- 区分A/B: 辞書にある語で zipf >= 1.5。 区分D: 辞書に無いが zipf >= 3.0 (活用形など)。
- 区分C (辞書にはあるが zipf < 1.5 の、非語に近い語) は対象外。
- 2文字以下の語は、辞書の雑多な短い語を拾いすぎないよう zipf >= 3.0 のものだけ。
- admin / ara / arse / addis / distal は、頻度に関わらず必ず避ける (MANUAL_FORBIDDEN)。

検査する組み合わせ:
- 解答欄が k 枠なら、選択肢から k 枚を選んだ全ての順列 (正解の並びは除く)。
- 3ピースの問題は、一部の枠だけ埋めた状態として、2枚の全順列も含める。
- 正解と同じ綴りになる別の分割も、判定上は不正解になるため禁止する。
"""
import itertools
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORDS = os.path.join(ROOT, 'assets', 'data', 'words.json')
TEST_DATA = os.path.join(ROOT, 'test', 'data', 'decoy_check_data.json')

# 利用者の指示で、頻度に関わらず必ず避ける語 (小学生向けのため俗語など)。
MANUAL_FORBIDDEN = {'admin', 'ara', 'arse', 'addis', 'distal'}

AB_MIN = 1.5      # 辞書にある語: この頻度(zipf)以上を禁止 (区分A/B)
D_MIN = 3.0       # 辞書に無い語: この頻度以上を禁止 (区分D)
SHORT_MIN = 3.0   # 2文字以下の語: この頻度以上だけを禁止

_dictionary = None
_freq = None
_cache = {}


def _load_resources():
    global _dictionary, _freq
    if _dictionary is not None:
        return
    try:
        from english_words import get_english_words_set
        from wordfreq import get_frequency_dict
    except ImportError:
        sys.exit('english-words と wordfreq が必要です: pip install english-words wordfreq')
    _dictionary = (get_english_words_set(['web2'], lower=True)
                   | get_english_words_set(['gcide'], lower=True))
    _freq = get_frequency_dict('en')


def zipf(word):
    from wordfreq import zipf_frequency
    return zipf_frequency(word, 'en') if _freq.get(word) else 0.0


def forbidden(s):
    """s が「正解以外に完成してはいけない実在語」ならTrue。"""
    if s in _cache:
        return _cache[s]
    _load_resources()
    result = False
    if s in MANUAL_FORBIDDEN:
        result = True
    elif s.isalpha():
        z = zipf(s)
        if len(s) <= 2:
            result = s in _dictionary and z >= SHORT_MIN
        elif s in _dictionary:
            result = z >= AB_MIN
        else:
            result = z >= D_MIN
    _cache[s] = result
    return result


def combos(texts, parts):
    """検査する組み合わせ (文字のタプル)。正解の並びそのものは含めない。"""
    k = len(parts)
    result = [p for p in itertools.permutations(texts, k) if list(p) != list(parts)]
    if k == 3:
        result.extend(itertools.permutations(texts, 2))
    return result


def collisions(texts, parts, answer):
    """(組み合わせ, 連結した綴り) のうち、禁止語になるもの。"""
    bad = []
    for perm in combos(texts, parts):
        s = ''.join(perm)
        if s == answer or forbidden(s):
            bad.append((perm, s))
    return bad


def load_words():
    with open(WORDS, encoding='utf-8') as f:
        return json.load(f)


def report():
    words = load_words()
    total = 0
    for i, w in enumerate(words, 1):
        texts = [c['text'] for c in w['choices']]
        bad = collisions(texts, w['parts'], w['word'].lower())
        for perm, s in bad:
            total += 1
            print(f"問題{i:02d} {w['word']}: {'+'.join(perm)} = {s}")
    print(f'衝突: {total} 件')
    return total


def write_test_data():
    """Dart のテスト用に、各問題から作れる全ての綴りと、その判定を書き出す。

    checked = 検査した全ての綴り、forbidden = そのうち禁止語。テストは辞書を使わず、
    words.json から組み合わせを作り直して、このデータと突き合わせる。
    """
    words = load_words()
    checked, banned = set(), set()
    for w in words:
        texts = [c['text'] for c in w['choices']]
        for perm in combos(texts, w['parts']):
            s = ''.join(perm)
            checked.add(s)
            if forbidden(s):
                banned.add(s)
    data = {
        'about': ('tools/decoy_check.py が作った検査用データ。words.json を変えたら'
                  ' python tools/decoy_check.py --write-test-data で作り直す。'),
        'forbidden': sorted(banned),
        'checked': sorted(checked),
    }
    os.makedirs(os.path.dirname(TEST_DATA), exist_ok=True)
    with open(TEST_DATA, 'w', encoding='utf-8', newline='\n') as f:
        f.write(json.dumps(data, ensure_ascii=False, indent=1))
        f.write('\n')
    print(f'書き出し: {TEST_DATA} (検査した綴り {len(checked)} 件 / うち禁止語 {len(banned)} 件)')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    if '--write-test-data' in sys.argv:
        write_test_data()
    else:
        sys.exit(1 if report() else 0)
