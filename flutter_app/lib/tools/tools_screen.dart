import 'package:flutter/material.dart';

import '../chords/chord_lookup_screen.dart';
import 'fretboard_screen.dart';
import '../theory/chord_chart_screen.dart';
import '../theory/theory_screen.dart';
import '../tuner/tuner_screen.dart';

/// 工具 Tab 入口：调音、吉他指板、和弦查询、静态乐理与和弦表。
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.graphic_eq_rounded),
          title: const Text('调音器'),
          subtitle: const Text('麦克风拾音与标准空弦目标'),
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const TunerScreen()),
            );
          },
        ),
        ListTile(
          key: const Key('tools_open_fretboard'),
          leading: const Icon(Icons.view_week_outlined),
          title: const Text('吉他指板'),
          subtitle: const Text('竖向指板 · 音名 · 变调夹'),
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const FretboardScreen()),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.piano_rounded),
          title: const Text('和弦字典'),
          subtitle: const Text('离线可查构成音与常见把位；可选联网更多按法'),
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const ChordLookupScreen(),
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('初级乐理'),
          subtitle: const Text('音程、调式等入门提要'),
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const TheoryScreen()),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.grid_on_outlined),
          title: const Text('和弦表'),
          subtitle: const Text('初/中/高分段 · 本地指法图速查'),
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const ChordChartScreen()),
            );
          },
        ),
      ],
    );
  }
}
