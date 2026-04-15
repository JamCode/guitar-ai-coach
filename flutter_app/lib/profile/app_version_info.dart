import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 应用版本信息，用于「我的」页和「关于与版本」页展示。
class AppVersionInfo {
  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseChannel,
    required this.platformLabel,
  });

  final String version;
  final String buildNumber;
  final String releaseChannel;
  final String platformLabel;

  /// 统一展示文案：v1.0.0 (4)
  String get displayVersion => 'v$version ($buildNumber)';
}

/// 负责读取应用版本信息与 iOS 分发渠道。
class AppVersionInfoLoader {
  static const MethodChannel _channel = MethodChannel(
    'guitar_helper/build_info',
  );

  /// 从平台读取版本信息，读取失败时降级为可展示的默认文案，避免页面崩溃。
  static Future<AppVersionInfo> load() async {
    var version = '0.0.0';
    var buildNumber = '0';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      version = packageInfo.version;
      buildNumber = packageInfo.buildNumber;
    } catch (_) {
      // 降级默认值，保证「我的」页在插件异常时仍可打开。
    }

    return AppVersionInfo(
      version: version,
      buildNumber: buildNumber,
      releaseChannel: await _resolveReleaseChannel(),
      platformLabel: _platformLabel(),
    );
  }

  static Future<String> _resolveReleaseChannel() async {
    if (kDebugMode) {
      return 'Debug';
    }
    if (kProfileMode) {
      return 'Profile';
    }
    if (!Platform.isIOS) {
      return 'Release';
    }
    try {
      final channel = await _channel.invokeMethod<String>(
        'getDistributionChannel',
      );
      if (channel != null && channel.isNotEmpty) {
        return channel;
      }
    } catch (_) {
      // 插件未注册或调用异常时回落到 Release。
    }
    return 'Release';
  }

  static String _platformLabel() {
    if (Platform.isIOS) {
      return 'iOS';
    }
    if (Platform.isAndroid) {
      return 'Android';
    }
    return Platform.operatingSystem;
  }
}
