import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../practice/practice_local_store.dart';
import '../practice/practice_models.dart';
import 'add_sheet_source_sheet.dart';
import 'authenticated_sheet_image.dart';
import 'multi_capture_screen.dart';
import 'sheet_draft_screen.dart';
import 'sheet_entry.dart';
import 'sheet_library_store.dart';
import 'sheets_api_repository.dart';

/// 「我的谱」列表：已登录时走云端 API（须在线）；元数据与图片均在服务端。
class SheetLibraryScreen extends StatefulWidget {
  const SheetLibraryScreen({super.key});

  @override
  State<SheetLibraryScreen> createState() => SheetLibraryScreenState();
}

class SheetLibraryScreenState extends State<SheetLibraryScreen> {
  final _api = SheetsApiRepository();
  final _localStore = SheetLibraryStore();
  final _practiceStore = PracticeLocalStore();
  var _loading = true;
  List<SheetEntry> _entries = [];
  String? _error;
  static const _sheetPracticeTask = PracticeTask(
    id: 'sheet-practice',
    name: '谱面跟练',
    targetMinutes: 10,
    description: '在我的谱中跟弹与复盘。',
  );
  static const _minPracticeSeconds = 30;

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
      final list = await _api.listSheets();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } on SheetsApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
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

  /// 由 [SheetLibraryPage] 上 FAB 调用：先选拍照/相册，再进入取名与保存。
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
      batch =
          await Navigator.push<List<XFile>>(
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
        builder: (_) => SheetDraftScreen(initialImages: batch, remoteApi: _api),
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存到「我的谱」')));
    }
  }

  Future<void> _onOpen(SheetEntry e) async {
    if (!mounted) return;
    final startedAt = DateTime.now();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.sizeOf(ctx).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.displayName,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Text(
                '共 ${e.pageCount} 页 · 需联网查看',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: PageView.builder(
                  itemCount: e.pageCount,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AuthenticatedSheetImage(
                        sheetId: e.id,
                        pageIndex: i,
                        api: _api,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final endedAt = DateTime.now();
    final durationSeconds = endedAt.difference(startedAt).inSeconds;
    if (durationSeconds >= _minPracticeSeconds) {
      await _practiceStore.saveSession(
        task: _sheetPracticeTask,
        startedAt: startedAt,
        endedAt: endedAt,
        durationSeconds: durationSeconds,
        completed: true,
        difficulty: 3,
        note: '曲谱：${e.displayName}',
      );
    }
  }

  Future<void> _onDelete(SheetEntry e) async {
    try {
      await _api.deleteSheet(e.id);
    } on SheetsApiException catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
      return;
    }
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _reload, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '暂无谱子。点击右下角 +：拍照或相册多选；起名后保存到云端（需联网与已登录）。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
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
              child: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.onError,
              ),
            ),
            onDismissed: (_) => _onDelete(e),
            child: Card(
              child: ListTile(
                leading: _SheetEntryThumb(entry: e, api: _api, localStore: _localStore),
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
      ),
    );
  }
}

/// 列表封面：云端首图（Bearer）或本地首张文件。
class _SheetEntryThumb extends StatefulWidget {
  const _SheetEntryThumb({
    required this.entry,
    required this.api,
    required this.localStore,
  });

  final SheetEntry entry;
  final SheetsApiRepository api;
  final SheetLibraryStore localStore;

  @override
  State<_SheetEntryThumb> createState() => _SheetEntryThumbState();
}

class _SheetEntryThumbState extends State<_SheetEntryThumb> {
  File? _file;
  var _done = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadLocal();
  }

  @override
  void didUpdateWidget(covariant _SheetEntryThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _file = null;
      _done = false;
      _maybeLoadLocal();
    }
  }

  Future<void> _maybeLoadLocal() async {
    if (widget.entry.storedFileNames.isNotEmpty) {
      final f = await widget.localStore.resolveFirstStoredFile(widget.entry);
      if (!mounted) return;
      setState(() {
        _file = f;
        _done = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _file = null;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const size = 56.0;
    if (widget.entry.storedFileNames.isEmpty && widget.entry.serverPageCount != null) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AuthenticatedSheetImage(
            sheetId: widget.entry.id,
            pageIndex: 0,
            api: widget.api,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    if (!_done) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }
    if (_file == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Icon(
          Icons.insert_photo_outlined,
          color: theme.colorScheme.outline,
        ),
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
