import 'package:flutter/material.dart';

import 'api_base_url_store.dart';

/// 配置后端 API 基址（如 `https://your-host/api`），写入 [SharedPreferences]。
class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  final _controller = TextEditingController();
  final _store = ApiBaseUrlStore();
  var _loading = true;
  String? _savedHint;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _store.load();
    if (!mounted) return;
    setState(() {
      _controller.text = v;
      _loading = false;
      _savedHint = ApiBaseUrlStore.kCompileTimeDefault.isNotEmpty
          ? '编译期默认：${ApiBaseUrlStore.kCompileTimeDefault}'
          : null;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _store.save(_controller.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('API 设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '填写与 Web 前端 `VITE_API_BASE_URL` 相同的基址，通常以 `/api` 结尾，无末尾斜杠。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (_savedHint != null)
                  Text(
                    _savedHint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: 'API 基址',
                    hintText: 'https://example.com/api',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
    );
  }
}
