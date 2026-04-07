import 'chord_models.dart';

/// 远程和弦能力（变调预览、多套按法）。实现类发起 HTTP，测试可注入 fake。
abstract class ChordRemoteRepository {
  /// 将 [symbol] 从 [fromKey] 变调到 [toKey]；失败时返回 `null`，调用方回退显示原符号。
  Future<String?> transposeChord({
    required String symbol,
    required String fromKey,
    required String toKey,
  });

  /// 请求多套按法说明；网络或业务错误时抛出 [ChordApiException]。
  Future<ChordExplainMultiPayload> explainMulti({
    required String symbol,
    required String key,
    required String level,
    bool forceRefresh = false,
  });
}

/// 和弦 API 可展示的错误（含 HTTP 状态与后端 JSON 中的 `detail` / `error`）。
class ChordApiException implements Exception {
  ChordApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ChordApiException($statusCode): $message';
}
