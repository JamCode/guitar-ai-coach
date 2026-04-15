import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'add_sheet_source_sheet.dart';
import 'multi_capture_screen.dart';
import 'sheet_library_store.dart';

/// 选图完成后：展示缩略图、可继续添加、输入谱名并保存。
class SheetDraftScreen extends StatefulWidget {
  const SheetDraftScreen({
    super.key,
    required this.initialImages,
    required this.localStore,
  });

  /// 进入本页前已选好的图片（相册多选或连拍结果）。
  final List<XFile> initialImages;

  /// 本地持久化存储。
  final SheetLibraryStore localStore;

  @override
  State<SheetDraftScreen> createState() => _SheetDraftScreenState();
}

class _SheetDraftScreenState extends State<SheetDraftScreen> {
  static const _maxPages = 30;

  late List<XFile> _files;
  final _nameController = TextEditingController();
  final _picker = ImagePicker();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _files = List<XFile>.from(widget.initialImages);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _appendFromSource(SheetImageSource source) async {
    if (!mounted) return;
    if (source == SheetImageSource.gallery) {
      final picked = await _picker.pickMultiImage(imageQuality: 85);
      if (!mounted) return;
      if (picked.isEmpty) return;
      final room = _maxPages - _files.length;
      if (room <= 0) {
        _toast('最多 $_maxPages 张');
        return;
      }
      setState(() => _files.addAll(picked.take(room)));
      if (picked.length > room) _toast('已添加 $room 张（达到上限）');
      return;
    }

    final room = _maxPages - _files.length;
    if (room <= 0) {
      _toast('最多 $_maxPages 张');
      return;
    }

    final batch = await Navigator.push<List<XFile>>(
      context,
      MaterialPageRoute<List<XFile>>(
        fullscreenDialog: true,
        builder: (_) => const MultiCaptureScreen(),
      ),
    );
    if (!mounted) return;
    if (batch == null || batch.isEmpty) return;
    setState(() => _files.addAll(batch.take(room)));
    if (batch.length > room) _toast('已添加 $room 张（达到上限）');
  }

  Future<void> _onAddPressed() async {
    final source = await showSheetImageSourceSheet(context);
    if (!mounted || source == null) return;
    await _appendFromSource(source);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onCancel() async {
    if (_files.isEmpty && _nameController.text.trim().isEmpty) {
      if (mounted) Navigator.pop(context, false);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃本次添加？'),
        content: const Text('已选图片与名称将不会保存。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续编辑')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('放弃')),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.pop(context, false);
    }
  }

  Future<void> _onSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('请填写谱子名称');
      return;
    }
    if (_files.isEmpty) {
      _toast('请至少保留一张图片');
      return;
    }
    setState(() => _saving = true);
    try {
      for (final x in _files) {
        if (!await File(x.path).exists()) {
          throw StateError('临时文件已失效，请重新选择');
        }
      }
      final sources = _files.map((x) => File(x.path)).toList();
      await widget.localStore.importSheetPages(sources: sources, displayName: name);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建谱子'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : _onCancel,
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _onSave,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('已选 ${_files.length} 张', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _files.length + 1,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                if (i == _files.length) {
                  return InkWell(
                    onTap: _files.length >= _maxPages ? null : _onAddPressed,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 88,
                      height: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: _files.length >= _maxPages ? theme.disabledColor : theme.colorScheme.primary,
                      ),
                    ),
                  );
                }
                final x = _files[i];
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(x.path),
                        width: 88,
                        height: 96,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 88,
                          height: 96,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Material(
                        color: theme.colorScheme.error,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => _files.removeAt(i)),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.close, size: 16, color: theme.colorScheme.onError),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('谱子名称', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '给谱子起个名字',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _onSave(),
          ),
        ],
      ),
    );
  }
}
