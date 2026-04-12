import 'package:flutter/material.dart';

import '../auth/auth_scope.dart';
import 'account_security_screen.dart';
import 'help_feedback_screen.dart';
import 'profile_store.dart';
import '../settings/api_settings_screen.dart';

/// 「我的」页面：承载个人资料与设置入口。
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final _store = ProfileStore();
  var _loading = true;
  UserProfile _profile = const UserProfile(nickname: '');

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _store.loadOrCreate();
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  Future<void> _editNickname() async {
    final next = await showDialog<String>(
      context: context,
      builder: (_) => _NicknameDialog(initialValue: _profile.nickname),
    );
    if (next == null) {
      return;
    }
    final saved = await _store.saveNickname(next);
    if (!mounted) {
      return;
    }
    setState(() => _profile = saved);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('昵称已更新')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(_profile.nickname),
            subtitle: const Text('Lv.6 · 连续练习 12 天'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _editNickname,
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
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('账号与安全'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountSecurityScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
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
                leading: const Icon(Icons.logout),
                title: const Text('退出登录'),
                onTap: () async {
                  await AuthScope.of(context).logout();
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已退出登录')),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置昵称'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '请输入昵称',
          border: OutlineInputBorder(),
        ),
        maxLength: 20,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
