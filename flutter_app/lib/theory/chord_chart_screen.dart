import 'package:flutter/material.dart';

/// 常用和弦类型速查（静态表，骨架阶段）。
class ChordChartScreen extends StatelessWidget {
  const ChordChartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('和弦表')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Section(
            title: '三和弦（Triads）',
            rows: [
              ('大三', 'C、D、E… 根音 + 大三度 + 纯五度，符号常写作 C、D…'),
              ('小三', 'Cm、Dm… 根音 + 小三度 + 纯五度'),
              ('减三', 'Cdim，根音 + 小三度 + 减五度'),
              ('增三', 'Caug，根音 + 大三度 + 增五度'),
            ],
          ),
          _Section(
            title: '常用七和弦',
            rows: [
              ('大七 maj7', 'Cmaj7，大七度色彩，爵士/流行抒情常见'),
              ('属七 7', 'C7，小七度 + 大三和弦，解决感强'),
              ('小七 m7', 'Cm7，柔和、略带布鲁斯味'),
              ('半减 m7♭5', 'Cm7♭5，二级小调或过渡常用'),
            ],
          ),
          _Section(
            title: '挂留与加音',
            rows: [
              ('sus2 / sus4', '用二度或四度替代三度，色彩空灵或开阔'),
              ('add9', '在完整三和弦上叠加九度音'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '具体把位请用「和弦查询」连接后端获取多套按法。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final r in rows) ...[
            Text(
              r.$1,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(r.$2, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
