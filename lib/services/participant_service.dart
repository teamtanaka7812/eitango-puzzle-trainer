import 'package:shared_preferences/shared_preferences.dart';

/// アンケート参加者ID（研究・データ収集用にアプリ利用者へ割り振られた番号など）を
/// 端末内に保存・取得する。一度入力されたIDは端末に保存され、次回起動時は
/// 入力画面を出さずにそのまま使う。
class ParticipantService {
  static const _prefsKey = 'participant_id';

  /// 保存済みの参加者IDを返す。未保存（初回起動）ならnull。
  static Future<String?> getParticipantId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefsKey);
    return (id == null || id.isEmpty) ? null : id;
  }

  /// 参加者IDを端末に保存する。
  static Future<void> setParticipantId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id);
  }
}
