import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../firebase_options.dart';

/// ログイン(匿名認証)の、Firebaseとのやりとりだけを担当する部分。
/// [AuthService]はこのインターフェース越しに使うので、テストでは模擬の実装に
/// 差し替えられる（実際のFirebaseには接続しない）。
abstract class AuthBackend {
  /// このプラットフォームで使えるか。Web以外ではFirebaseを初期化していないのでfalse。
  bool get isEnabled;

  /// 今ログインしているアカウントのID。未ログインならnull。
  String? get currentUid;

  /// Firebaseを初期化し、未ログインなら匿名でログインする。失敗したら例外を投げる。
  Future<void> ensureSignedIn();
}

/// 解答1回ぶんの記録の中身（Firestoreに書く項目のうち、解答ごとに決まるもの）。
class AttemptData {
  const AttemptData({
    required this.word,
    required this.level,
    required this.isCorrect,
    required this.answeredAt,
    required this.startedAt,
    required this.durationSeconds,
    required this.dragCount,
    required this.dataVersion,
  });

  final String word;
  final int level;
  final bool isCorrect;

  /// 解答した端末の時刻。通常の書き込みではサーバー時刻を使うので、再送のときだけ使う。
  final DateTime answeredAt;
  final DateTime startedAt;
  final double durationSeconds;
  final int dragCount;
  final String dataVersion;
}

/// 解答の記録(Firestore)の、書き込みだけを担当する部分。テストでは模擬に差し替える。
abstract class RecordBackend {
  bool get isEnabled;

  /// 記録のIDを、通信せずにその場で作る（Firestoreの自動IDと同じ形式）。
  /// アプリ側で先にIDを決めておくので、再送しても同じIDになり、重複しない。
  String newDocId(String participantId);

  /// 記録を書き込む。サーバーが受け付けたら完了、拒否されたら例外。
  /// 通信が切れている間は、完了しないまま待つ（Firestoreが内部で保持して、
  /// 復帰後に送る。ただしページを閉じる・再読み込みすると失われる）。
  ///
  /// [useServerTime]がtrueなら`answeredAt`にサーバー時刻を使う（通常）。falseなら
  /// [AttemptData.answeredAt]（解答した端末の時刻）を使う（再送のとき）。
  Future<void> write({
    required String participantId,
    required String docId,
    required String ownerUid,
    required AttemptData data,
    required bool useServerTime,
  });
}

/// 本物のFirebase Authentication。
class FirebaseAuthBackend implements AuthBackend {
  @override
  bool get isEnabled => kIsWeb;

  @override
  String? get currentUid {
    if (!kIsWeb || Firebase.apps.isEmpty) return null;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  Future<void> ensureSignedIn() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    if (FirebaseAuth.instance.currentUser != null) return;
    await FirebaseAuth.instance.signInAnonymously();
  }
}

/// 本物のFirestore。`participants/{参加者ID}/attempts/{記録ID}`に書く。
class FirestoreRecordBackend implements RecordBackend {
  @override
  bool get isEnabled => kIsWeb;

  CollectionReference<Map<String, dynamic>> _attempts(String participantId) =>
      FirebaseFirestore.instance
          .collection('participants')
          .doc(participantId)
          .collection('attempts');

  @override
  String newDocId(String participantId) => _attempts(participantId).doc().id;

  @override
  Future<void> write({
    required String participantId,
    required String docId,
    required String ownerUid,
    required AttemptData data,
    required bool useServerTime,
  }) {
    // 新しいIDへのset()は「作成」として扱われるので、セキュリティルール
    // （作成は本人のownerUidのみ・更新と削除は不可）を変えなくてよい。
    return _attempts(participantId).doc(docId).set({
      'word': data.word,
      'level': data.level,
      'isCorrect': data.isCorrect,
      'answeredAt': useServerTime
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(data.answeredAt),
      'ownerUid': ownerUid,
      'startedAt': Timestamp.fromDate(data.startedAt),
      'durationSeconds': data.durationSeconds,
      'dragCount': data.dragCount,
      'dataVersion': data.dataVersion,
    });
  }
}

/// Web以外で使う、何もしない実装（Firebaseを初期化していないため）。
class DisabledAuthBackend implements AuthBackend {
  @override
  bool get isEnabled => false;
  @override
  String? get currentUid => null;
  @override
  Future<void> ensureSignedIn() async {}
}

class DisabledRecordBackend implements RecordBackend {
  @override
  bool get isEnabled => false;
  @override
  String newDocId(String participantId) => '';
  @override
  Future<void> write({
    required String participantId,
    required String docId,
    required String ownerUid,
    required AttemptData data,
    required bool useServerTime,
  }) async {}
}
