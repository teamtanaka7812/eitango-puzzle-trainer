import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
  static Future<void> recordAttempt({required PuzzleWord puzzle, required bool isCorrect}) async {
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
      });
    } catch (_) {
      // 通信できない・権限エラーなど、理由を問わず黙って諦める
      // （学習データ収集はあくまで裏方の処理であり、ゲーム本体の動作を
      // 妨げてはならないため）。
    }
  }
}
