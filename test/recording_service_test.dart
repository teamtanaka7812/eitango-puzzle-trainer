import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:word_puzzle_trainer/data_version.dart';
import 'package:word_puzzle_trainer/models/puzzle_word.dart';
import 'package:word_puzzle_trainer/services/auth_service.dart';
import 'package:word_puzzle_trainer/services/firebase_backends.dart';
import 'package:word_puzzle_trainer/services/learning_record_service.dart';

/// 模擬のログイン。実際のFirebaseには接続しない。
class FakeAuthBackend implements AuthBackend {
  /// 次の[ensureSignedIn]がどうなるか。nullなら成功、Completerなら完了を待つ。
  bool failNext = false;
  Completer<void>? hold;
  int calls = 0;
  String? uid;

  @override
  bool get isEnabled => true;

  @override
  String? get currentUid => uid;

  @override
  Future<void> ensureSignedIn() async {
    calls++;
    if (uid != null) return;
    final h = hold;
    if (h != null) await h.future;
    if (failNext) throw StateError('ログインできない');
    uid = 'uid-1';
  }
}

class WriteCall {
  WriteCall(this.participantId, this.docId, this.ownerUid, this.data, this.useServerTime);
  final String participantId;
  final String docId;
  final String ownerUid;
  final AttemptData data;
  final bool useServerTime;
}

/// 模擬のFirestore。実際のFirestoreには書き込まない。
class FakeRecordBackend implements RecordBackend {
  final List<WriteCall> calls = [];

  /// 保存済み（サーバーが受け付けた）記録。IDをキーにする（同じIDは上書き＝重複しない）。
  final Map<String, WriteCall> saved = {};

  /// 次の書き込みの結果。'ok'（既定）・'fail'（拒否）・'hang'（通信が切れていて完了しない）。
  String mode = 'ok';
  final List<Completer<void>> hangs = [];
  int _id = 0;

  @override
  bool get isEnabled => true;

  @override
  String newDocId(String participantId) => 'doc-${++_id}';

  @override
  Future<void> write({
    required String participantId,
    required String docId,
    required String ownerUid,
    required AttemptData data,
    required bool useServerTime,
  }) async {
    final call = WriteCall(participantId, docId, ownerUid, data, useServerTime);
    calls.add(call);
    if (mode == 'fail') throw StateError('拒否された');
    if (mode == 'hang') {
      final c = Completer<void>();
      hangs.add(c);
      await c.future;
    }
    saved[docId] = call;
  }
}

const _puzzle = PuzzleWord(
  id: 'test',
  word: 'unhappy',
  level: 1,
  parts: [WordPiecePart(text: 'un'), WordPiecePart(text: 'happy')],
  meaning: '不幸な',
  exampleEn: 'e',
  exampleJa: 'j',
  presetChoices: [],
);

void main() {
  late FakeAuthBackend auth;
  late FakeRecordBackend records;

  Future<void> answer({bool correct = true}) => LearningRecordService.recordAttempt(
        puzzle: _puzzle,
        isCorrect: correct,
        startedAt: DateTime(2026, 10, 18, 10, 0, 0),
        durationSeconds: 12.5,
        dragCount: 4,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({'participant_id': 'Test-0001'});
    auth = FakeAuthBackend();
    records = FakeRecordBackend();
    AuthService.resetForTest(auth);
    LearningRecordService.resetForTest(records);
  });

  group('ログイン（AuthService）', () {
    test('成功するとsignedInになり、currentUidが取れる', () async {
      expect(await AuthService.ensureSignedIn(), isTrue);
      expect(AuthService.status.value, AuthStatus.signedIn);
      expect(AuthService.currentUid, 'uid-1');
    });

    test('失敗しても例外は出ず、failedになる。「もう一度」で成功すればsignedInに戻る', () async {
      auth.failNext = true;
      expect(await AuthService.ensureSignedIn(), isFalse);
      expect(AuthService.status.value, AuthStatus.failed);

      auth.failNext = false;
      expect(await AuthService.ensureSignedIn(), isTrue);
      expect(AuthService.status.value, AuthStatus.signedIn);
    });

    test('ログイン中に呼ばれても、二重には試さない', () async {
      auth.hold = Completer<void>();
      final a = AuthService.ensureSignedIn();
      final b = AuthService.ensureSignedIn();
      auth.hold!.complete();
      expect(await a, isTrue);
      expect(await b, isTrue);
      expect(auth.calls, 1);
    });

    testWidgets('時間内に終わらなければfailedにし、あとで成功したらsignedInに戻る', (tester) async {
      auth.hold = Completer<void>();
      bool? result;
      AuthService.ensureSignedIn().then((v) => result = v);
      await tester.pump(AuthService.signInTimeout + const Duration(seconds: 1));
      expect(result, isFalse);
      expect(AuthService.status.value, AuthStatus.failed);

      // 時間切れのあとに、ログインが終わった。
      auth.hold!.complete();
      await tester.pump();
      expect(AuthService.status.value, AuthStatus.signedIn);
    });
  });

  group('記録の保存（LearningRecordService）', () {
    test('ログイン済みなら1回の解答で1件だけ書き込む（IDはアプリ側で決める）', () async {
      auth.uid = 'uid-1';
      await answer();
      expect(records.calls, hasLength(1));
      final c = records.calls.single;
      expect(c.participantId, 'Test-0001');
      expect(c.docId, 'doc-1');
      expect(c.ownerUid, 'uid-1');
      expect(c.useServerTime, isTrue);
      expect(c.data.word, 'unhappy');
      expect(c.data.isCorrect, isTrue);
      expect(c.data.dragCount, 4);
      expect(c.data.dataVersion, kDataVersion);
      expect(LearningRecordService.unsavedCount.value, 0);
      expect(LearningRecordService.noticeRequests.value, 0);
    });

    test('ログインできていないとき、保存の前に1回だけログインを試みる', () async {
      await answer();
      expect(auth.calls, 1);
      expect(records.calls, hasLength(1));
      expect(records.saved, hasLength(1));
    });

    test('ログインできないままだと、送れず「記録できなかった」に数え、案内は1回だけ', () async {
      auth.failNext = true;
      await answer();
      await answer();
      await answer();
      // 解答のたびに1回ずつログインを試みる。
      expect(auth.calls, 3);
      expect(records.calls, isEmpty);
      expect(LearningRecordService.unsavedCount.value, 3);
      // 案内は、同じ状態の間は繰り返さない。
      expect(LearningRecordService.noticeRequests.value, 1);
    });

    test('ログインできたら、溜まっていた記録が同じIDで送られ、重複しない', () async {
      auth.failNext = true;
      await answer();
      await answer(correct: false);
      expect(LearningRecordService.unsavedCount.value, 2);

      auth.failNext = false;
      expect(await AuthService.ensureSignedIn(), isTrue);
      // ログイン成功の合図で、送り直しが走る。
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(records.saved.keys, unorderedEquals(['doc-1', 'doc-2']));
      expect(records.calls.map((c) => c.docId).toSet(), hasLength(2));
      expect(records.calls.every((c) => !c.useServerTime), isTrue); // 解答時刻は端末の時刻
      expect(records.saved['doc-2']!.data.isCorrect, isFalse);
      expect(LearningRecordService.unsavedCount.value, 0);
    });

    test('書き込みが拒否されたら数えて案内し、次の解答のときに同じIDで送り直す', () async {
      auth.uid = 'uid-1';
      records.mode = 'fail';
      await answer();
      expect(LearningRecordService.unsavedCount.value, 1);
      expect(LearningRecordService.noticeRequests.value, 1);

      // 同じ状態の間は、案内を繰り返さない。
      await answer();
      expect(LearningRecordService.unsavedCount.value, 2);
      expect(LearningRecordService.noticeRequests.value, 1);

      // 直ったので、次の解答で、これまでの2件も同じIDで送り直される。
      records.mode = 'ok';
      await answer();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(records.saved.keys, unorderedEquals(['doc-1', 'doc-2', 'doc-3']));
      expect(LearningRecordService.unsavedCount.value, 0);
      // 送り直した2件だけ、解答時刻に端末の時刻を使う。
      expect(records.saved['doc-1']!.useServerTime, isFalse);
      expect(records.saved['doc-3']!.useServerTime, isTrue);
    });

    test('成功が続いたあとに、また失敗したら、案内がもう一度出る', () async {
      auth.uid = 'uid-1';
      records.mode = 'fail';
      await answer();
      expect(LearningRecordService.noticeRequests.value, 1);

      records.mode = 'ok';
      await answer(); // 成功 → 状態がリセットされる
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(LearningRecordService.unsavedCount.value, 0);

      records.mode = 'fail';
      await answer();
      expect(LearningRecordService.noticeRequests.value, 2);
    });

    testWidgets('10秒たっても完了しないときは未確認として案内し、再送はしない。完了したら数えから外れる',
        (tester) async {
      auth.uid = 'uid-1';
      records.mode = 'hang';
      unawaited(answer());
      await tester.pump();
      expect(LearningRecordService.unsavedCount.value, 0);
      expect(LearningRecordService.noticeRequests.value, 0);

      await tester.pump(LearningRecordService.confirmTimeout + const Duration(seconds: 1));
      expect(LearningRecordService.unsavedCount.value, 1);
      expect(LearningRecordService.noticeRequests.value, 1);

      // さらに解答しても、案内は繰り返さない。保留中の記録は再送しない（二重に送らない）。
      unawaited(answer());
      await tester.pump();
      await tester.pump(LearningRecordService.confirmTimeout + const Duration(seconds: 1));
      expect(LearningRecordService.noticeRequests.value, 1);
      expect(records.calls.map((c) => c.docId).toSet(), hasLength(2)); // doc-1, doc-2だけ

      // 通信が復帰して、保留中の書き込みが完了した。
      records.mode = 'ok';
      for (final c in records.hangs) {
        c.complete();
      }
      await tester.pump();
      expect(LearningRecordService.unsavedCount.value, 0);
      expect(records.saved.keys, unorderedEquals(['doc-1', 'doc-2']));
      expect(records.calls, hasLength(2)); // 再送は発生していない
    });

    test('参加者IDが無いときは、何も書き込まず、数えもしない', () async {
      SharedPreferences.setMockInitialValues({});
      auth.uid = 'uid-1';
      await answer();
      expect(records.calls, isEmpty);
      expect(LearningRecordService.unsavedCount.value, 0);
    });

    test('Firebaseを使えない環境（Web以外）では何もしない', () async {
      final disabled = DisabledRecordBackend();
      LearningRecordService.resetForTest(disabled);
      await answer();
      expect(LearningRecordService.unsavedCount.value, 0);
      expect(LearningRecordService.noticeRequests.value, 0);
    });
  });
}
