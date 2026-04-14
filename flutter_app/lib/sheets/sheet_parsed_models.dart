import 'dart:convert';

/// 结构化谱子解析状态：仅图片、待校对、可变调。
enum SheetParseStatus { rawOnly, draft, ready }

/// 单段结构化内容：和弦、旋律、歌词三列。
class SheetSegment {
  const SheetSegment({
    required this.chords,
    required this.melody,
    required this.lyrics,
  });

  final List<String> chords;
  final String melody;
  final String lyrics;

  Map<String, dynamic> toJson() => {
    'chords': chords,
    'melody': melody,
    'lyrics': lyrics,
  };

  static SheetSegment fromJson(Object? raw) {
    if (raw is! Map) {
      return const SheetSegment(chords: [], melody: '', lyrics: '');
    }
    final c = raw['chords'];
    final chordList = c is List
        ? c.whereType<String>().where((x) => x.isNotEmpty).toList()
        : <String>[];
    final melody = raw['melody'] is String ? raw['melody'] as String : '';
    final lyrics = raw['lyrics'] is String ? raw['lyrics'] as String : '';
    return SheetSegment(chords: chordList, melody: melody, lyrics: lyrics);
  }
}

/// 一首谱子的结构化内容，用于后续变调与展示。
class SheetParsedData {
  const SheetParsedData({
    required this.sheetId,
    required this.parseStatus,
    required this.originalKey,
    required this.segments,
    required this.updatedAtMs,
  });

  final String sheetId;
  final SheetParseStatus parseStatus;
  final String originalKey;
  final List<SheetSegment> segments;
  final int updatedAtMs;

  bool get hasContent => segments.any(
    (s) => s.chords.isNotEmpty || s.melody.isNotEmpty || s.lyrics.isNotEmpty,
  );

  SheetParsedData copyWith({
    SheetParseStatus? parseStatus,
    String? originalKey,
    List<SheetSegment>? segments,
    int? updatedAtMs,
  }) {
    return SheetParsedData(
      sheetId: sheetId,
      parseStatus: parseStatus ?? this.parseStatus,
      originalKey: originalKey ?? this.originalKey,
      segments: segments ?? this.segments,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'sheetId': sheetId,
    'parseStatus': parseStatus.name,
    'originalKey': originalKey,
    'segments': segments.map((s) => s.toJson()).toList(),
    'updatedAtMs': updatedAtMs,
  };

  String toEncodedJson() => jsonEncode(toJson());

  static SheetParsedData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final sheetId = raw['sheetId'];
    final originalKey = raw['originalKey'];
    final updatedAtRaw = raw['updatedAtMs'];
    if (sheetId is! String ||
        sheetId.isEmpty ||
        originalKey is! String ||
        originalKey.isEmpty) {
      return null;
    }
    final updatedAt = updatedAtRaw is int
        ? updatedAtRaw
        : (updatedAtRaw is num ? updatedAtRaw.toInt() : null);
    if (updatedAt == null) return null;
    final statusRaw = raw['parseStatus'];
    SheetParseStatus status = SheetParseStatus.ready;
    if (statusRaw is String) {
      for (final candidate in SheetParseStatus.values) {
        if (candidate.name == statusRaw) {
          status = candidate;
          break;
        }
      }
    }
    final segRaw = raw['segments'];
    final segments = segRaw is List
        ? segRaw.map(SheetSegment.fromJson).toList()
        : <SheetSegment>[];
    return SheetParsedData(
      sheetId: sheetId,
      parseStatus: status,
      originalKey: originalKey,
      segments: segments,
      updatedAtMs: updatedAt,
    );
  }
}
