import 'package:flutter/material.dart';

/// [showPracticeFinishDialog] 的返回结果，用于写入 [PracticeSession]。
class PracticeFinishResult {
  const PracticeFinishResult({
    required this.completed,
    required this.difficulty,
    required this.note,
  });

  final bool completed;
  final int difficulty;
  final String? note;
}

/// 练习结束时的主观反馈弹窗（与任务类型无关，由调用方决定标题与是否显示「完成目标」）。
Future<PracticeFinishResult?> showPracticeFinishDialog({
  required BuildContext context,
  required TextEditingController noteController,
  String title = '本次练习完成',
  bool showCompletedGoal = true,
}) {
  return showDialog<PracticeFinishResult>(
    context: context,
    builder: (_) => _PracticeFinishDialog(
      noteController: noteController,
      title: title,
      showCompletedGoal: showCompletedGoal,
    ),
  );
}

class _PracticeFinishDialog extends StatefulWidget {
  const _PracticeFinishDialog({
    required this.noteController,
    required this.title,
    required this.showCompletedGoal,
  });

  final TextEditingController noteController;
  final String title;
  final bool showCompletedGoal;

  @override
  State<_PracticeFinishDialog> createState() => _PracticeFinishDialogState();
}

class _PracticeFinishDialogState extends State<_PracticeFinishDialog> {
  var _completed = true;
  var _difficulty = 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showCompletedGoal)
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
              PracticeFinishResult(
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
