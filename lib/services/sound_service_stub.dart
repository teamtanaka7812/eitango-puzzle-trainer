/// [sound_service.dart]の条件付きエクスポート先（Web以外の環境向け）。
/// `speechSynthesis`・`AudioContext`はブラウザ専用のAPIのため、Web以外では
/// 何もしない（呼び出しても静かに無視する）実装にする。これにより、将来
/// スマホアプリ向けにビルドしてもコンパイルが壊れず、音が出ないだけで
/// 他の動作には影響しない。
library;

void playCorrectSound() {}

void playIncorrectSound() {}

void speak(String text, {String lang = 'en-US'}) {}
