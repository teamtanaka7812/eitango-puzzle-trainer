# -*- coding: utf-8 -*-
"""Firestore の解答記録 (participants/{参加者ID}/attempts/{記録ID}) を、Excel で集計できる
CSV に書き出す、開発者用の読み取り専用ツール。公開版アプリ (Flutter) には含まれない。

**読み取り専用**: Firestore への書き込み・更新・削除は一切しない (読み取り API だけを使う)。

使い方 (リポジトリ直下から):
    python tools/export_attempts.py
    python tools/export_attempts.py --data-version 2026-10b
    python tools/export_attempts.py --participant Test-00001
    python tools/export_attempts.py --since 2026-10-01
    python tools/export_attempts.py --key secrets/別のキー.json --out-dir exports

必要なもの:
    pip install firebase-admin
    サービスアカウントキー (JSON) を secrets/ に置く。secrets/ と exports/ は
    .gitignore 済みで、コミットされない。キーの中身は、画面にも報告にも出さないこと。

出力: exports/attempts_YYYYMMDD_HHMMSS.csv (日本時間の実行時刻)
- 文字コードは UTF-8 (BOM 付き)。Excel でダブルクリックで開いても、日本語が文字化けしない。
- 1 行 = 1 回の解答。並びは participantId、answeredAt の昇順。
- 列: participantId, word, level, isCorrect, answeredAt, startedAt, durationSeconds,
  dragCount, dataVersion, ownerUid
- 日時は日本時間 (JST) の YYYY-MM-DD HH:MM:SS。isCorrect は TRUE / FALSE。
- 記録に無い項目 (古い記録の startedAt など) は空欄にして、止まらずに続ける。

絞り込み (どれも任意。組み合わせられる):
- --data-version 2026-10b : その版の記録だけ。`none` を指定すると、dataVersion が無い旧版だけ。
- --participant ID        : その参加者だけ。
- --since 2026-10-01      : 日本時間のその日の 0 時以降に解答した記録だけ
                            (answeredAt が無い記録は、この指定のときは除く)。

メモ:
- 記録は collection group クエリ (全 attempts) をドキュメント名の順にページ分割して読む
  (1 回 PAGE_SIZE 件ずつ。件数が多くても、1 回の通信が大きくなりすぎない)。
  絞り込みと並べ替えは手元 (Python) で行うので、Firestore のインデックスは要らない。
- 参加者 ID は、記録の親ドキュメントの ID (participants/{ID}) から取る。
  participants のドキュメント自体は項目を持たない (サブコレクションだけがある)。
- 参加者 ID は自由入力なので、`=` などで始まる ID があると Excel が数式として
  解釈することがある (この場合は CSV を開く前に ID を確認すること)。
"""
import argparse
import csv
import glob
import os
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_KEY_GLOB = os.path.join(ROOT, 'secrets', '*.json')
DEFAULT_OUT_DIR = os.path.join(ROOT, 'exports')
PAGE_SIZE = 500
JST = timezone(timedelta(hours=9))

COLUMNS = ['participantId', 'word', 'level', 'isCorrect', 'answeredAt', 'startedAt',
           'durationSeconds', 'dragCount', 'dataVersion', 'ownerUid']


def fail(message):
    print(f'エラー: {message}', file=sys.stderr)
    sys.exit(1)


def resolve_key(path):
    """キーのパス。指定が無ければ secrets/ 内の JSON (1個だけのとき)。"""
    if path:
        if not os.path.isfile(path):
            fail(f'キーのファイルが見つかりません: {path}')
        return path
    found = sorted(glob.glob(DEFAULT_KEY_GLOB))
    if not found:
        fail('secrets/ にサービスアカウントキー (JSON) がありません。--key で指定してください。')
    if len(found) > 1:
        names = ', '.join(os.path.basename(f) for f in found)
        fail(f'secrets/ に JSON が複数あります ({names})。--key で指定してください。')
    return found[0]


def fmt_time(value):
    """Firestore の Timestamp (datetime) を JST の文字列に。無ければ空欄。"""
    if value is None:
        return ''
    if not isinstance(value, datetime):
        return ''
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(JST).strftime('%Y-%m-%d %H:%M:%S')


def fmt_bool(value):
    if isinstance(value, bool):
        return 'TRUE' if value else 'FALSE'
    return ''


def fmt_number(value, decimals=None):
    if value is None or isinstance(value, bool):
        return ''
    if isinstance(value, (int, float)):
        if decimals is not None and isinstance(value, float):
            return f'{value:.{decimals}f}'
        return str(value)
    return ''


def fmt_text(value):
    return '' if value is None else str(value)


def read_attempts(db, participant):
    """(参加者ID, 記録の dict) を順に返す。読み取りだけ。"""
    if participant:
        query = db.collection('participants').document(participant).collection('attempts')
    else:
        query = db.collection_group('attempts')
    query = query.order_by('__name__')  # ドキュメント名の順 (ページ分割の目印)

    last = None
    while True:
        page_query = query.limit(PAGE_SIZE)
        if last is not None:
            page_query = page_query.start_after(last)
        docs = list(page_query.stream())
        for doc in docs:
            # participants/{ID}/attempts/{記録ID} -> 親の親 = 参加者 ID
            parent = doc.reference.parent.parent
            yield (parent.id if parent is not None else ''), doc.to_dict() or {}
        if len(docs) < PAGE_SIZE:
            return
        last = docs[-1]


def to_row(participant_id, data):
    return {
        'participantId': participant_id,
        'word': fmt_text(data.get('word')),
        'level': fmt_number(data.get('level')),
        'isCorrect': fmt_bool(data.get('isCorrect')),
        'answeredAt': fmt_time(data.get('answeredAt')),
        'startedAt': fmt_time(data.get('startedAt')),
        'durationSeconds': fmt_number(data.get('durationSeconds'), decimals=3),
        'dragCount': fmt_number(data.get('dragCount')),
        'dataVersion': fmt_text(data.get('dataVersion')),
        'ownerUid': fmt_text(data.get('ownerUid')),
    }


def main():
    parser = argparse.ArgumentParser(description='Firestore の解答記録を CSV に書き出す (読み取り専用)')
    parser.add_argument('--key', help='サービスアカウントキー (JSON) のパス。既定は secrets/ 内の1個')
    parser.add_argument('--data-version', help='この dataVersion の記録だけ。none = 旧版 (dataVersion なし)')
    parser.add_argument('--participant', help='この参加者 ID の記録だけ')
    parser.add_argument('--since', help='YYYY-MM-DD。日本時間のその日の 0 時以降に解答した記録だけ')
    parser.add_argument('--out-dir', default=DEFAULT_OUT_DIR, help='出力先フォルダ (既定: exports)')
    args = parser.parse_args()

    since = None
    if args.since:
        try:
            since = datetime.strptime(args.since, '%Y-%m-%d').replace(tzinfo=JST)
        except ValueError:
            fail('--since は YYYY-MM-DD の形式で指定してください (例: 2026-10-01)')

    key_path = resolve_key(args.key)

    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError:
        fail('firebase-admin が必要です: pip install firebase-admin')

    try:
        firebase_admin.initialize_app(credentials.Certificate(key_path))
    except Exception as e:  # キーの中身を出さないよう、種類だけ知らせる
        fail(f'キーを読み込めませんでした ({type(e).__name__})。キーのファイルを確認してください。')
    db = firestore.client()

    print(f'キー: {os.path.basename(key_path)}  読み取り専用で実行します')
    rows = []
    excluded_no_time = 0
    for participant_id, data in read_attempts(db, args.participant):
        version = data.get('dataVersion')
        if args.data_version is not None:
            wanted = None if args.data_version.lower() == 'none' else args.data_version
            if (version or None) != wanted:
                continue
        answered = data.get('answeredAt')
        if since is not None:
            if not isinstance(answered, datetime):
                excluded_no_time += 1
                continue
            if answered.astimezone(JST) < since:
                continue
        # 並べ替え用のキー (answeredAt が無い記録は、その参加者の最後に置く)
        sort_time = answered.astimezone(timezone.utc) if isinstance(answered, datetime) else None
        rows.append((participant_id, sort_time, to_row(participant_id, data)))

    far_future = datetime.max.replace(tzinfo=timezone.utc)
    rows.sort(key=lambda r: (r[0], r[1] is None, r[1] or far_future))

    os.makedirs(args.out_dir, exist_ok=True)
    stamp = datetime.now(JST).strftime('%Y%m%d_%H%M%S')
    out_path = os.path.join(args.out_dir, f'attempts_{stamp}.csv')
    with open(out_path, 'w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        for _, _, row in rows:
            writer.writerow(row)

    # ---- 実行結果 ----
    participants = {r[0] for r in rows}
    versions = Counter(r[2]['dataVersion'] or '' for r in rows)
    print(f'書き出し: {out_path}')
    print(f'総行数: {len(rows)}  参加者数: {len(participants)}')
    print('dataVersion ごとの件数:')
    for v in sorted(versions, key=lambda x: (x == '', x)):
        label = v if v else '(なし: 旧版の記録。空欄で出力)'
        print(f'  {label}: {versions[v]}')
    missing = {c: sum(1 for r in rows if r[2][c] == '') for c in COLUMNS}
    missing = {c: n for c, n in missing.items() if n}
    if missing:
        print('空欄になった項目 (記録に無かった件数): ' + ', '.join(f'{c}={n}' for c, n in missing.items()))
    if excluded_no_time:
        print(f'--since の指定で、answeredAt が無い記録 {excluded_no_time} 件を除きました')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
