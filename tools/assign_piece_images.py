# -*- coding: utf-8 -*-
"""words.json の各単語の choices[].image を、役割つきの新しいピース画像
(assets/puzzle_pieces_v3) に割り当て直す。

使い方 (リポジトリ直下から):
    python tools/assign_piece_images.py

結果は決定論的 (同じ入力なら同じ出力)。全参加者が同じ刺激を見ること、再実行
しても画像が変わらないことが目的なので、実行時に乱数で抽選せず、ここで
決めた結果を words.json に書き込んでおく。

割り当ての方針
--------------
- 画像名は 役割 + 形の番号: pre_K / stem_g_K / stem_y_K / suf_K  (K = 1 か 3)。
  K は単語ごとに 1 と 3 を交互に使う。2 と 4 は語幹の左右両方が凹んでいて、
  横に伸ばすと絵が崩れるため使わない (tools/piece_exporter 参照)。
  同じ単語の全ピースは同じ K なので、前置・語幹・後置が互いにかみ合う。
- 正解ピースの役割は注釈 (new_words_49.json の q_Prefixes / q_Stem / q_Suffix)
  から復元する。2 ピースの単語は 前置+語幹 (PS) か 語幹+後置 (SX)、
  3 ピースの単語は 前置+語幹+後置 (PSX)。
- おとりピース: 正解の各役割と同じ役割のおとりを必ず 1 個以上入れ、残りは
  その時点で最も少ない役割に割り当てる。これにより、ピースの形 (左端が平ら、
  左が凹んでいる、など) から正解を推測できなくなる。同じ条件を満たす割り当てが
  複数あるときは、そのおとり自身が本来使われる役割 (例: ly は後置) に近い
  ものを選ぶ。
- 語幹の色 (緑/黄) は、語幹の役割のピースごとに決定論的に選ぶ。
"""
import hashlib
import itertools
import json
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORDS = os.path.join(ROOT, 'assets', 'data', 'words.json')
SOURCE = os.path.join(ROOT, 'assets', 'data', 'new_words_49.json')

PRE, STEM, SUF = 'pre', 'stem', 'suf'
ROLES = (PRE, STEM, SUF)
VARIANTS = (1, 3)

# new_words_49.json の注釈が壊れている 1 語 (q_No 19) など、注釈から読めない単語。
# 旧 10 問も注釈を持たないため、構造 (PS / SX) をここで明示する。
STRUCTURE_OVERRIDES = {
    'illegal': 'PS',          # il + legal
    'development': 'SX',      # develop + ment
    'unfortunately': 'SX',    # unfortunate + ly
    'reappearance': 'SX',     # reappear + ance
    'independently': 'SX',    # independent + ly
    'reconsideration': 'SX',  # reconsider + ation
    'unbelievable': 'PS',     # un + believable
    'uncomfortable': 'PS',    # un + comfortable
    'disagreement': 'SX',     # disagree + ment
    'undependable': 'PS',     # un + dependable
    'minor': 'SX',            # min + or
}


def seeded(*keys):
    digest = hashlib.sha256('|'.join(keys).encode('utf-8')).hexdigest()
    return random.Random(int(digest[:16], 16))


def load_annotations():
    with open(SOURCE, encoding='utf-8') as f:
        return {q['q_answer']: q for q in json.load(f)}


def natural_roles(annotations, words):
    """テキスト -> 本来使われる役割の集合 (注釈と旧 10 問の構造から作る語彙表)。"""
    vocab = {}

    def add(text, role):
        if text:
            vocab.setdefault(text, set()).add(role)

    for q in annotations.values():
        add(q['q_Prefixes'], PRE)
        add(q['q_Stem'], STEM)
        add(q['q_Suffix'], SUF)
    for w in words:
        structure = structure_of(w, annotations)
        for text, role in zip(w['parts'], roles_of(structure)):
            add(text, role)
    return vocab


def roles_of(structure):
    return {'PS': (PRE, STEM), 'SX': (STEM, SUF), 'PSX': (PRE, STEM, SUF)}[structure]


def structure_of(word, annotations):
    parts = word['parts']
    if len(parts) == 3:
        return 'PSX'
    if word['word'] in STRUCTURE_OVERRIDES:
        return STRUCTURE_OVERRIDES[word['word']]
    q = annotations[word['word']]
    pre, suf = q['q_Prefixes'], q['q_Suffix']
    if pre and parts[0] == pre:
        return 'PS'
    if suf and parts[1] == suf:
        return 'SX'
    return 'PS' if pre else 'SX'


def decoy_role_targets(correct_roles, decoy_count):
    """おとりに割り当てる役割ごとの個数。"""
    counts = {r: 0 for r in ROLES}
    # 正解の各役割と同じ役割のおとりを 1 個ずつ
    remaining = decoy_count
    totals = {r: (1 if r in correct_roles else 0) for r in ROLES}
    for r in correct_roles:
        if remaining > 0:
            counts[r] += 1
            totals[r] += 1
            remaining -= 1
    # 残りは、おとりを含めた合計が最も少ない役割へ
    while remaining > 0:
        r = min(ROLES, key=lambda x: (totals[x], ROLES.index(x)))
        counts[r] += 1
        totals[r] += 1
        remaining -= 1
    return counts


def assign_decoys(decoys, targets, vocab, rng):
    """目標の個数を満たしつつ、おとり本来の役割に近い割り当てを選ぶ。"""
    sequence = []
    for r in ROLES:
        sequence += [r] * targets[r]
    best, best_score = None, None
    # set の並びは実行ごとに変わりうるので、一度ソートしてから seed 付きでシャッフルする
    candidates = sorted(set(itertools.permutations(sequence)))
    rng.shuffle(candidates)
    for perm in candidates:
        score = sum(1 for text, role in zip(decoys, perm) if role in vocab.get(text, ()))
        if best_score is None or score > best_score:
            best, best_score = perm, score
    return best


def image_name(role, variant, stem_color):
    if role == STEM:
        return f'stem_{stem_color}_{variant}.png'
    return f'{role}_{variant}.png'


def main():
    annotations = load_annotations()
    with open(WORDS, encoding='utf-8') as f:
        words = json.load(f)
    vocab = natural_roles(annotations, words)

    summary = []
    for index, word in enumerate(words):
        variant = VARIANTS[index % len(VARIANTS)]
        structure = structure_of(word, annotations)
        correct_roles = roles_of(structure)
        correct = dict(zip(word['parts'], correct_roles))
        texts = [c['text'] for c in word['choices']]
        assert set(word['parts']) <= set(texts), word['word']
        decoys = [t for t in texts if t not in correct]

        rng = seeded(word['id'], 'roles')
        targets = decoy_role_targets(correct_roles, len(decoys))
        decoy_roles = dict(zip(decoys, assign_decoys(decoys, targets, vocab, rng)))

        role_of = {**correct, **decoy_roles}
        for choice in word['choices']:
            role = role_of[choice['text']]
            color = seeded(word['id'], choice['text'], 'color').choice(['g', 'y'])
            choice['image'] = image_name(role, variant, color)
        summary.append((word['word'], structure, variant,
                        {t: role_of[t] for t in texts}))

    with open(WORDS, 'w', encoding='utf-8', newline='\n') as f:
        f.write(json.dumps(words, ensure_ascii=False, indent=2))
        f.write('\n')

    for name, structure, variant, roles in summary:
        shown = ' '.join(f'{t}:{r}' for t, r in roles.items())
        print(f'{name:16s} {structure:3s} K={variant}  {shown}')


if __name__ == '__main__':
    main()
