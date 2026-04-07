/// 练耳题库中一道四选一 MCQ（模式 A / B）。
class EarMcqOption {
  const EarMcqOption({required this.key, required this.label});

  final String key;
  final String label;
}

/// 从 `ear_seed_v1.json` 解析后的题目。
class EarBankItem {
  const EarBankItem({
    required this.id,
    required this.mode,
    required this.questionType,
    required this.promptZh,
    required this.options,
    required this.correctOptionKey,
    this.root,
    this.targetQuality,
    this.musicKey,
    this.progressionRoman,
    this.hintZh,
  });

  final String id;
  final String mode;
  final String questionType;
  final String promptZh;
  final List<EarMcqOption> options;
  final String correctOptionKey;

  /// 模式 A：`single_chord_quality`
  final String? root;
  final String? targetQuality;

  /// 模式 B：`progression_recognition`
  final String? musicKey;
  final String? progressionRoman;

  final String? hintZh;

  static EarBankItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final mode = raw['mode'];
    final qt = raw['question_type'];
    final prompt = raw['prompt_zh'];
    final correct = raw['correct_option_key'];
    if (id is! String ||
        mode is! String ||
        qt is! String ||
        prompt is! String ||
        correct is! String) {
      return null;
    }
    final optRaw = raw['options'];
    if (optRaw is! List) return null;
    final options = <EarMcqOption>[];
    for (final o in optRaw) {
      if (o is! Map) continue;
      final k = o['key'];
      final lb = o['label'];
      if (k is! String || lb is! String) continue;
      options.add(EarMcqOption(key: k, label: lb));
    }
    if (options.length < 2) return null;

    final root = raw['root'];
    final tq = raw['target_quality'];
    final mk = raw['music_key'];
    final pr = raw['progression_roman'];
    final hint = raw['hint_zh'];

    return EarBankItem(
      id: id,
      mode: mode,
      questionType: qt,
      promptZh: prompt,
      options: options,
      correctOptionKey: correct,
      root: root is String ? root : null,
      targetQuality: tq is String ? tq : null,
      musicKey: mk is String ? mk : null,
      progressionRoman: pr is String ? pr : null,
      hintZh: hint is String ? hint : null,
    );
  }
}

/// 根 JSON 文档。
class EarSeedDocument {
  const EarSeedDocument({required this.bankA, required this.bankB});

  final List<EarBankItem> bankA;
  final List<EarBankItem> bankB;

  static EarSeedDocument? tryParseMap(Map<String, dynamic> map) {
    final banks = map['banks'];
    if (banks is! Map) return null;
    final aRaw = banks['A'];
    final bRaw = banks['B'];
    final a = <EarBankItem>[];
    final b = <EarBankItem>[];
    if (aRaw is List) {
      for (final x in aRaw) {
        final item = EarBankItem.tryParse(x);
        if (item != null) a.add(item);
      }
    }
    if (bRaw is List) {
      for (final x in bRaw) {
        final item = EarBankItem.tryParse(x);
        if (item != null) b.add(item);
      }
    }
    if (a.isEmpty && b.isEmpty) return null;
    return EarSeedDocument(bankA: a, bankB: b);
  }
}
