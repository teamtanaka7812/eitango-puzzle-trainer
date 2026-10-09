# -*- coding: utf-8 -*-
"""全問題のおとりを、次の条件を満たすように選び直す。

使い方 (リポジトリ直下から):
    python tools/reselect_decoys.py --dry-run   # 提案を表示するだけ (words.json は変えない)
    python tools/reselect_decoys.py             # words.json を更新し、ピース画像も割り当て直す

条件
----
1. 選択肢から作れる組み合わせ (tools/decoy_check.py の基準) が、正解以外の実在語に
   ならない。3ピースの問題は、2枚だけ置いた状態も含む。
2. おとりの文字が本来使われる役割 (接頭辞・語幹・接尾辞) が、割り当てる形の役割と
   一致する。形の役割の個数は tools/assign_piece_images.py の decoy_role_targets と同じ
   (正解の各役割に同じ形のおとりを1個以上 + 残りは最も少ない役割へ)。
3. 正解ピースと、各問題のおとりの個数 (3〜4個) は変えない。
   出題から外した問題 (words.json の "retired": true) は触らず、その問題にしか無い
   ピース (他の出題中の問題の正解ピースでないもの。例: fen・curate) は、おとりに
   使わない。文字の役割の知識は、外した問題の注釈からの分も残す (se は接尾辞でもある)。
4. 結果は決定論的 (乱数ではなく、問題ID+文字のハッシュで同点を決める)。

方針: 今のおとりを残せるだけ残し (変更が最小)、足りない分は、手持ちの文字
(注釈・手作業補完) から、それでも無理なら予備の候補 (EXTRA_ROLES) から選ぶ。
条件を満たす組み合わせが無い問題は、変更せずに報告する (無理に決めない)。
"""
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import assign_piece_images as assign  # noqa: E402
import decoy_check  # noqa: E402


def tiebreak(word_id, text):
    return int(hashlib.sha256(f'{word_id}|{text}|decoy'.encode('utf-8')).hexdigest()[:8], 16)


def solve(word, vocab, tier1, annotations):
    """1問ぶんの、新しいおとり (文字のリスト)。見つからなければ None。"""
    word_id = word['id']
    parts = word['parts']
    answer = word['word'].lower()
    correct_roles = assign.roles_of(assign.structure_of(word, annotations))
    current = [c['text'] for c in word['choices'] if c['text'] not in parts]
    targets = assign.decoy_role_targets(correct_roles, len(current))

    def cost(text):
        if text in current:
            return 0
        return 1 if text in tier1 else 2

    def pair_ok(x, y):
        if [x, y] == parts:
            return True
        s = x + y
        return not (s == answer or decoy_check.forbidden(s))

    # 候補: 役割ごと。正解ピースとの組み合わせ (どちらの順も) が安全なものだけ。
    candidates = {}
    for role in assign.ROLES:
        texts = [t for t, roles in vocab.items()
                 if role in roles and t not in parts
                 and all(pair_ok(t, p) and pair_ok(p, t) for p in parts)]
        candidates[role] = sorted(texts, key=lambda t: (cost(t), tiebreak(word_id, t)))

    slots = [role for role in assign.ROLES for _ in range(targets[role])]
    best = {'key': None, 'chosen': None}

    def leaf_ok(chosen):
        everything = parts + chosen
        for perm in decoy_check.combos(everything, parts):
            s = ''.join(perm)
            if s == answer or decoy_check.forbidden(s):
                return False
        return True

    def search(i, chosen, total_cost, total_tie):
        if best['key'] is not None and total_cost > best['key'][0]:
            return
        if i == len(slots):
            key = (total_cost, total_tie)
            if (best['key'] is None or key < best['key']) and leaf_ok(chosen):
                best['key'], best['chosen'] = key, list(chosen)
            return
        role = slots[i]
        # 同じ役割の中では並びを固定して、同じ組み合わせを重ねて探さない。
        after = chosen[-1] if i > 0 and slots[i - 1] == role else None
        passed = after is None
        for text in candidates[role]:
            if not passed:
                passed = text == after
                continue
            if text in chosen:
                continue
            if all(pair_ok(text, c) and pair_ok(c, text) for c in chosen):
                chosen.append(text)
                search(i + 1, chosen, total_cost + cost(text),
                       total_tie + tiebreak(word_id, text) % 1000)
                chosen.pop()

    search(0, [], 0, 0)
    return best['chosen']


def main():
    dry_run = '--dry-run' in sys.argv
    sys.stdout.reconfigure(encoding='utf-8')
    annotations = assign.load_annotations()
    with open(assign.WORDS, encoding='utf-8') as f:
        words = json.load(f)
    vocab = assign.natural_roles(annotations, words)
    tier1 = set(assign.natural_roles(annotations, words, include_extra=False))
    # 外した問題にしか無いピースは、おとりの候補にしない (役割の知識は残す)。
    active_parts = {t for w in words if not w.get('retired') for t in w['parts']}
    retired_only = {t for w in words if w.get('retired') for t in w['parts']} - active_parts
    vocab = {t: roles for t, roles in vocab.items() if t not in retired_only}
    tier1 -= retired_only

    failed = []
    changes = []
    for number, word in enumerate(words, 1):
        if word.get('retired'):
            continue
        parts = word['parts']
        current = [c['text'] for c in word['choices'] if c['text'] not in parts]
        chosen = solve(word, vocab, tier1, annotations)
        if chosen is None:
            failed.append((number, word['word']))
            continue
        removed = [t for t in current if t not in chosen]
        added = [t for t in chosen if t not in current]
        if removed or added:
            changes.append((number, word['word'], removed, added))
        # 残すおとりは元の位置のまま、外すおとりの位置に新しいおとりを入れる。
        queue = list(added)
        new_choices = []
        for choice in word['choices']:
            if choice['text'] in parts or choice['text'] in chosen:
                new_choices.append(choice)
            else:
                new_choices.append({'text': queue.pop(0), 'image': choice['image']})
        word['choices'] = new_choices

    for number, name, removed, added in changes:
        print(f'問題{number:02d} {name}: {"/".join(removed)} -> {"/".join(added)}')
    for number, name in failed:
        print(f'問題{number:02d} {name}: 条件を満たすおとりが見つからない (変更なし)')
    print(f'変更 {len(changes)} 問 / 見つからない {len(failed)} 問')

    if dry_run:
        return
    with open(assign.WORDS, 'w', encoding='utf-8', newline='\n') as f:
        f.write(json.dumps(words, ensure_ascii=False, indent=2))
        f.write('\n')
    # ピース画像 (形の役割) を、新しいおとりに合わせて決定論的に割り当て直す。
    assign.main()


if __name__ == '__main__':
    main()
