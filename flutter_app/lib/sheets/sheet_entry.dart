/// 用户的一条谱子元数据。
///
/// 本地模式：每页对应沙箱内一个文件副本（[storedFileNames] 有序）。
/// 云端模式：[storedFileNames] 可为空，此时 [serverPageCount] 表示页数。
class SheetEntry {
  const SheetEntry({
    required this.id,
    required this.displayName,
    required this.storedFileNames,
    required this.addedAtMs,
    this.serverPageCount,
    this.parseStatus = 'rawOnly',
    this.parsedUpdatedAtMs,
  });

  final String id;
  final String displayName;

  /// 相对于应用文档目录下 `sheets/` 的文件名列表，顺序即页序（仅本地）。
  final List<String> storedFileNames;
  final int addedAtMs;

  /// 云端谱页数；非空时优先于 [storedFileNames.length]。
  final int? serverPageCount;
  final String parseStatus;
  final int? parsedUpdatedAtMs;

  int get pageCount => serverPageCount ?? storedFileNames.length;

  SheetEntry copyWith({
    String? displayName,
    List<String>? storedFileNames,
    int? addedAtMs,
    int? serverPageCount,
    String? parseStatus,
    int? parsedUpdatedAtMs,
  }) {
    return SheetEntry(
      id: id,
      displayName: displayName ?? this.displayName,
      storedFileNames: storedFileNames ?? this.storedFileNames,
      addedAtMs: addedAtMs ?? this.addedAtMs,
      serverPageCount: serverPageCount ?? this.serverPageCount,
      parseStatus: parseStatus ?? this.parseStatus,
      parsedUpdatedAtMs: parsedUpdatedAtMs ?? this.parsedUpdatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'storedFileNames': storedFileNames,
    'addedAtMs': addedAtMs,
    if (serverPageCount != null) 'serverPageCount': serverPageCount,
    'parseStatus': parseStatus,
    if (parsedUpdatedAtMs != null) 'parsedUpdatedAtMs': parsedUpdatedAtMs,
  };

  /// 解析索引项；兼容旧版单文件字段 `storedFileName`。
  static SheetEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final dn = raw['displayName'];
    final ms = raw['addedAtMs'];
    if (id is! String || dn is! String) return null;
    final t = ms is int ? ms : (ms is num ? ms.toInt() : null);
    if (t == null) return null;

    int? spc;
    final spcRaw = raw['serverPageCount'];
    if (spcRaw is int) {
      spc = spcRaw;
    } else if (spcRaw is num) {
      spc = spcRaw.toInt();
    }
    final statusRaw = raw['parseStatus'];
    final parseStatus = statusRaw is String && statusRaw.isNotEmpty
        ? statusRaw
        : 'rawOnly';
    final parsedAtRaw = raw['parsedUpdatedAtMs'];
    int? parsedUpdatedAtMs;
    if (parsedAtRaw is int) {
      parsedUpdatedAtMs = parsedAtRaw;
    } else if (parsedAtRaw is num) {
      parsedUpdatedAtMs = parsedAtRaw.toInt();
    }

    final namesRaw = raw['storedFileNames'];
    if (namesRaw is List) {
      final names = namesRaw
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.isNotEmpty) {
        return SheetEntry(
          id: id,
          displayName: dn,
          storedFileNames: names,
          addedAtMs: t,
          serverPageCount: spc,
          parseStatus: parseStatus,
          parsedUpdatedAtMs: parsedUpdatedAtMs,
        );
      }
    }
    final legacy = raw['storedFileName'];
    if (legacy is String && legacy.isNotEmpty) {
      return SheetEntry(
        id: id,
        displayName: dn,
        storedFileNames: [legacy],
        addedAtMs: t,
        serverPageCount: spc,
        parseStatus: parseStatus,
        parsedUpdatedAtMs: parsedUpdatedAtMs,
      );
    }
    if (spc != null && spc > 0) {
      return SheetEntry(
        id: id,
        displayName: dn,
        storedFileNames: const [],
        addedAtMs: t,
        serverPageCount: spc,
        parseStatus: parseStatus,
        parsedUpdatedAtMs: parsedUpdatedAtMs,
      );
    }
    return null;
  }
}
