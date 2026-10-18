import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/learning_record_service.dart';

/// 記録（ログイン・保存）がうまくいかないときの、小さな案内。
/// ゲームの進行は止めず、全画面のダイアログも使わない（2026年10月）。
/// 生徒向けなので、短いやさしい文言にしている。
const String kAuthFailedTitle = '記録の準備ができていません';
const String kAuthFailedBody =
    '通信を確認して「もう一度」を押してください。このままゲームはできますが、記録は残りません。';
const String kAuthStillFailed = 'まだつながりません。';
const String kAuthRetryLabel = 'もう一度';
const String kAuthRetryingLabel = '確認中…';
const String kSaveFailedNotice = 'この解答は記録できなかったかもしれません。通信を確認してください';

/// 結果画面に出す「記録できなかった問題：N問」。
String unsavedCountText(int count) => '記録できなかった問題：$count問';

/// どの画面からでも案内（SnackBar）を出せるよう、アプリ全体で共有するキー。
final GlobalKey<ScaffoldMessengerState> kMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// ログインに失敗しているとき、ホーム画面などに出す小さな案内と「もう一度」ボタン。
/// 成功したら消える。ログインに失敗していなければ何も表示しない（場所も取らない）。
class AuthStatusBanner extends StatefulWidget {
  const AuthStatusBanner({super.key});

  @override
  State<AuthStatusBanner> createState() => _AuthStatusBannerState();
}

class _AuthStatusBannerState extends State<AuthStatusBanner> {
  bool _retrying = false;
  bool _retryFailed = false;

  Future<void> _retry() async {
    setState(() {
      _retrying = true;
      _retryFailed = false;
    });
    final ok = await AuthService.ensureSignedIn();
    if (!mounted) return;
    setState(() {
      _retrying = false;
      _retryFailed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthStatus>(
      valueListenable: AuthService.status,
      builder: (context, status, _) {
        // 失敗したときだけ出す。「もう一度」を押して確認している最中は、そのまま残す。
        if (status != AuthStatus.failed && !_retrying) return const SizedBox.shrink();
        return Container(
          key: const ValueKey('auth_banner'),
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            border: Border.all(color: const Color(0xFFFFB74D)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 20, color: Color(0xFFEF6C00)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      kAuthFailedTitle,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
                    ),
                    Text(
                      _retryFailed ? '$kAuthStillFailed$kAuthFailedBody' : kAuthFailedBody,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037), height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _retrying ? null : _retry,
                child: Text(_retrying ? kAuthRetryingLabel : kAuthRetryLabel),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 記録の保存がうまくいかなかったときに、小さな案内（SnackBar）を出す。
/// [LearningRecordService]が同じ状態の間は1回だけ合図を出すので、解答のたびには出ない。
/// アプリ全体を包んで使う（[kMessengerKey]を`MaterialApp`に渡す）。
class RecordingNoticeListener extends StatefulWidget {
  const RecordingNoticeListener({super.key, required this.child});

  final Widget child;

  @override
  State<RecordingNoticeListener> createState() => _RecordingNoticeListenerState();
}

class _RecordingNoticeListenerState extends State<RecordingNoticeListener> {
  @override
  void initState() {
    super.initState();
    LearningRecordService.noticeRequests.addListener(_show);
  }

  @override
  void dispose() {
    LearningRecordService.noticeRequests.removeListener(_show);
    super.dispose();
  }

  void _show() {
    final messenger = kMessengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text(kSaveFailedNotice),
        behavior: SnackBarBehavior.floating,
        // 画面下のボタン行に重ならないよう、浮かせて少し上に出す。
        margin: EdgeInsets.fromLTRB(24, 0, 24, 110),
        duration: Duration(seconds: 7),
      ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 結果画面に出す、「記録できなかった問題：N問」。0問なら何も表示しない。
class UnsavedCountLabel extends StatelessWidget {
  const UnsavedCountLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: LearningRecordService.unsavedCount,
      builder: (context, count, _) {
        if (count <= 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            unsavedCountText(count),
            key: const ValueKey('unsaved_count'),
            style: const TextStyle(fontSize: 12, color: Color(0xFFEF6C00)),
          ),
        );
      },
    );
  }
}
