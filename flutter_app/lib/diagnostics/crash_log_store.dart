import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 全局未捕获异常的本地落盘与 [FlutterError] / 异步错误挂钩。
///
/// - 文件位于应用支持目录下的 `diagnostics/app_diagnostic.log`（随应用卸载删除）。
/// - Web 不落盘，仅在调试模式打印到控制台。
/// - 原生崩溃（SIGSEGV 等）不会经过 Dart，需用 Xcode / `adb logcat` 查看系统日志。
class CrashLogStore {
  CrashLogStore._();
  static final CrashLogStore instance = CrashLogStore._();

  static const _subDirName = 'diagnostics';
  static const _fileName = 'app_diagnostic.log';
  static const _maxBytes = 400 * 1024;

  File? _logFile;
  bool _handlersInstalled = false;

  /// 当前日志文件绝对路径；未初始化成功时为 `null`。
  String? get logFilePath => _logFile?.path;

  /// 创建日志目录与空文件；须在 [installHandlers] 之前 `await`。
  Future<void> ensureInitialized() async {
    if (kIsWeb) return;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, _subDirName));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _logFile = File(p.join(dir.path, _fileName));
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
    } catch (e, st) {
      debugPrint('CrashLogStore.ensureInitialized failed: $e\n$st');
      _logFile = null;
    }
  }

  /// 注册 [FlutterError.onError] 与 [PlatformDispatcher.instance.onError]。
  void installHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      recordFlutterFrameworkError(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      recordError(error, stack, source: 'PlatformDispatcher (async)');
      return true;
    };
  }

  /// Flutter 框架错误（布局、断言、渲染等）。
  void recordFlutterFrameworkError(FlutterErrorDetails details) {
    final buffer = StringBuffer();
    buffer.writeln(details.exceptionAsString());
    if (details.stack != null) {
      buffer.writeln(details.stack);
    }
    if (details.context != null) {
      buffer.writeln('Context: ${details.context}');
    }
    unawaited(
      _writeEntry(header: 'Flutter framework', body: buffer.toString()),
    );
  }

  /// 通用错误文本（Zone、同步 catch 等）。
  void recordError(
    Object error,
    StackTrace? stack, {
    String source = 'unknown',
  }) {
    final buffer = StringBuffer();
    buffer.writeln(error.toString());
    if (stack != null) {
      buffer.writeln(stack);
    }
    unawaited(_writeEntry(header: source, body: buffer.toString()));
  }

  /// 供测试或展示用的单行块格式（UTC 时间戳）。
  static String formatEntry({
    required String header,
    required String body,
    DateTime? at,
  }) {
    final t = (at ?? DateTime.now()).toUtc().toIso8601String();
    return '\n======== $t =========\n[$header]\n${body.trim()}\n';
  }

  Future<void> _writeEntry({
    required String header,
    required String body,
  }) async {
    final entry = formatEntry(header: header, body: body);
    if (_logFile == null) {
      if (kDebugMode) {
        debugPrint(entry);
      }
      return;
    }
    try {
      await _rotateIfNeeded();
      await _logFile!.writeAsString(entry, mode: FileMode.append, flush: true);
    } catch (e, st) {
      debugPrint('CrashLogStore._writeEntry failed: $e\n$st\n$entry');
    }
  }

  Future<void> _rotateIfNeeded() async {
    final f = _logFile;
    if (f == null) return;
    try {
      if (!await f.exists()) return;
      final len = await f.length();
      if (len <= _maxBytes) return;
      final path = f.path;
      final bak = File('$path.bak');
      if (await bak.exists()) await bak.delete();
      await f.rename(bak.path);
      _logFile = File(path);
      await _logFile!.create(recursive: true);
    } catch (e, st) {
      debugPrint('CrashLogStore._rotateIfNeeded failed: $e\n$st');
    }
  }

  /// 删除主日志与轮转备份并重建空文件。
  Future<void> clearLogFiles() async {
    if (_logFile == null) return;
    try {
      final dir = _logFile!.parent;
      for (final name in [_fileName, '$_fileName.bak']) {
        final file = File(p.join(dir.path, name));
        if (await file.exists()) await file.delete();
      }
      _logFile = File(p.join(dir.path, _fileName));
      await _logFile!.create(recursive: true);
    } catch (e, st) {
      debugPrint('CrashLogStore.clearLogFiles failed: $e\n$st');
    }
  }

  /// 主日志文件字节数（不含 `.bak`）。
  Future<int> logByteLength() async {
    if (_logFile == null || !await _logFile!.exists()) return 0;
    return _logFile!.length();
  }
}
