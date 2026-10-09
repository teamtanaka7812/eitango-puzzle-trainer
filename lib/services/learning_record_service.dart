import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../data_version.dart';
import '../models/puzzle_word.dart';
import 'auth_service.dart';
import 'participant_service.dart';

/// 学習データ収集（アンケート・研究用）のためのFirestoreへの書き込み。
///
/// **できれば行う程度の扱い**：通信状況に関わらずゲーム本体の動作（正誤判定・
/// 画面遷移）を止めない・遅らせないため、呼び出し側（[GameScreen]）は
/// このメソッドの完了を待たない（`await`しない）。内部でも例外はすべて
/// 握りつぶし、失敗しても黙って諦める。
class LearningRecordService {
  /// 1問答えるたびに呼ぶ。`participants/{参加者ID}/attempts`に1件追加する。
  ///
  /// [startedAt]・[durationSeconds]・[dragCount]は、試用者の取り組み方を
  /// 詳しく分析するための研究データ用の項目（2026年9月追加）。HISTORY画面
  /// では使わず、Firestoreに送る記録にのみ含める（端末内
  /// [LocalHistoryService]の保存方式は変更しない、という決定）。
  /// - [startedAt] : その問題の画面（[GameScreen]）が表示され始めた日時
  ///   （`initState()`の時点、端末の時計）。過去の一時点を記録するため
  ///   `FieldValue.serverTimestamp()`ではなく`Timestamp.fromDate()`を使う。
  /// - [durationSeconds] : [startedAt]から、「Answer!」を押して正誤判定
  ///   されるまでの経過時間（秒）。
  /// - [dragCount] : その問題を解いている間に、ピースをドラッグして
  ///   どこかに離した回数（結果が解答欄への設置・置き直し・トレイへの
  ///   取り出しのいずれであっても、ドラッグ操作1回につき1）。
  /// - `dataVersion` : 問題データ・出題仕様の版（[kDataVersion]）。無い記録は旧版。
  static Future<void> recordAttempt({
    required PuzzleWord puzzle,
    required bool isCorrect,
    required DateTime startedAt,
    required double durationSeconds,
    required int dragCount,
  }) async {
    if (!kIsWeb) return; // 現時点でWeb版のみ対応（Firebase未初期化のため）。
    try {
      final participantId = await ParticipantService.getParticipantId();
      final ownerUid = AuthService.currentUid;
      if (participantId == null || ownerUid == null) return;

      await FirebaseFirestore.instance
          .collection('participants')
          .doc(participantId)
          .collection('attempts')
          .add({
        'word': puzzle.word,
        'level': puzzle.level,
        'isCorrect': isCorrect,
        'answeredAt': FieldValue.serverTimestamp(),
        'ownerUid': ownerUid,
        'startedAt': Timestamp.fromDate(startedAt),
        'durationSeconds': durationSeconds,
        'dragCount': dragCount,
        'dataVersion': kDataVersion,
      });
    } catch (_) {
      // 通信できない・権限エラーなど、理由を問わず黙って諦める
      // （学習データ収集はあくまで裏方の処理であり、ゲーム本体の動作を
      // 妨げてはならないため）。
    }
  }
}
