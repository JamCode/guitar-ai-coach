import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_version_info.dart';

/// 「关于与版本」页：展示当前版本、发布渠道与平台，并支持复制信息。
class AppVersionScreen extends StatefulWidget {
  const AppVersionScreen({super.key});

  @override
  State<AppVersionScreen> createState() => _AppVersionScreenState();
}

class _AppVersionScreenState extends State<AppVersionScreen> {
  AppVersionInfo? _info;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  /// 加载版本信息，失败时保持降级文案，不阻塞页面可用性。
  Future<void> _loadInfo() async {
    final info = await AppVersionInfoLoader.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  /// 复制版本摘要，便于用户反馈问题时直接粘贴。
  Future<void> _copyVersionSummary() async {
    final info = _info;
    if (info == null) {
      return;
    }
    final message =
        'AI吉他 ${info.displayVersion} / ${info.releaseChannel} / ${info.platformLabel}';
    await Clipboard.setData(ClipboardData(text: message));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('版本信息已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('关于与版本')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('应用版本'),
                        trailing: Text(info?.displayVersion ?? '--'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('发布渠道'),
                        trailing: Text(info?.releaseChannel ?? '--'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('系统平台'),
                        trailing: Text(info?.platformLabel ?? '--'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _copyVersionSummary,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('复制版本信息'),
                ),
              ],
            ),
    );
  }
}
