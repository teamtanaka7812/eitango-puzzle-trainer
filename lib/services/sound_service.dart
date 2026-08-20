/// 効果音（正解ファンファーレ・不正解ブザー）と、英語読み上げ（Web Speech API）
/// をまとめて提供する。実体はWeb版（[sound_service_web.dart]）とそれ以外向けの
/// 何もしない実装（[sound_service_stub.dart]）に分かれており、コンパイル時に
/// 自動で切り替わる。
///
/// - [playCorrectSound] : 正解時のファンファーレを鳴らす。
/// - [playIncorrectSound] : 不正解時のブザー音を鳴らす。
/// - [speak] : 与えたテキストを英語の音声合成で読み上げる。
library;

export 'sound_service_stub.dart' if (dart.library.js_interop) 'sound_service_web.dart';
