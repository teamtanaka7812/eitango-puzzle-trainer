import 'dart:async';

import 'package:flutter/foundation.dart';

import 'firebase_backends.dart';

/// ログインの状態。
enum AuthStatus {
  /// まだ試していない（Web以外もここのまま）。
  idle,

  /// ログインしようとしている最中。
  signingIn,

  /// ログイン済み（記録を保存できる）。
  signedIn,

  /// ログインに失敗した（通信できない・1時間あたりの新規作成の上限に達した、など）。
  failed,
}

/// Firebase匿名認証（通常は画面に出ず、裏側でサインインする）。
///
/// 匿名認証はブラウザに認証状態が保存されるため、2回目以降の起動では
/// 同じUID（[currentUid]）が再利用される（毎回新しい匿名アカウントが
/// 作られるわけではない）。学習記録の書き込みは、このUIDを本人確認の
/// 代わりに使う（`firestore.rules`参照）。
///
/// ログインに失敗してもゲーム本体は動くが、記録は保存できない。そのため
/// 失敗は[status]で知らせ、ホーム画面などの案内（`AuthStatusBanner`）が
/// 「もう一度」ボタンで[ensureSignedIn]を呼び直せるようにしている
/// （2026年10月。以前は起動時に1回だけ試し、失敗しても何も出なかった）。
class AuthService {
  /// ログインが終わるのを待つ時間。これを過ぎたら「失敗」として案内を出す
  /// （通信が止まっていても、いつまでも「確認中」のままにしないため）。
  /// 過ぎたあとで成功したときは、自動で[AuthStatus.signedIn]に戻る。
  static const signInTimeout = Duration(seconds: 10);

  /// Firebaseとのやりとり。テストでは模擬に差し替える。
  static AuthBackend backend = kIsWeb ? FirebaseAuthBackend() : DisabledAuthBackend();

  /// 画面（案内）が見守るログイン状態。
  static final ValueNotifier<AuthStatus> status = ValueNotifier(AuthStatus.idle);

  static Future<bool>? _inFlight;

  /// Firebaseに実際に出している、ログインの要求。時間切れになったあとも続いている
  /// ことがあるので、終わるまでは新しく出し直さない（二重に匿名アカウントが作られない
  /// ようにするため）。
  static Future<void>? _rawAttempt;

  /// 現在の匿名認証UID。ログイン前・Web以外ではnull。
  static String? get currentUid => backend.isEnabled ? backend.currentUid : null;

  /// ログイン済みにする。成功（すでにログイン済みを含む）ならtrue。
  /// 失敗しても例外は投げず、falseを返して[status]を[AuthStatus.failed]にする
  /// （パズル本体の起動・プレイは、記録の保存可否に関わらず動くべきため）。
  /// ログイン処理の最中に呼ばれたときは、同じ処理の結果を返す（二重に試さない）。
  static Future<bool> ensureSignedIn() {
    if (!backend.isEnabled) return Future.value(false);
    if (backend.currentUid != null) {
      _set(AuthStatus.signedIn);
      return Future.value(true);
    }
    return _inFlight ??= _signIn().whenComplete(() => _inFlight = null);
  }

  static Future<bool> _signIn() async {
    _set(AuthStatus.signingIn);
    final attempt = _rawAttempt ??= backend.ensureSignedIn().whenComplete(() => _rawAttempt = null);
    try {
      await attempt.timeout(signInTimeout);
      final ok = backend.currentUid != null;
      _set(ok ? AuthStatus.signedIn : AuthStatus.failed);
      return ok;
    } on TimeoutException {
      // 時間内に終わらなかった。処理は続いているので、あとで成功したら元に戻す。
      unawaited(attempt.then((_) {
        if (backend.currentUid != null) _set(AuthStatus.signedIn);
      }, onError: (_) {}));
      _set(AuthStatus.failed);
      return false;
    } catch (_) {
      // 通信できない、匿名ログインが有効でない、上限に達した、など理由は問わない。
      _set(AuthStatus.failed);
      return false;
    }
  }

  static void _set(AuthStatus value) {
    if (status.value != value) status.value = value;
  }

  /// テスト用：状態を初期化し、バックエンドを差し替える。
  @visibleForTesting
  static void resetForTest(AuthBackend newBackend) {
    backend = newBackend;
    _inFlight = null;
    _rawAttempt = null;
    status.value = AuthStatus.idle;
  }
}
