import 'package:flutter/material.dart';

/// 本地数据与隐私页：说明离线模式下的数据存储方式。
class AccountSecurityScreen extends StatelessWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私与本地数据')),
      body: ListView(
        children: const [
          ListTile(
            title: Text('当前模式'),
            subtitle: Text('离线模式（无需登录，无网络依赖）'),
          ),
          Divider(height: 1),
          ListTile(
            title: Text('数据存储位置'),
            subtitle: Text('练习记录和曲谱仅保存在本机应用沙箱内'),
          ),
          Divider(height: 1),
          ListTile(
            title: Text('云同步'),
            subtitle: Text('当前版本未启用云端同步与账号恢复'),
          ),
        ],
      ),
    );
  }
}
