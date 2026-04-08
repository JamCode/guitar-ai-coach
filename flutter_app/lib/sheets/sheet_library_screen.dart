import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'add_sheet_source_sheet.dart';
import 'multi_capture_screen.dart';
import 'sheet_draft_screen.dart';
import 'sheet_entry.dart';
import 'sheet_library_store.dart';

/// 本地谱子列表：相册多选或连拍导入，一谱多页；支持删除；详情预览为占位。
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

  /// 由 [HomeShell] 上 FAB 调用：先选拍照/相册，再进入取名与保存。
  Future<void> pickAndAddSheet() async {
    if (!mounted) return;
    final source = await showSheetImageSourceSheet(context);
    if (!mounted || source == null) return;

    List<XFile> batch = [];
    if (source == SheetImageSource.gallery) {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
      if (!mounted) return;
      if (picked.isEmpty) return;
      batch = picked;
    } else {
      batch = await Navigator.push<List<XFile>>(
            context,
            MaterialPageRoute<List<XFile>>(
              fullscreenDialog: true,
              builder: (_) => const MultiCaptureScreen(),
            ),
          ) ??
          [];
      if (!mounted) return;
      if (batch.isEmpty) return;
    }

    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => SheetDraftScreen(
          initialImages: batch,
          store: _store,
        ),
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到「我的谱」')),
      );
    }
  }

  Future<void> _onOpen(SheetEntry e) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.displayName),
        content: Text('共 ${e.pageCount} 页。谱面预览开发中；文件已保存在本应用目录。'),
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
            '暂无谱子。点击右下角 +：可选择拍照（连拍多页）或从相册一次选多张；'
            '再为谱子起名后保存。文件会复制到应用沙箱。',
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
        final dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
              leading: _SheetEntryThumb(entry: e, store: _store),
              title: Text(e.displayName),
              subtitle: Text('${e.pageCount} 张 · $dateStr'),
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

/// 列表封面：首张仍存在的页图，否则占位图标。
class _SheetEntryThumb extends StatefulWidget {
  const _SheetEntryThumb({required this.entry, required this.store});

  final SheetEntry entry;
  final SheetLibraryStore store;

  @override
  State<_SheetEntryThumb> createState() => _SheetEntryThumbState();
}

class _SheetEntryThumbState extends State<_SheetEntryThumb> {
  File? _file;
  var _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SheetEntryThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _file = null;
      _done = false;
      _load();
    }
  }

  Future<void> _load() async {
    final f = await widget.store.resolveFirstStoredFile(widget.entry);
    if (!mounted) return;
    setState(() {
      _file = f;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const size = 56.0;
    if (!_done) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.outline),
          ),
        ),
      );
    }
    if (_file == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.insert_photo_outlined, color: theme.colorScheme.outline),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        _file!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.insert_photo_outlined, color: theme.colorScheme.outline),
      ),
    );
  }
}
