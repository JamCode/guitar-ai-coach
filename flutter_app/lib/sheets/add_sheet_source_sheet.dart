import 'package:flutter/material.dart';

/// 用户选择谱子图片来源：系统相机连拍页或相册多选。
enum SheetImageSource { camera, gallery }

/// 底部弹层：拍照 / 从相册选择 / 取消。取消时返回 `null`。
Future<SheetImageSource?> showSheetImageSourceSheet(BuildContext context) {
  return showModalBottomSheet<SheetImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, SheetImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, SheetImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    ),
  );
}
