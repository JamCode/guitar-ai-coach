import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'sheet_ocr_parser.dart';
import 'sheet_parsed_models.dart';

/// 本地 OCR：读取谱面图片并提取和弦/旋律/歌词的初稿。
class SheetOcrService {
  SheetOcrService({TextRecognizer? recognizer})
    : _recognizer =
          recognizer ?? TextRecognizer(script: TextRecognitionScript.chinese);

  final TextRecognizer _recognizer;

  /// 对谱面页批量识别，返回可校对的结构化草稿。
  Future<List<SheetSegment>> recognizeSheetSegments(List<File> pages) async {
    final candidates = <OcrLineCandidate>[];
    for (final file in pages) {
      if (!await file.exists()) continue;
      final image = InputImage.fromFilePath(file.path);
      final recognized = await _recognizer.processImage(image);
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isEmpty) continue;
          final y = line.boundingBox.center.dy;
          candidates.add(OcrLineCandidate(text: text, centerY: y));
        }
      }
    }
    return SheetOcrParser.parseCandidates(candidates);
  }

  /// 释放 ML Kit 资源。
  Future<void> close() async {
    await _recognizer.close();
  }
}
