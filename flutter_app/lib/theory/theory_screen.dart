import 'package:flutter/material.dart';

/// 初级乐理静态导读（骨架：无交互题库）。
class TheoryScreen extends StatelessWidget {
  const TheoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('初级乐理')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Section(
            title: '音名与十二平均律',
            body:
                '吉他上每一品约等于半音。空弦标准调弦从粗到细为 E、A、D、G、B、E。'
                '熟悉自然音阶内各音的相对位置，是读谱与扒歌的基础。',
          ),
          _Section(
            title: '音程（扒歌核心）',
            body:
                '两个音之间的「距离」称为音程。先练会：纯四度、纯五度、大三度、小三度、大七度、小七度等。'
                '听辨时先抓根音与最高声部，再补中间层；流行歌里三度与五度出现频率极高。',
          ),
          _Section(
            title: '大调与小调色彩',
            body:
                '大三和弦明亮，小三和弦暗淡；属七和弦有「要解决」的张力。'
                '练耳时把「色彩」和和弦功能（主、下属、属）联系起来，比死记符号更有效。',
          ),
          _Section(
            title: '节拍与分层聆听',
            body:
                '扒歌不只听和弦，还要注意底鼓/军鼓型态与贝斯走向。'
                '建议先分段循环，低速听低音与根音运动，再确认上层和声。',
          ),
          const SizedBox(height: 16),
          Text(
            '更系统的练耳题库与错题复习见需求文档「练耳训练一期」。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(body, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
