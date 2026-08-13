import 'package:flutter/material.dart';

import 'level_play_screen.dart';

class LevelSelectScreen extends StatelessWidget {
  const LevelSelectScreen({super.key});

  static const routeName = '/level-select';

  static const _levels = [
    _LevelItem(level: 1, label: 'Level 1', subtitle: '英検3級程度', color: Color(0xFFA5D6A7)),
    _LevelItem(level: 2, label: 'Level 2', subtitle: '英検準2級程度', color: Color(0xFF90CAF9)),
    _LevelItem(level: 3, label: 'Level 3', subtitle: '英検2級程度', color: Color(0xFFFFCC80)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('レベル選択')),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'レベルをえらんでね',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF37474F),
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 32),
                for (final level in _levels) ...[
                  _LevelButton(
                    item: level,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LevelPlayScreen(level: level.level),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelItem {
  const _LevelItem({
    required this.level,
    required this.label,
    required this.subtitle,
    required this.color,
  });

  final int level;
  final String label;
  final String subtitle;
  final Color color;
}

class _LevelButton extends StatelessWidget {
  const _LevelButton({required this.item, required this.onTap});

  final _LevelItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 76,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: item.color,
          foregroundColor: const Color(0xFF37474F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 3,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(item.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(item.subtitle, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
