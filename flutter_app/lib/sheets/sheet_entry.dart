/// 用户导入的一条谱子元数据（文件副本保存在应用文档目录）。
class SheetEntry {
  const SheetEntry({
    required this.id,
    required this.displayName,
    required this.storedFileName,
    required this.addedAtMs,
  });

  final String id;
  final String displayName;
  final String storedFileName;
  final int addedAtMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'storedFileName': storedFileName,
        'addedAtMs': addedAtMs,
      };

  static SheetEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final dn = raw['displayName'];
    final fn = raw['storedFileName'];
    final ms = raw['addedAtMs'];
    if (id is! String || dn is! String || fn is! String) return null;
    final t = ms is int ? ms : (ms is num ? ms.toInt() : null);
    if (t == null) return null;
    return SheetEntry(
      id: id,
      displayName: dn,
      storedFileName: fn,
      addedAtMs: t,
    );
  }
}
