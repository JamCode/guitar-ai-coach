import 'package:flutter/material.dart';

import 'ear_mcq_session_screen.dart';
import 'interval_ear_screen.dart';
import 'sight_singing_setup_screen.dart';

/// 练耳 Tab：自由练习式入口（音程 / 和弦性质 / 和弦进行）+ C 占位。
class EarHomeScreen extends StatelessWidget {
  const EarHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '自由练习',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: Icon(
              Icons.play_circle_outline_rounded,
              color: scheme.primary,
            ),
            title: const Text('音程识别'),
            subtitle: const Text('两音上行、四选一'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const IntervalEarScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.piano, color: scheme.primary),
            title: const Text('和弦听辨'),
            subtitle: const Text('大三 / 小三 / 属七 · 题库离线 · 吉他采样合成'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const EarMcqSessionScreen(
                    title: '和弦听辨',
                    bank: 'A',
                    totalQuestions: 10,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.queue_music_rounded, color: scheme.primary),
            title: const Text('和弦进行'),
            subtitle: const Text('常见流行进行 · 四选一'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const EarMcqSessionScreen(
                    title: '和弦进行',
                    bank: 'B',
                    totalQuestions: 10,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(
              Icons.record_voice_over_rounded,
              color: scheme.primary,
            ),
            title: const Text('视唱训练'),
            subtitle: const Text('单音视唱 · 可选音域 · 麦克风实时判定'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const SightSingingSetupScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        _StubCard(
          title: 'C · 错题本与每日 10 题',
          body:
              '个性化复习与连续打卡；依赖本地学习记录。需求见 '
              '`requirements/练耳训练一期-ABC-需求.md`。',
        ),
      ],
    );
  }
}

class _StubCard extends StatelessWidget {
  const _StubCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '即将推出',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
