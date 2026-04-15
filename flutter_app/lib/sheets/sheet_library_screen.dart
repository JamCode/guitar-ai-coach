import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../chords/chord_transpose_local.dart';
import '../practice/practice_local_store.dart';
import '../practice/practice_models.dart';
import 'add_sheet_source_sheet.dart';
import 'multi_capture_screen.dart';
import 'sheet_draft_screen.dart';
import 'sheet_entry.dart';
import 'sheet_library_store.dart';
import 'sheet_ocr_review_screen.dart';
import 'sheet_ocr_service.dart';
import 'sheet_parsed_models.dart';

/// 「我的谱」列表：离线本地库（元数据与图片均保存在应用沙箱）。
class SheetLibraryScreen extends StatefulWidget {
  const SheetLibraryScreen({super.key});

  @override
  State<SheetLibraryScreen> createState() => SheetLibraryScreenState();
}

class SheetLibraryScreenState extends State<SheetLibraryScreen> {
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
      final list = await _localStore.loadAll();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '读取本地曲谱失败：$e';
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
        builder: (_) =>
            SheetDraftScreen(initialImages: batch, localStore: _localStore),
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
      builder: (ctx) => _SheetDetailDialog(entry: e, localStore: _localStore),
    );
    final endedAt = DateTime.now();
    final durationSeconds = endedAt.difference(startedAt).inSeconds;
    if (durationSeconds < _minPracticeSeconds) return;
    try {
      await _practiceStore.saveSession(
        task: _sheetPracticeTask,
        startedAt: startedAt,
        endedAt: endedAt,
        durationSeconds: durationSeconds,
        completed: true,
        difficulty: 3,
        note: '曲谱：${e.displayName}',
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('写入练习记录失败：$err')));
    }
  }

  Future<void> _onDelete(SheetEntry e) async {
    try {
      await _localStore.remove(e.id);
      if (!mounted) return;
      await _reload();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$err')));
    }
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
            '暂无谱子。点击右下角 +：拍照或相册多选；起名后保存到本地。',
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
                leading: _SheetEntryThumb(entry: e, localStore: _localStore),
                title: Text(e.displayName),
                subtitle: Text(
                  '${e.pageCount} 张 · $dateStr · ${_parseStatusLabel(e.parseStatus)}',
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
      ),
    );
  }

  String _parseStatusLabel(String status) {
    switch (status) {
      case 'ready':
        return '可变调';
      case 'draft':
        return '待校对';
      default:
        return '未解析';
    }
  }
}

/// 列表封面：显示本地首张文件。
class _SheetEntryThumb extends StatefulWidget {
  const _SheetEntryThumb({required this.entry, required this.localStore});

  final SheetEntry entry;
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

class _LocalSheetPreview extends StatefulWidget {
  const _LocalSheetPreview({required this.entry, required this.localStore});

  final SheetEntry entry;
  final SheetLibraryStore localStore;

  @override
  State<_LocalSheetPreview> createState() => _LocalSheetPreviewState();
}

class _LocalSheetPreviewState extends State<_LocalSheetPreview> {
  List<File> _files = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final files = await widget.localStore.resolveStoredFiles(widget.entry);
      if (!mounted) return;
      setState(() => _files = files);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('加载失败：$_error'));
    }
    if (_files.isEmpty) {
      return const Center(child: Text('未找到谱面图片'));
    }
    return PageView.builder(
      itemCount: _files.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(_files[i], fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// 谱子详情弹窗：支持按需 OCR、校对保存与和弦变调预览。
class _SheetDetailDialog extends StatefulWidget {
  const _SheetDetailDialog({required this.entry, required this.localStore});

  final SheetEntry entry;
  final SheetLibraryStore localStore;

  @override
  State<_SheetDetailDialog> createState() => _SheetDetailDialogState();
}

class _SheetDetailDialogState extends State<_SheetDetailDialog> {
  List<File> _files = const [];
  SheetParsedData? _parsed;
  bool _loading = true;
  bool _ocring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final files = await widget.localStore.resolveStoredFiles(widget.entry);
      final parsed = await widget.localStore.loadParsed(widget.entry.id);
      if (!mounted) return;
      setState(() {
        _files = files;
        _parsed = parsed;
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

  Future<void> _onRunOcrAndReview() async {
    if (_files.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未找到可识别的图片页')));
      return;
    }
    setState(() => _ocring = true);
    final service = SheetOcrService();
    try {
      final segments = await service.recognizeSheetSegments(_files);
      if (!mounted) return;
      if (segments.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未识别到可用内容，请尝试更清晰的谱面')));
        return;
      }
      final reviewed = await Navigator.push<SheetParsedData>(
        context,
        MaterialPageRoute<SheetParsedData>(
          fullscreenDialog: true,
          builder: (_) => SheetOcrReviewScreen(
            sheetId: widget.entry.id,
            initialSegments: segments,
          ),
        ),
      );
      if (!mounted || reviewed == null) return;
      await widget.localStore.saveParsed(reviewed);
      if (!mounted) return;
      setState(() => _parsed = reviewed);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存结构化内容，后续可直接变调')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('识别失败：$e')));
    } finally {
      await service.close();
      if (mounted) setState(() => _ocring = false);
    }
  }

  Future<void> _onTransposePreview() async {
    final parsed = _parsed;
    if (parsed == null) return;
    var toKey = parsed.originalKey;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          final lines = parsed.segments
              .map(
                (s) => s.chords
                    .map(
                      (c) => ChordTransposeLocal.transposeChordSymbol(
                        c,
                        parsed.originalKey,
                        toKey,
                      ),
                    )
                    .join(' '),
              )
              .where((x) => x.isNotEmpty)
              .toList();
          return AlertDialog(
            title: const Text('一键变调预览'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '目标调',
                      border: OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: toKey,
                        isExpanded: true,
                        items:
                            const [
                                  'C',
                                  'Db',
                                  'D',
                                  'Eb',
                                  'E',
                                  'F',
                                  'Gb',
                                  'G',
                                  'Ab',
                                  'A',
                                  'Bb',
                                  'B',
                                ]
                                .map(
                                  (k) => DropdownMenuItem<String>(
                                    value: k,
                                    child: Text(k),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setLocalState(() => toKey = value);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        lines.isEmpty ? '暂无和弦数据' : lines.take(6).join('\n'),
                        style: Theme.of(ctx).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.entry.displayName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '共 ${widget.entry.pageCount} 页 · ${_parsed == null ? '未解析' : '可变调'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text('加载失败：$_error'),
                    )
                  else
                    Expanded(
                      child: _files.isEmpty
                          ? const Center(child: Text('未找到谱面图片'))
                          : PageView.builder(
                              itemCount: _files.length,
                              itemBuilder: (context, i) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    _files[i],
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  if (_parsed != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '已解析 ${_parsed!.segments.length} 段 · 原调 ${_parsed!.originalKey}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _ocring
                                ? null
                                : (_parsed == null
                                      ? _onRunOcrAndReview
                                      : _onTransposePreview),
                            icon: _ocring
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _parsed == null
                                        ? Icons.text_snippet_outlined
                                        : Icons.music_note_outlined,
                                  ),
                            label: Text(
                              _parsed == null ? '识别并校对（用于变调）' : '一键变调预览',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
