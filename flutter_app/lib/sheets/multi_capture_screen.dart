import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// 连续拍摄多张照片；点「完成」时通过 [Navigator.pop] 返回 [XFile] 列表（可为空表示放弃本页）。
class MultiCaptureScreen extends StatefulWidget {
  const MultiCaptureScreen({super.key});

  @override
  State<MultiCaptureScreen> createState() => _MultiCaptureScreenState();
}

class _MultiCaptureScreenState extends State<MultiCaptureScreen> {
  CameraController? _controller;
  final List<XFile> _shots = [];
  bool _initializing = true;
  bool _capturing = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _initError = '未检测到相机，请改用相册。';
        });
        return;
      }
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _controller = ctrl;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _initError = '相机不可用：$e';
      });
    }
  }

  Future<void> _onShutter() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await c.takePicture();
      if (!mounted) return;
      setState(() => _shots.add(file));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拍照失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _removeAt(int i) {
    setState(() => _shots.removeAt(i));
  }

  Future<void> _onCancel() async {
    if (_shots.isEmpty) {
      if (mounted) Navigator.pop(context, <XFile>[]);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃已拍照片？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续拍摄')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('放弃')),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.pop(context, <XFile>[]);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('拍照（可多张）'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _onCancel,
        ),
        actions: [
          TextButton(
            onPressed: _shots.isEmpty ? null : () => Navigator.pop(context, List<XFile>.from(_shots)),
            child: const Text('完成'),
          ),
        ],
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _initError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_initError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, <XFile>[]),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: _controller != null && _controller!.value.isInitialized
                            ? AspectRatio(
                                aspectRatio: _controller!.value.aspectRatio,
                                child: CameraPreview(_controller!),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    Container(
                      color: Colors.black,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_shots.isNotEmpty)
                            SizedBox(
                              height: 72,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _shots.length,
                                separatorBuilder: (context, index) => const SizedBox(width: 8),
                                itemBuilder: (ctx, i) {
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.file(
                                          File(_shots[i].path),
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            width: 64,
                                            height: 64,
                                            color: Colors.grey.shade800,
                                            child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: -6,
                                        right: -6,
                                        child: Material(
                                          color: colorScheme.error,
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: () => _removeAt(i),
                                            child: Padding(
                                              padding: const EdgeInsets.all(2),
                                              child: Icon(Icons.close, size: 16, color: colorScheme.onError),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                '按快门可连续拍摄多页',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Center(
                            child: Material(
                              color: Colors.white,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _capturing ? null : _onShutter,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey.shade400, width: 3),
                                    ),
                                    child: _capturing
                                        ? const Padding(
                                            padding: EdgeInsets.all(20),
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
