import 'package:flutter/material.dart';

/// 帮助与反馈页：集中常见问题和反馈入口。
class HelpFeedbackScreen extends StatelessWidget {
  const HelpFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('帮助与反馈')),
      body: ListView(
        children: const [
          ListTile(
            title: Text('常见问题'),
            subtitle: Text('调音器、练习记录、我的谱相关问题'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
          Divider(height: 1),
          ListTile(
            title: Text('问题反馈'),
            subtitle: Text('描述你的问题与复现步骤'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
          Divider(height: 1),
          ListTile(
            title: Text('功能建议'),
            subtitle: Text('告诉我们你希望新增的功能'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
          Divider(height: 1),
          ListTile(
            title: Text('关于我们'),
            subtitle: Text('版本信息与开源说明'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
