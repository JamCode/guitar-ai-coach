import 'package:guitar_helper/chords/chord_models.dart';
import 'package:guitar_helper/chords/chord_remote_repository.dart';

/// 测试用 [ChordRemoteRepository]，可注入固定结果或错误。
class FakeChordRepository implements ChordRemoteRepository {
  FakeChordRepository({
    this.transposeResult,
    this.payload,
    this.exception,
  });

  final String? transposeResult;
  final ChordExplainMultiPayload? payload;
  final ChordApiException? exception;

  @override
  Future<String?> transposeChord({
    required String symbol,
    required String fromKey,
    required String toKey,
  }) async =>
      transposeResult;

  @override
  Future<ChordExplainMultiPayload> explainMulti({
    required String symbol,
    required String key,
    required String level,
    bool forceRefresh = false,
  }) async {
    if (exception != null) throw exception!;
    final p = payload;
    if (p == null) {
      throw ChordApiException('FakeChordRepository: no payload');
    }
    return p;
  }
}
