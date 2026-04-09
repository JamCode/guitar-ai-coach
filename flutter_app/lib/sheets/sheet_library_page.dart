import 'package:flutter/material.dart';

import 'sheet_library_screen.dart';

/// 「我的谱」独立页面：用于从练习模块二级进入。
class SheetLibraryPage extends StatefulWidget {
  const SheetLibraryPage({super.key});

  @override
  State<SheetLibraryPage> createState() => _SheetLibraryPageState();
}

class _SheetLibraryPageState extends State<SheetLibraryPage> {
  final _sheetLibraryKey = GlobalKey<SheetLibraryScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的谱')),
      body: SheetLibraryScreen(key: _sheetLibraryKey),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _sheetLibraryKey.currentState?.pickAndAddSheet(),
        tooltip: '添加谱子',
        child: const Icon(Icons.add),
      ),
    );
  }
}
