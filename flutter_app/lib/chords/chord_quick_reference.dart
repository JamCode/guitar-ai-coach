import 'package:flutter/material.dart';

import 'chord_result_bottom_sheet.dart';
import 'offline_chord_builder.dart';

/// 用当前和弦符号弹出底部指法层（离线构成音 + 指法图 + 试听）。
///
/// 解析失败时提示用户改去和弦字典；不抛异常。
Future<void> showChordQuickReferenceSheet(
  BuildContext context,
  String chordSymbol,
) async {
  final sym = chordSymbol.trim();
  if (sym.isEmpty) return;
  final payload = buildOfflineChordPayload(displaySymbol: sym);
  if (!context.mounted) return;
  if (payload == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('暂无法解析「$sym」的离线指法，请到「工具」打开和弦字典。'),
      ),
    );
    return;
  }
  final disc = payload.disclaimer.trim();
  await showChordResultBottomSheet(
    context: context,
    payload: payload,
    disclaimer: disc.isNotEmpty ? disc : null,
  );
}
