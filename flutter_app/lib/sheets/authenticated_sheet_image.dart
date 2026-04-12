import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'sheets_api_repository.dart';

/// 使用 Bearer 拉取 `/sheets/{id}/pages/{n}` 并显示；失败显示占位。
class AuthenticatedSheetImage extends StatefulWidget {
  const AuthenticatedSheetImage({
    super.key,
    required this.sheetId,
    required this.pageIndex,
    required this.api,
    this.fit = BoxFit.contain,
  });

  final String sheetId;
  final int pageIndex;
  final SheetsApiRepository api;
  final BoxFit fit;

  @override
  State<AuthenticatedSheetImage> createState() => _AuthenticatedSheetImageState();
}

class _AuthenticatedSheetImageState extends State<AuthenticatedSheetImage> {
  Uint8List? _bytes;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedSheetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sheetId != widget.sheetId || oldWidget.pageIndex != widget.pageIndex) {
      _bytes = null;
      _error = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final raw = await widget.api.fetchPageBytes(widget.sheetId, widget.pageIndex);
      if (!mounted) return;
      setState(() {
        _bytes = Uint8List.fromList(raw);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _bytes = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _bytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '图片加载失败\n$_error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.broken_image_outlined,
        color: theme.colorScheme.outline,
      ),
    );
  }
}
