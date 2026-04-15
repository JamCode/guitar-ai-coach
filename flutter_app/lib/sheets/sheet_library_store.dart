import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'sheet_entry.dart';
import 'sheet_parsed_models.dart';

/// 读写 `sheets_index.json` 与 `sheets/` 目录下的谱子页文件副本。
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

  Future<File> _parsedFile(String sheetId) async {
    final dir = await _sheetsDir();
    return File(p.join(dir.path, '${sheetId}_parsed.json'));
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

  /// 将 [sources] 按顺序复制到沙箱并追加一条谱子索引（至少一页）。
  Future<SheetEntry> importSheetPages({
    required List<File> sources,
    required String displayName,
  }) async {
    if (sources.isEmpty) {
      throw ArgumentError('sources must not be empty');
    }
    final dir = await _sheetsDir();
    final id = const Uuid().v4();
    final storedNames = <String>[];
    for (var i = 0; i < sources.length; i++) {
      var ext = p.extension(sources[i].path).toLowerCase();
      if (ext.isEmpty || ext == '.') {
        ext = '.jpg';
      }
      final name = '${id}_$i$ext';
      final dest = File(p.join(dir.path, name));
      await sources[i].copy(dest.path);
      storedNames.add(name);
    }
    final entry = SheetEntry(
      id: id,
      displayName: displayName,
      storedFileNames: storedNames,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
      parseStatus: SheetParseStatus.rawOnly.name,
    );
    final all = await loadAll();
    all.add(entry);
    await _writeAll(all);
    return entry;
  }

  /// 删除索引项及沙箱内对应页文件（若存在）。
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
      for (final name in victim.storedFileNames) {
        final f = File(p.join(dir.path, name));
        if (await f.exists()) {
          await f.delete();
        }
      }
      final parsed = await _parsedFile(victim.id);
      if (await parsed.exists()) {
        await parsed.delete();
      }
    }
    await _writeAll(keep);
  }

  /// 读取结构化结果（不存在或损坏返回 null）。
  Future<SheetParsedData?> loadParsed(String sheetId) async {
    final f = await _parsedFile(sheetId);
    if (!await f.exists()) return null;
    try {
      final decoded = jsonDecode(await f.readAsString());
      return SheetParsedData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// 保存结构化结果并回写索引状态。
  Future<void> saveParsed(SheetParsedData data) async {
    final f = await _parsedFile(data.sheetId);
    await f.writeAsString(data.toEncodedJson());
    final all = await loadAll();
    final next = <SheetEntry>[];
    for (final entry in all) {
      if (entry.id != data.sheetId) {
        next.add(entry);
        continue;
      }
      next.add(
        entry.copyWith(
          parseStatus: data.parseStatus.name,
          parsedUpdatedAtMs: data.updatedAtMs,
        ),
      );
    }
    await _writeAll(next);
  }

  /// 解析 [e] 在沙箱中仍存在的页文件（保持 [SheetEntry.storedFileNames] 顺序，跳过缺失）。
  Future<List<File>> resolveStoredFiles(SheetEntry e) async {
    final dir = await _sheetsDir();
    final out = <File>[];
    for (final name in e.storedFileNames) {
      final f = File(p.join(dir.path, name));
      if (await f.exists()) {
        out.add(f);
      }
    }
    return out;
  }

  /// 封面用：第一张仍存在的页；若无则 `null`。
  Future<File?> resolveFirstStoredFile(SheetEntry e) async {
    final list = await resolveStoredFiles(e);
    return list.isEmpty ? null : list.first;
  }
}
