import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'sheet_entry.dart';

/// 读写 `sheets_index.json` 与 `sheets/` 目录下的谱子副本。
class SheetLibraryStore {
  static const _indexFileName = 'sheets_index.json';
  static const _sheetsSubdir = 'sheets';

  Future<Directory> _docsDir() async {
    final d = await getApplicationDocumentsDirectory();
    return d;
  }

  Future<File> _indexFile() async {
    final root = await _docsDir();
    return File(p.join(root.path, _indexFileName));
  }

  Future<Directory> _sheetsDir() async {
    final root = await _docsDir();
    final dir = Directory(p.join(root.path, _sheetsSubdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 读取全部条目（文件损坏时返回空列表）。
  Future<List<SheetEntry>> loadAll() async {
    final f = await _indexFile();
    if (!await f.exists()) return [];
    try {
      final text = await f.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! List) return [];
      final out = <SheetEntry>[];
      for (final x in decoded) {
        final e = SheetEntry.fromJson(x);
        if (e != null) out.add(e);
      }
      out.sort((a, b) => b.addedAtMs.compareTo(a.addedAtMs));
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<SheetEntry> entries) async {
    final f = await _indexFile();
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await f.writeAsString(encoded);
  }

  /// 将 [source] 复制到沙箱并追加索引。
  Future<SheetEntry> importFile({
    required File source,
    required String displayName,
    required String id,
    required String storedFileName,
  }) async {
    final dir = await _sheetsDir();
    final dest = File(p.join(dir.path, storedFileName));
    await source.copy(dest.path);
    final entry = SheetEntry(
      id: id,
      displayName: displayName,
      storedFileName: storedFileName,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final all = await loadAll();
    all.add(entry);
    await _writeAll(all);
    return entry;
  }

  /// 删除索引项及对应文件（若存在）。
  Future<void> remove(String id) async {
    final all = await loadAll();
    final keep = <SheetEntry>[];
    SheetEntry? victim;
    for (final e in all) {
      if (e.id == id) {
        victim = e;
      } else {
        keep.add(e);
      }
    }
    if (victim != null) {
      final dir = await _sheetsDir();
      final f = File(p.join(dir.path, victim.storedFileName));
      if (await f.exists()) {
        await f.delete();
      }
    }
    await _writeAll(keep);
  }

  Future<File?> resolveStoredFile(SheetEntry e) async {
    final dir = await _sheetsDir();
    final f = File(p.join(dir.path, e.storedFileName));
    if (await f.exists()) return f;
    return null;
  }
}
