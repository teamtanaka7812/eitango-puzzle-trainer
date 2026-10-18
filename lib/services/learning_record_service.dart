import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data_version.dart';
import '../models/puzzle_word.dart';
import 'auth_service.dart';
import 'firebase_backends.dart';
import 'participant_service.dart';

/// 解答1回ぶんの記録の、保存の状態。
enum _SaveState {
  /// 送っている最中（まだ10秒たっていない）。
  sending,

  /// 送ったが、10秒たっても完了が確認できない（通信が切れている、など）。
  /// Firestoreが内部で保持していて、復帰すれば送られる。アプリは再送しない。
  unconfirmed,

  /// サーバーに拒否された（権限・上限など）。保存されていない。
  failed,

  /// ログインできなくて、送れていない。
  unsent,

  /// サーバーが受け付けた。
  saved,
}

class _Attempt {
  _Attempt({required this.id, required this.participantId, required this.data});

  /// 記録のID。解答の時点でアプリ側が決める。再送しても同じIDなので、重複しない。
  final String id;
  final String participantId;
  final AttemptData data;
  _SaveState state = _SaveState.sending;

  /// 送った回数（失敗の再送に上限を設けるため）。
  int tries = 0;
  Timer? timer;
}

/// 学習データ収集（アンケート・研究用）のためのFirestoreへの書き込み。
///
/// **ゲーム本体は止めない**：通信状況に関わらず正誤判定・画面遷移を止めない・遅らせない
/// ため、呼び出し側（[GameScreen]）はこのメソッドの完了を待たず、このメソッドも
/// 例外を外に出さない。ただし以前のように黙って諦めるのではなく、保存できなかった
/// ときは状態を[unsavedCount]と[noticeRequests]で知らせ、画面が小さな案内を出す
/// （2026年10月）。
///
/// 保存の流れ（1回の解答につき1件、IDはアプリ側で先に決める）：
/// 1. ログインしていなければ、保存の前にもう一度ログインを試みる（解答1回につき1回まで）。
///    それでもできなければ「未送信」として溜め、案内を出す。
/// 2. 書き込む。10秒たっても完了が確認できなければ「未確認」として案内を出す
///    （通信が切れていても書き込みはFirestoreが内部に保持し、復帰後に送る。アプリは
///    再送しない。ページを閉じる・再読み込みすると失われる）。
/// 3. サーバーに拒否された記録と未送信の記録は、ログインできたとき・次の解答のときに、
///    同じIDで送り直す（ページを開いている間だけ。再読み込みすると失われる）。
class LearningRecordService {
  /// 書き込みの完了を待つ時間。過ぎたら「未確認」として案内を出す。
  static const confirmTimeout = Duration(seconds: 10);

  /// 失敗した記録を送り直す回数の上限（上限に達したら、そのまま「記録できなかった」に数える）。
  static const maxTries = 5;

  /// Firestoreとのやりとり。テストでは模擬に差し替える。
  static RecordBackend backend =
      kIsWeb ? FirestoreRecordBackend() : DisabledRecordBackend();

  /// 保存できていない（未確認・失敗・未送信の）解答の数。結果画面が表示する。
  static final ValueNotifier<int> unsavedCount = ValueNotifier(0);

  /// 「記録できなかったかもしれません」の案内を出す合図。値が増えるたびに1回出す。
  static final ValueNotifier<int> noticeRequests = ValueNotifier(0);

  static final List<_Attempt> _open = [];
  static bool _noticeShown = false;
  static bool _flushing = false;
  static bool _listening = false;

  /// 1回答えるたびに呼ぶ。`participants/{参加者ID}/attempts/{記録ID}`に1件追加する。
  ///
  /// [startedAt]・[durationSeconds]・[dragCount]は、試用者の取り組み方を
  /// 詳しく分析するための研究データ用の項目（2026年9月追加）。HISTORY画面
  /// では使わず、Firestoreに送る記録にのみ含める（端末内
  /// [LocalHistoryService]の保存方式は変更しない、という決定）。
  /// - [startedAt] : その問題の画面（[GameScreen]）が表示され始めた日時
  ///   （`initState()`の時点、端末の時計）。
  /// - [durationSeconds] : [startedAt]から、「Answer!」を押して正誤判定
  ///   されるまでの経過時間（秒）。
  /// - [dragCount] : その問題を解いている間に、ピースをドラッグして
  ///   どこかに離した回数。
  /// - `dataVersion` : 問題データ・出題仕様の版（[kDataVersion]）。無い記録は旧版。
  /// - `answeredAt` : 通常はサーバー時刻。送り直した記録だけ、解答した端末の時刻
  ///   （送り直しが遅れても、解答の時刻がずれないようにするため）。
  static Future<void> recordAttempt({
    required PuzzleWord puzzle,
    required bool isCorrect,
    required DateTime startedAt,
    required double durationSeconds,
    required int dragCount,
  }) async {
    if (!backend.isEnabled) return; // 現時点でWeb版のみ対応（Firebase未初期化のため）。
    _ensureListening();
    _Attempt? attempt;
    try {
      final participantId = await ParticipantService.getParticipantId();
      if (participantId == null) return;

      attempt = _Attempt(
        id: backend.newDocId(participantId),
        participantId: participantId,
        data: AttemptData(
          word: puzzle.word,
          level: puzzle.level,
          isCorrect: isCorrect,
          answeredAt: DateTime.now(),
          startedAt: startedAt,
          durationSeconds: durationSeconds,
          dragCount: dragCount,
          dataVersion: kDataVersion,
        ),
      );
      _open.add(attempt);

      var uid = AuthService.currentUid;
      if (uid == null) {
        // 起動時のログインが終わっていない・失敗していたので、保存の前に1回だけ試す。
        await AuthService.ensureSignedIn();
        uid = AuthService.currentUid;
      }
      if (uid == null) {
        _markNotSaved(attempt, _SaveState.unsent);
        return;
      }

      // ログインできている間に、前に保存できなかった解答も送り直す。
      unawaited(flushPending());
      await _send(attempt, uid, useServerTime: true);
    } catch (_) {
      // 想定外の失敗も、ゲーム本体を妨げないよう外に出さず、「記録できなかった」に数える。
      if (attempt != null && attempt.state != _SaveState.saved) {
        _markNotSaved(attempt, _SaveState.failed);
      }
    }
  }

  /// 保存できていない記録（サーバーに拒否された・未送信のもの）を、同じIDで送り直す。
  /// ログインできたとき・次の解答のときに呼ばれる。「未確認」の記録は、Firestoreが
  /// 内部に保持していて送られるので、ここでは送らない（二重に送ると、2回目が
  /// 「更新」とみなされて拒否される）。
  static Future<void> flushPending() async {
    final uid = AuthService.currentUid;
    if (uid == null || _flushing) return;
    _flushing = true;
    try {
      final targets = _open
          .where((a) =>
              (a.state == _SaveState.failed || a.state == _SaveState.unsent) &&
              a.tries < maxTries)
          .toList();
      for (final a in targets) {
        await _send(a, uid, useServerTime: false);
      }
    } finally {
      _flushing = false;
    }
  }

  static Future<void> _send(_Attempt a, String uid, {required bool useServerTime}) async {
    a.state = _SaveState.sending;
    a.tries++;
    a.timer?.cancel();
    a.timer = Timer(confirmTimeout, () {
      if (a.state == _SaveState.sending) _markNotSaved(a, _SaveState.unconfirmed);
    });
    try {
      await backend.write(
        participantId: a.participantId,
        docId: a.id,
        ownerUid: uid,
        data: a.data,
        useServerTime: useServerTime,
      );
      a.timer?.cancel();
      a.state = _SaveState.saved;
      _open.remove(a);
      _noticeShown = false; // 保存できたので、次に問題が起きたらまた案内を出す。
      _refresh();
    } catch (_) {
      a.timer?.cancel();
      _markNotSaved(a, _SaveState.failed);
    }
  }

  static void _markNotSaved(_Attempt a, _SaveState state) {
    a.state = state;
    _refresh();
    // 案内は、同じ状態の間は1回だけ（保存に成功したら、またリセットされる）。
    if (!_noticeShown) {
      _noticeShown = true;
      noticeRequests.value++;
    }
  }

  static void _refresh() {
    unsavedCount.value = _open
        .where((a) =>
            a.state == _SaveState.unconfirmed ||
            a.state == _SaveState.failed ||
            a.state == _SaveState.unsent)
        .length;
  }

  /// ログインに成功したら、溜まっていた記録を送り直す。
  static void _ensureListening() {
    if (_listening) return;
    _listening = true;
    AuthService.status.addListener(() {
      if (AuthService.status.value == AuthStatus.signedIn) unawaited(flushPending());
    });
  }

  /// テスト用：状態を初期化し、バックエンドを差し替える。
  @visibleForTesting
  static void resetForTest(RecordBackend newBackend) {
    for (final a in _open) {
      a.timer?.cancel();
    }
    _open.clear();
    backend = newBackend;
    _noticeShown = false;
    _flushing = false;
    unsavedCount.value = 0;
    noticeRequests.value = 0;
  }
}
