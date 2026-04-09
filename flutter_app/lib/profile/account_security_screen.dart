import 'package:flutter/material.dart';

/// 账号与安全页：一期先提供结构化入口，后续可接入真实账号能力。
class AccountSecurityScreen extends StatelessWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账号与安全')),
      body: ListView(
        children: const [
          ListTile(
            title: Text('手机号'),
            subtitle: Text('未绑定'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
          Divider(height: 1),
          ListTile(
            title: Text('邮箱'),
            subtitle: Text('未绑定'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
          Divider(height: 1),
          ListTile(
            title: Text('登录设备管理'),
            subtitle: Text('查看最近登录记录'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
          Divider(height: 1),
          ListTile(
            title: Text('隐私设置'),
            subtitle: Text('控制数据展示与授权'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
