import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'crash_log_store.dart';

/// 展示诊断日志路径，并支持分享、复制与清空。
class DiagnosticLogsScreen extends StatefulWidget {
  const DiagnosticLogsScreen({super.key});

  @override
  State<DiagnosticLogsScreen> createState() => _DiagnosticLogsScreenState();
}

class _DiagnosticLogsScreenState extends State<DiagnosticLogsScreen> {
  var _loading = true;
  String? _path;
  int _bytes = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final path = CrashLogStore.instance.logFilePath;
    final n = await CrashLogStore.instance.logByteLength();
    if (!mounted) return;
    setState(() {
      _path = path;
      _bytes = n;
      _loading = false;
    });
  }

  Future<void> _share() async {
    final path = _path;
    if (path == null) {
      _toast('当前环境未生成日志文件');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(path)],
        subject: 'AI吉他 诊断日志',
      ),
    );
  }

  Future<void> _copyPath() async {
    final path = _path;
    if (path == null || path.isEmpty) {
      _toast('无可用路径');
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    _toast('路径已复制');
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空诊断日志？'),
        content: const Text('将删除本机已记录的错误文本（不可恢复）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await CrashLogStore.instance.clearLogFiles();
    await _reload();
    if (!mounted) return;
    _toast('已清空');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('诊断日志')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '说明',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  kIsWeb
                      ? 'Web 版不向磁盘写入诊断文件；调试时请打开浏览器开发者工具控制台。'
                      : 'Dart 层未捕获的异常会追加写入下方路径。进程被系统强杀、'
                          '原生插件崩溃等不会写入此文件，需用电脑连接手机查看 '
                          'Xcode 设备日志或 Android logcat。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '日志文件',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _path ?? '（未初始化或当前平台不支持）',
                  style: theme.textTheme.bodySmall,
                ),
                if (!kIsWeb && _path != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '约 ${_bytes > 0 ? (_bytes / 1024).toStringAsFixed(1) : '0'} KB',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: kIsWeb ? null : _share,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('分享日志文件'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _path == null ? null : _copyPath,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制路径'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: kIsWeb || _path == null ? null : _clear,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('清空日志'),
                ),
              ],
            ),
    );
  }
}
