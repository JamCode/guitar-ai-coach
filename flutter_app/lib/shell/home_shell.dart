import 'package:flutter/material.dart';

import '../ear/ear_home_screen.dart';
import '../practice/practice_stub_screen.dart';
import '../profile/me_screen.dart';
import '../sheets/sheet_library_page.dart';
import '../tools/tools_screen.dart';

/// 底部四 Tab 壳：工具 / 练耳 / 练习 / 我的。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _index = 0;

  /// 首次进入「练习」Tab 后再挂载子树，避免冷启动即请求练习记录接口。
  var _practiceTabMounted = false;

  static const _titles = ['工具', '练耳', '练习', '我的'];

  Future<void> _openMySheets() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SheetLibraryPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index]), centerTitle: true),
      body: IndexedStack(
        index: _index,
        children: [
          const ToolsScreen(),
          const EarHomeScreen(),
          _practiceTabMounted
              ? PracticeStubScreen(onOpenMySheets: _openMySheets)
              : const SizedBox.expand(),
          const MeScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() {
            _index = i;
            if (i == 2) {
              _practiceTabMounted = true;
            }
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.handyman_outlined),
            selectedIcon: Icon(Icons.handyman),
            label: '工具',
          ),
          NavigationDestination(
            icon: Icon(Icons.hearing_outlined),
            selectedIcon: Icon(Icons.hearing_rounded),
            label: '练耳',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: '练习',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
