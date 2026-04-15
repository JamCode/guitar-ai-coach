import 'package:flutter/material.dart';

import 'app_version_info.dart';
import 'app_version_screen.dart';
import 'help_feedback_screen.dart';

/// 「我的」页面：承载个人资料与设置入口。
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  var _versionText = '--';

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
  }

  /// 读取版本号摘要，在「我的」页入口直出当前构建版本。
  Future<void> _loadVersionInfo() async {
    final info = await AppVersionInfoLoader.load();
    if (!mounted) {
      return;
    }
    setState(() => _versionText = info.displayVersion);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.help_outline),
                title: Text('帮助与反馈'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const HelpFeedbackScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于与版本'),
                subtitle: Text(_versionText),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const AppVersionScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
            ],
          ),
        ),
      ],
    );
  }
}
