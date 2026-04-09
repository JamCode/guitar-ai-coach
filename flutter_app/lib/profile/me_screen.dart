import 'package:flutter/material.dart';

import '../settings/api_settings_screen.dart';

/// 「我的」页面：承载个人资料与设置入口。
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: const Text('王小吉'),
            subtitle: const Text('Lv.6 · 连续练习 12 天'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {},
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const ApiSettingsScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.verified_user_outlined),
                title: Text('账号与安全'),
                trailing: Icon(Icons.chevron_right_rounded),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.help_outline),
                title: Text('帮助与反馈'),
                trailing: Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
