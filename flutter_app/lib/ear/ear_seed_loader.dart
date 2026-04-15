import 'dart:convert';

import 'package:flutter/services.dart';

import 'ear_seed_models.dart';

/// 从 Asset 加载 `ear_seed_v1.json`（内存缓存）。
class EarSeedLoader {
  EarSeedLoader._();

  static final EarSeedLoader instance = EarSeedLoader._();

  static const _assetPath = 'assets/data/ear_seed_v1.json';

  EarSeedDocument? _cached;

  /// 副作用：读 [rootBundle]；成功则缓存。
  Future<EarSeedDocument> load() async {
    if (_cached != null) return _cached!;
    final text = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ear seed root is not an object');
    }
    final doc = EarSeedDocument.tryParseMap(decoded);
    if (doc == null) {
      throw const FormatException('ear seed banks missing or empty');
    }
    _cached = doc;
    return doc;
  }

  /// 仅测试：注入假数据并跳过 Asset。
  void debugSetCache(EarSeedDocument doc) {
    _cached = doc;
  }

  void clearCacheForTest() {
    _cached = null;
  }
}
