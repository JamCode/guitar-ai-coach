import 'package:flutter/material.dart';

import '../chords/chord_lookup_screen.dart';
import '../theory/chord_chart_screen.dart';
import '../theory/theory_screen.dart';
import '../tuner/tuner_screen.dart';

/// 工具 Tab 入口：调音、和弦查询、静态乐理与和弦表。
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
          leading: const Icon(Icons.piano_rounded),
          title: const Text('和弦查询'),
          subtitle: const Text('对接后端多套按法说明'),
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const ChordLookupScreen()),
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
          subtitle: const Text('常用三和弦与七和弦速查'),
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
