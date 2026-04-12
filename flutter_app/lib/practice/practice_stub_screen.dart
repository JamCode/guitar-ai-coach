import 'package:flutter/material.dart';
import 'dart:async';

import 'chord_practice_selection_screen.dart';
import 'practice_api_repository.dart';
import 'practice_models.dart';
import 'practice_remote_store.dart';
import 'practice_session_store.dart';

/// 练习模块首页：提供任务入口、今日进度与历史记录。
class PracticeStubScreen extends StatefulWidget {
  const PracticeStubScreen({
    super.key,
    this.onOpenMySheets,
    this.sessionStore,
  });

  /// 打开「我的谱」页面，由外层壳统一路由。
  final Future<void> Function()? onOpenMySheets;

  /// 注入练习存储（测试用）；默认使用 [PracticeRemoteStore]（服务端为数据源）。
  final PracticeSessionStore? sessionStore;

  @override
  State<PracticeStubScreen> createState() => _PracticeStubScreenState();
}

class _PracticeStubScreenState extends State<PracticeStubScreen> {
  late final PracticeSessionStore _store =
      widget.sessionStore ?? PracticeRemoteStore();

  var _loading = true;
  String? _loadError;
  PracticeSummary _summary = const PracticeSummary(
    todayMinutes: 0,
    todaySessions: 0,
    streakDays: 0,
  );
  List<PracticeSession> _sessions = <PracticeSession>[];

  static const _dailyGoalMinutes = 20;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  /// 刷新首页统计与历史。
  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final summary = await _store.loadSummary();
      final sessions = await _store.loadSessions();
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = summary;
        _sessions = sessions;
        _loading = false;
      });
    } on PracticeApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = e.message;
        _summary = const PracticeSummary(
          todayMinutes: 0,
          todaySessions: 0,
          streakDays: 0,
        );
        _sessions = <PracticeSession>[];
        _loading = false;
      });
    }
  }

  /// 进入单任务练习页，结束后回流刷新首页数据。
  ///
  /// 和弦切换任务 (`chord-switch`) 跳转到专用选择页。
  Future<void> _openPracticeTask(PracticeTask task) async {
    if (task.id == 'chord-switch') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChordPracticeSelectionScreen(
            task: task,
            store: _store,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _PracticeSessionScreen(task: task, store: _store),
        ),
      );
    }
    if (!mounted) {
      return;
    }
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => unawaited(_refresh()),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final recentSessions = _sessions.take(3).toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '今日目标：$_dailyGoalMinutes 分钟',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('已完成：${_summary.todayMinutes} 分钟'),
                  Text('已练习：${_summary.todaySessions} 次'),
                  Text('连续打卡：${_summary.streakDays} 天'),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (_summary.todayMinutes / _dailyGoalMinutes).clamp(
                      0,
                      1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('今日任务', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...kDefaultPracticeTasks.map((task) {
            return Card(
              child: ListTile(
                title: Text(task.name),
                subtitle: Text(
                  '${task.targetMinutes} 分钟 · ${task.description}',
                ),
                trailing: FilledButton(
                  key: Key('practice_start_${task.id}'),
                  onPressed: () => _openPracticeTask(task),
                  child: const Text('开始'),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: const Text('我的谱'),
              subtitle: const Text('在曲谱中练习并累计时长与次数'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: widget.onOpenMySheets,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('练习历史', style: theme.textTheme.titleMedium),
            trailing: TextButton(
              key: const Key('practice_history_button'),
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => _PracticeHistoryScreen(sessions: _sessions),
                  ),
                );
              },
              child: const Text('查看全部'),
            ),
          ),
          if (recentSessions.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '还没有练习记录，先开始第一次练习吧。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...recentSessions.map(
              (session) => Card(
                child: ListTile(
                  title: Text(session.taskName),
                  subtitle: Text(
                    '${_formatDate(session.endedAt)} · ${_formatDuration(session.durationSeconds)}',
                  ),
                  trailing: Text('难度 ${session.difficulty}/5'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PracticeSessionScreen extends StatefulWidget {
  const _PracticeSessionScreen({required this.task, required this.store});

  final PracticeTask task;
  final PracticeSessionStore store;

  @override
  State<_PracticeSessionScreen> createState() => _PracticeSessionScreenState();
}

class _PracticeSessionScreenState extends State<_PracticeSessionScreen> {
  Timer? _ticker;
  final _noteController = TextEditingController();
  DateTime? _startedAt;
  var _elapsed = Duration.zero;
  var _running = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  void _start() {
    if (_running) {
      return;
    }
    _startedAt ??= DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _elapsed += const Duration(seconds: 1);
      });
    });
    setState(() => _running = true);
  }

  void _pause() {
    _ticker?.cancel();
    setState(() => _running = false);
  }

  Future<void> _finish() async {
    if (_elapsed == Duration.zero) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先开始练习再结束哦')));
      return;
    }
    _pause();
    final result = await showDialog<_FinishResult>(
      context: context,
      builder: (_) => _FinishDialog(noteController: _noteController),
    );
    if (result == null || _startedAt == null) {
      return;
    }
    try {
      await widget.store.saveSession(
        task: widget.task,
        startedAt: _startedAt!,
        endedAt: DateTime.now(),
        durationSeconds: _elapsed.inSeconds,
        completed: result.completed,
        difficulty: result.difficulty,
        note: result.note,
      );
    } on PracticeApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('记录已保存')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('离开练习？'),
            content: const Text('当前练习尚未保存，确定要返回吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('继续练习'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('放弃返回'),
              ),
            ],
          ),
        );
        if (leave == true && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.task.name)),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.task.description),
              const SizedBox(height: 24),
              Text(
                _formatDuration(_elapsed.inSeconds),
                key: const Key('practice_timer'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    key: const Key('practice_timer_start'),
                    onPressed: _start,
                    child: const Text('开始'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    key: const Key('practice_timer_pause'),
                    onPressed: _pause,
                    child: const Text('暂停'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    key: const Key('practice_timer_finish'),
                    onPressed: _finish,
                    child: const Text('结束'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinishDialog extends StatefulWidget {
  const _FinishDialog({required this.noteController});

  final TextEditingController noteController;

  @override
  State<_FinishDialog> createState() => _FinishDialogState();
}

class _FinishDialogState extends State<_FinishDialog> {
  var _completed = true;
  var _difficulty = 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('本次练习完成'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('完成目标'),
              value: _completed,
              onChanged: (v) => setState(() => _completed = v),
            ),
            Row(
              children: [
                const Text('主观难度'),
                Expanded(
                  child: Slider(
                    key: const Key('practice_difficulty_slider'),
                    value: _difficulty.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$_difficulty',
                    onChanged: (v) => setState(() => _difficulty = v.round()),
                  ),
                ),
                Text('$_difficulty'),
              ],
            ),
            TextField(
              key: const Key('practice_note_input'),
              controller: widget.noteController,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('practice_save_session'),
          onPressed: () {
            Navigator.of(context).pop(
              _FinishResult(
                completed: _completed,
                difficulty: _difficulty,
                note: widget.noteController.text.trim().isEmpty
                    ? null
                    : widget.noteController.text.trim(),
              ),
            );
          },
          child: const Text('保存记录'),
        ),
      ],
    );
  }
}

class _PracticeHistoryScreen extends StatelessWidget {
  const _PracticeHistoryScreen({required this.sessions});

  final List<PracticeSession> sessions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('练习历史')),
      body: sessions.isEmpty
          ? const Center(child: Text('暂无历史记录'))
          : ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (_, i) {
                final session = sessions[i];
                return ListTile(
                  title: Text(session.taskName),
                  subtitle: Text(
                    '${_formatDate(session.endedAt)} · ${_formatDuration(session.durationSeconds)}',
                  ),
                  trailing: Text('难度 ${session.difficulty}/5'),
                );
              },
            ),
    );
  }
}

class _FinishResult {
  const _FinishResult({
    required this.completed,
    required this.difficulty,
    required this.note,
  });

  final bool completed;
  final int difficulty;
  final String? note;
}

String _formatDuration(int seconds) {
  final minute = (seconds ~/ 60).toString().padLeft(2, '0');
  final second = (seconds % 60).toString().padLeft(2, '0');
  return '$minute:$second';
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day';
}
