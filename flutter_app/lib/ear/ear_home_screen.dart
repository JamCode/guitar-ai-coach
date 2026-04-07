import 'package:flutter/material.dart';

import 'interval_ear_screen.dart';

/// 练耳 Tab：音程练习入口 + 一期 ABC 能力占位说明。
class EarHomeScreen extends StatelessWidget {
  const EarHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(Icons.play_circle_outline_rounded, color: scheme.primary),
            title: const Text('音程识别'),
            subtitle: const Text('两音上行、四选一（已实现）'),
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
        const SizedBox(height: 12),
        _StubCard(
          title: 'A · 单和弦听辨',
          body:
              '大三 / 小三 / 属七 听辨与干扰项策略，见仓库 '
              '`requirements/练耳训练一期-ABC-需求.md`。'
              ' 题库种子：`requirements/练耳题库-一期种子.json`（本期未接入 App）。',
        ),
        _StubCard(
          title: 'B · 和弦进行听辨',
          body: '2～4 个和弦的常见进行，流行场景优先；与 Web 练耳一期范围一致，后续迭代接入。',
        ),
        _StubCard(
          title: 'C · 错题本与每日 10 题',
          body: '个性化复习与连续打卡指标，需本地/服务端学习记录表，本期仅占位。',
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
