import 'package:flutter/material.dart';

import '../widgets/sheep_guide.dart';
import 'coming_soon_screen.dart';
import 'level_select_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const routeName = '/';

  static const _menuItems = [
    _MenuItem(label: 'START', icon: Icons.play_arrow_rounded, color: Color(0xFFEF9A9A)),
    _MenuItem(label: 'HISTORY', icon: Icons.bar_chart_rounded, color: Color(0xFF90CAF9)),
    _MenuItem(label: 'WORD BOOK', icon: Icons.menu_book_rounded, color: Color(0xFFA5D6A7)),
    _MenuItem(label: 'ENCYCLOPEDIA', icon: Icons.auto_stories_rounded, color: Color(0xFFFFE082)),
  ];

  void _onMenuTap(BuildContext context, String label) {
    if (label == 'START') {
      Navigator.of(context).pushNamed(LevelSelectScreen.routeName);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ComingSoonScreen(title: label)),
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
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 32),
                  Text(
                    '英単語パズルトレーナー',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF37474F),
                        ),
                  ),
                  const SizedBox(height: 48),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final item in _menuItems) ...[
                            _MenuButton(
                              item: item,
                              onTap: () => _onMenuTap(context, item.label),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: SheepGuide(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.item, required this.onTap});

  final _MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 64,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(item.icon, size: 26),
        label: Text(
          item.label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: item.color,
          foregroundColor: const Color(0xFF37474F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 3,
        ),
      ),
    );
  }
}
