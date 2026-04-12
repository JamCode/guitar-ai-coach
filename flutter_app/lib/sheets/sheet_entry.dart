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
  });

  final String id;
  final String displayName;

  /// 相对于应用文档目录下 `sheets/` 的文件名列表，顺序即页序（仅本地）。
  final List<String> storedFileNames;
  final int addedAtMs;

  /// 云端谱页数；非空时优先于 [storedFileNames.length]。
  final int? serverPageCount;

  int get pageCount => serverPageCount ?? storedFileNames.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'storedFileNames': storedFileNames,
        'addedAtMs': addedAtMs,
        if (serverPageCount != null) 'serverPageCount': serverPageCount,
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

    final namesRaw = raw['storedFileNames'];
    if (namesRaw is List) {
      final names = namesRaw.whereType<String>().where((s) => s.isNotEmpty).toList();
      if (names.isNotEmpty) {
        return SheetEntry(
          id: id,
          displayName: dn,
          storedFileNames: names,
          addedAtMs: t,
          serverPageCount: spc,
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
      );
    }
    if (spc != null && spc > 0) {
      return SheetEntry(
        id: id,
        displayName: dn,
        storedFileNames: const [],
        addedAtMs: t,
        serverPageCount: spc,
      );
    }
    return null;
  }
}
