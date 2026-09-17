import 'package:flutter/material.dart';

import '../services/local_history_service.dart';

/// 学習履歴（解答数・正解数・正答率）を表示する画面。
/// 端末内に保存された集計値（[LocalHistoryService]）を表示する
/// （オフラインでも表示できるようにするため。Firestoreへの送信とは別経路）。
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  static const routeName = '/history';

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<HistoryStats> _stats;

  @override
  void initState() {
    super.initState();
    _stats = LocalHistoryService.loadStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HISTORY')),
      body: FutureBuilder<HistoryStats>(
        future: _stats,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snapshot.data!;
          if (stats.totalAnswered == 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'まだ記録がありません。\nパズルを解くと、ここに成績が表示されます。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF78909C), fontSize: 16),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _OverallCard(stats: stats),
              const SizedBox(height: 20),
              const Text(
                'レベルごとの内訳',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF37474F)),
              ),
              const SizedBox(height: 8),
              for (final level in [1, 2, 3]) ...[
                _LevelRow(level: level, stats: stats.byLevel[level]!),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.stats});

  final HistoryStats stats;

  @override
  Widget build(BuildContext context) {
    final accuracyText =
        stats.totalAccuracy == null ? '-' : '${(stats.totalAccuracy! * 100).round()}%';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Stat(label: '解いた問題数', value: '${stats.totalAnswered}'),
          _Stat(label: '正解数', value: '${stats.totalCorrect}'),
          _Stat(label: '正答率', value: accuracyText),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF37474F)),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF78909C))),
      ],
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.level, required this.stats});

  final int level;
  final LevelHistoryStats stats;

  @override
  Widget build(BuildContext context) {
    final accuracyText = stats.accuracy == null ? '-' : '${(stats.accuracy! * 100).round()}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFECEFF1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            'Level $level',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF37474F)),
          ),
          const Spacer(),
          Text(
            '${stats.correct} / ${stats.answered} 問正解',
            style: const TextStyle(color: Color(0xFF78909C)),
          ),
          const SizedBox(width: 16),
          Text(
            accuracyText,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF37474F)),
          ),
        ],
      ),
    );
  }
}
