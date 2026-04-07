import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'sheet_entry.dart';
import 'sheet_library_store.dart';

/// 本地谱子列表：从系统文件选择器导入副本，支持删除；预览为占位。
class SheetLibraryScreen extends StatefulWidget {
  const SheetLibraryScreen({super.key});

  @override
  State<SheetLibraryScreen> createState() => SheetLibraryScreenState();
}

class SheetLibraryScreenState extends State<SheetLibraryScreen> {
  final _store = SheetLibraryStore();
  var _loading = true;
  List<SheetEntry> _entries = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _store.loadAll();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 由 [HomeShell] 上 FAB 调用。
  Future<void> pickAndAddSheet() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'png',
          'jpg',
          'jpeg',
          'webp',
          'txt',
          'gp',
          'gpx',
        ],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final plat = result.files.single;
      final path = plat.path;
      if (path == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法读取该文件路径')),
        );
        return;
      }
      final source = File(path);
      if (!await source.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不存在')),
        );
        return;
      }
      final ext = p.extension(plat.name).toLowerCase();
      final id = const Uuid().v4();
      final storedName = '$id$ext';
      final displayName = plat.name;
      await _store.importFile(
        source: source,
        displayName: displayName,
        id: id,
        storedFileName: storedName,
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加：$displayName')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  Future<void> _onOpen(SheetEntry e) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.displayName),
        content: const Text('谱面预览开发中。文件已保存在本应用目录，可在后续版本查看。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _onDelete(SheetEntry e) async {
    await _store.remove(e.id);
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '暂无谱子。点击右下角 + 从本机选择 PDF / 图片 等文件；'
            ' 会复制到应用沙箱，避免系统授权过期导致打不开。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: _entries.length,
      itemBuilder: (context, i) {
        final e = _entries[i];
        final date = DateTime.fromMillisecondsSinceEpoch(e.addedAtMs);
        return Dismissible(
          key: ValueKey(e.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Theme.of(context).colorScheme.error,
            child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onError),
          ),
          onDismissed: (_) => _onDelete(e),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(e.displayName),
              subtitle: Text(
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
              ),
              onTap: () => _onOpen(e),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _onDelete(e),
                tooltip: '删除',
              ),
            ),
          ),
        );
      },
    );
  }
}
