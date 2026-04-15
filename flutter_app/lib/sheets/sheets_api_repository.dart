import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/auth_session_store.dart';
import '../settings/api_base_url_store.dart';
import 'sheet_entry.dart';

/// 调用后端 `/sheets`：列表、multipart 创建、删除；读图字节用于 [Image.memory]。
///
/// 依赖已登录的 [AuthSessionStore] 与 [ApiBaseUrlStore]。
class SheetsApiRepository {
  SheetsApiRepository({
    AuthSessionStore? sessionStore,
    ApiBaseUrlStore? baseUrlStore,
    http.Client? client,
  })  : _session = sessionStore ?? AuthSessionStore(),
        _baseStore = baseUrlStore ?? ApiBaseUrlStore(),
        _client = client ?? http.Client();

  final AuthSessionStore _session;
  final ApiBaseUrlStore _baseStore;
  final http.Client _client;

  Future<String> _base() async {
    final b = await _baseStore.load();
    if (b.isEmpty) {
      throw SheetsApiException('当前环境未配置可用 API 地址，请联系管理员。');
    }
    return b;
  }

  Future<String> _token() async {
    final t = await _session.loadAccessToken();
    if (t == null || t.isEmpty) {
      throw SheetsApiException('请先登录。');
    }
    return t;
  }

  Future<Map<String, String>> _authHeaders() async {
    final t = await _token();
    return {
      'Authorization': 'Bearer $t',
      'Accept': 'application/json',
    };
  }

  /// GET `/sheets`。
  Future<List<SheetEntry>> listSheets() async {
    final base = await _base();
    final uri = Uri.parse('$base/sheets');
    http.Response resp;
    try {
      resp = await _client.get(uri, headers: await _authHeaders());
    } catch (e) {
      throw SheetsApiException('网络错误：$e');
    }
    if (resp.statusCode != 200) {
      throw SheetsApiException(_errMessage(resp));
    }
    Map<String, dynamic>? map;
    try {
      final d = jsonDecode(resp.body);
      map = d is Map<String, dynamic> ? d : null;
    } catch (_) {
      map = null;
    }
    final list = map?['sheets'];
    if (list is! List) {
      return [];
    }
    final out = <SheetEntry>[];
    for (final x in list) {
      if (x is! Map<String, dynamic>) continue;
      final id = x['id'];
      final dn = x['display_name'];
      final pc = x['page_count'];
      final ms = x['added_at_ms'];
      if (id is! String || dn is! String) continue;
      final pages = pc is int ? pc : (pc is num ? pc.toInt() : 0);
      final added = ms is int ? ms : (ms is num ? ms.toInt() : 0);
      if (pages <= 0) continue;
      out.add(
        SheetEntry(
          id: id,
          displayName: dn,
          storedFileNames: const [],
          addedAtMs: added,
          serverPageCount: pages,
        ),
      );
    }
    return out;
  }

  /// DELETE `/sheets/{id}`。
  Future<void> deleteSheet(String publicId) async {
    final base = await _base();
    final uri = Uri.parse('$base/sheets/${Uri.encodeComponent(publicId)}');
    http.Response resp;
    try {
      resp = await _client.delete(uri, headers: await _authHeaders());
    } catch (e) {
      throw SheetsApiException('网络错误：$e');
    }
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw SheetsApiException(_errMessage(resp));
    }
  }

  /// POST `multipart/form-data`：`display_name` + 多个 `page` 文件域。
  Future<void> createSheet({
    required String displayName,
    required List<XFile> images,
  }) async {
    if (images.isEmpty) {
      throw SheetsApiException('至少一页');
    }
    final base = await _base();
    final uri = Uri.parse('$base/sheets');
    final req = http.MultipartRequest('POST', uri);
    final headers = await _authHeaders();
    req.headers.addAll(headers);
    req.fields['display_name'] = displayName.trim();
    for (var i = 0; i < images.length; i++) {
      final path = images[i].path;
      final file = File(path);
      if (!await file.exists()) {
        throw SheetsApiException('临时文件已失效，请重新选择');
      }
      final ext = _extFromPath(path);
      final mime = _mimeFromExt(ext);
      req.files.add(
        await http.MultipartFile.fromPath(
          'page',
          path,
          filename: 'page_$i$ext',
          contentType: MediaType.parse(mime),
        ),
      );
    }
    http.Response resp;
    try {
      final streamed = await _client.send(req);
      resp = await http.Response.fromStream(streamed);
    } catch (e) {
      throw SheetsApiException('网络错误：$e');
    }
    if (resp.statusCode != 200) {
      throw SheetsApiException(_errMessage(resp));
    }
  }

  /// GET `/sheets/{id}/pages/{n}` 返回原始字节（须调用方关闭 client 时由 repository 管理）。
  Future<List<int>> fetchPageBytes(String sheetId, int pageIndex) async {
    final base = await _base();
    final uri = Uri.parse('$base/sheets/${Uri.encodeComponent(sheetId)}/pages/$pageIndex');
    http.Response resp;
    try {
      resp = await _client.get(uri, headers: await _authHeaders());
    } catch (e) {
      throw SheetsApiException('网络错误：$e');
    }
    if (resp.statusCode != 200) {
      throw SheetsApiException(_errMessage(resp));
    }
    return resp.bodyBytes;
  }

  static String _errMessage(http.Response resp) {
    try {
      final d = jsonDecode(resp.body);
      if (d is Map && d['detail'] != null) {
        return '请求失败（${resp.statusCode}）：${d['detail']}';
      }
      if (d is Map && d['error'] != null) {
        return '请求失败（${resp.statusCode}）：${d['error']}';
      }
    } catch (_) {}
    return '请求失败（${resp.statusCode}）';
  }

  static String _extFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    return '.jpg';
  }

  static String _mimeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

/// [SheetsApiRepository] 的可读错误。
class SheetsApiException implements Exception {
  SheetsApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
