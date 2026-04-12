import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../settings/api_base_url_store.dart';
import 'auth_api.dart';
import 'auth_session_store.dart';

/// 未登录时的首屏：仅 iOS 提供 Sign in with Apple；配置 API 基址后换发本站 token。
class AppleLoginScreen extends StatefulWidget {
  const AppleLoginScreen({super.key, required this.onLoggedIn});

  /// 登录成功并已持久化 token 后调用。
  final VoidCallback onLoggedIn;

  @override
  State<AppleLoginScreen> createState() => _AppleLoginScreenState();
}

class _AppleLoginScreenState extends State<AppleLoginScreen> {
  final _session = AuthSessionStore();
  final _apiBaseStore = ApiBaseUrlStore();
  final _authApi = AuthApi();
  var _busy = false;
  var _apiBasePreview = '';

  static bool get _appleAvailable =>
      !kIsWeb && !kIsWasm && (Platform.isIOS || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _loadApiPreview();
  }

  Future<void> _loadApiPreview() async {
    final s = await _apiBaseStore.load();
    if (!mounted) {
      return;
    }
    setState(() => _apiBasePreview = s.isEmpty ? '未配置' : s);
  }

  String _randomNonce([int length = 32]) {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _sha256Hex(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  Future<void> _signInWithApple() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final rawNonce = _randomNonce();
      final nonceHash = _sha256Hex(rawNonce);
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [],
        nonce: nonceHash,
      );
      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw AuthApiException('Apple 未返回 identityToken');
      }
      final access = await _authApi.exchangeAppleIdentity(
        identityToken: idToken,
        rawNonce: rawNonce,
      );
      await _session.saveAccessToken(access);
      if (!mounted) {
        return;
      }
      widget.onLoggedIn();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (!mounted) {
        return;
      }
      if (e.code == AuthorizationErrorCode.canceled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消登录')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apple 登录失败：${e.message}')),
        );
      }
    } on AuthApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登录异常：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _editApiBase() async {
    final controller = TextEditingController(text: await _apiBaseStore.load());
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API 服务地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '例如 https://example.com/api',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null) {
      return;
    }
    await _apiBaseStore.save(next);
    await _loadApiPreview();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Text(
              '吉他小助手',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              '使用 Apple 账号登录以继续使用',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: muted),
            ),
            const SizedBox(height: 32),
            Card(
              child: ListTile(
                title: const Text('API 服务地址'),
                subtitle: Text(_apiBasePreview, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _busy ? null : _editApiBase,
              ),
            ),
            const SizedBox(height: 24),
            if (_appleAvailable) ...[
              if (_busy)
                const Center(child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ))
              else
                SignInWithAppleButton(
                  onPressed: _signInWithApple,
                  style: SignInWithAppleButtonStyle.black,
                  height: 48,
                ),
            ] else
              Text(
                'Apple 登录仅支持 iOS / macOS 客户端。请在 iPhone 上安装本应用后登录。',
                style: TextStyle(color: muted),
              ),
            const SizedBox(height: 24),
            Text(
              '登录即表示你同意《用户协议》和《隐私政策》（链接待配置）。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
