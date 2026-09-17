import 'package:flutter/material.dart';

import '../services/participant_service.dart';
import 'home_screen.dart';

/// 初回起動時に表示する、参加者ID入力画面。
/// 入力されたIDは端末に保存し、[onSaved]でホーム画面へ進む
/// （[onSaved]を省略した場合はホーム画面へ直接遷移する。設定画面からの
/// 再入力時は、呼び出し側で戻り方を制御できるようにするため）。
class ParticipantIdScreen extends StatefulWidget {
  const ParticipantIdScreen({super.key, this.onSaved});

  final VoidCallback? onSaved;

  @override
  State<ParticipantIdScreen> createState() => _ParticipantIdScreenState();
}

class _ParticipantIdScreenState extends State<ParticipantIdScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    await ParticipantService.setParticipantId(_controller.text.trim());
    if (!mounted) return;

    if (widget.onSaved != null) {
      widget.onSaved!();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE3F2FD), Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_rounded, size: 56, color: Color(0xFF5B9BD5)),
                    const SizedBox(height: 24),
                    Text(
                      '参加者IDを入力してください',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF37474F),
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'アンケートで案内された番号などを入力してください。\n'
                      '一度入力すると、次回からは表示されません。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF78909C)),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _controller,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20),
                      decoration: const InputDecoration(
                        hintText: '例：1234',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '参加者IDを入力してください';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B9BD5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('はじめる', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
