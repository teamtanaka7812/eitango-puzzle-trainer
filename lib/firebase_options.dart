import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

/// Firebaseプロジェクト（`eitango-puzzle-trainer`）の接続情報。
///
/// 通常はFlutterFire CLI（`flutterfire configure`）が自動生成するファイルだが、
/// この開発環境にはCLIが入っていないため、人手で用意した値をそのまま使っている。
/// 現時点ではWeb版のみ対応（2026年時点の決定）。他プラットフォーム向けの値は
/// 用意していないため、[currentPlatform]はWeb以外では例外を投げる。
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions は現時点でWeb版のみに対応しています '
      '（defaultTargetPlatform=$defaultTargetPlatform ではFirebaseを初期化していません）。',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBDH0Oh6gd5J93k-hUahDe3YJGUyT0AfVo',
    authDomain: 'eitango-puzzle-trainer.firebaseapp.com',
    projectId: 'eitango-puzzle-trainer',
    storageBucket: 'eitango-puzzle-trainer.firebasestorage.app',
    messagingSenderId: '545945177675',
    appId: '1:545945177675:web:4fb9b441a7e957789c87ce',
  );
}
