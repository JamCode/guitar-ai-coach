import 'package:flutter/material.dart';

import '../ear/ear_home_screen.dart';
import '../practice/practice_stub_screen.dart';
import '../settings/api_settings_screen.dart';
import '../sheets/sheet_library_screen.dart';
import '../tools/tools_screen.dart';

/// 底部四 Tab 壳：工具 / 练耳 / 练习 / 我的谱。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _index = 0;
  final _sheetLibraryKey = GlobalKey<SheetLibraryScreenState>();

  static const _titles = ['工具', '练耳', '练习', '我的谱'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'API 设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const ApiSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const ToolsScreen(),
          const EarHomeScreen(),
          const PracticeStubScreen(),
          SheetLibraryScreen(key: _sheetLibraryKey),
        ],
      ),
      floatingActionButton: _index == 3
          ? FloatingActionButton(
              onPressed: () =>
                  _sheetLibraryKey.currentState?.pickAndAddSheet(),
              tooltip: '添加谱子',
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: '我的谱',
          ),
        ],
      ),
    );
  }
}
