import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Firebase匿名認証（画面には一切出さず、裏側でサインインするだけ）。
///
/// 匿名認証はブラウザに認証状態が保存されるため、2回目以降の起動では
/// 同じUID（[FirebaseAuth.instance.currentUser?.uid]）が再利用される
/// （毎回新しい匿名アカウントが作られるわけではない）。学習記録の書き込み・
/// 読み取りは、このUIDを本人確認の代わりに使う（`firestore.rules`参照）。
class AuthService {
  /// アプリ起動時に一度だけ呼ぶ。Web版以外では何もしない
  /// （Firebase自体を初期化していないため）。失敗しても（Firebaseコンソール側で
  /// 匿名認証が有効化されていない、通信できないなど）例外は投げず、静かに諦める
  /// ——パズル本体の起動・プレイは、学習記録の送信可否に関わらず動作すべきため。
  /// この場合[currentUid]はnullのままになり、[LearningRecordService]は
  /// 書き込みをスキップする。
  static Future<void> ensureSignedIn() async {
    if (!kIsWeb) return;
    if (FirebaseAuth.instance.currentUser != null) return;
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {
      // 意図的に無視する（上記コメント参照）。
    }
  }

  /// 現在の匿名認証UID。サインイン前・Web以外ではnull。
  static String? get currentUid => kIsWeb ? FirebaseAuth.instance.currentUser?.uid : null;
}
