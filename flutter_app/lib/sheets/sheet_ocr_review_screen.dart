import 'package:flutter/material.dart';

import 'sheet_parsed_models.dart';

/// OCR 初稿校对页：确认和弦、旋律、歌词后再保存为可变调格式。
class SheetOcrReviewScreen extends StatefulWidget {
  const SheetOcrReviewScreen({
    super.key,
    required this.sheetId,
    required this.initialSegments,
  });

  final String sheetId;
  final List<SheetSegment> initialSegments;

  @override
  State<SheetOcrReviewScreen> createState() => _SheetOcrReviewScreenState();
}

class _SheetOcrReviewScreenState extends State<SheetOcrReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _chordsController = TextEditingController();
  final _melodyController = TextEditingController();
  final _lyricsController = TextEditingController();
  String _originalKey = 'C';

  @override
  void initState() {
    super.initState();
    _chordsController.text = widget.initialSegments
        .map((s) => s.chords.join(' '))
        .join('\n');
    _melodyController.text = widget.initialSegments
        .map((s) => s.melody)
        .join('\n');
    _lyricsController.text = widget.initialSegments
        .map((s) => s.lyrics)
        .join('\n');
  }

  @override
  void dispose() {
    _chordsController.dispose();
    _melodyController.dispose();
    _lyricsController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final chordLines = _splitLines(_chordsController.text);
    final melodyLines = _splitLines(_melodyController.text);
    final lyricLines = _splitLines(_lyricsController.text);
    final maxLen = _max3(
      chordLines.length,
      melodyLines.length,
      lyricLines.length,
    );
    final segments = <SheetSegment>[];
    for (var i = 0; i < maxLen; i++) {
      final chordLine = i < chordLines.length ? chordLines[i] : '';
      segments.add(
        SheetSegment(
          chords: chordLine.isEmpty
              ? const []
              : chordLine
                    .split(RegExp(r'\s+'))
                    .where((x) => x.isNotEmpty)
                    .toList(),
          melody: i < melodyLines.length ? melodyLines[i] : '',
          lyrics: i < lyricLines.length ? lyricLines[i] : '',
        ),
      );
    }
    final data = SheetParsedData(
      sheetId: widget.sheetId,
      parseStatus: SheetParseStatus.ready,
      originalKey: _originalKey,
      segments: segments,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('识别结果校对'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _originalKey,
              decoration: const InputDecoration(
                labelText: '原调',
                border: OutlineInputBorder(),
              ),
              items:
                  const [
                        'C',
                        'Db',
                        'D',
                        'Eb',
                        'E',
                        'F',
                        'Gb',
                        'G',
                        'Ab',
                        'A',
                        'Bb',
                        'B',
                      ]
                      .map(
                        (x) =>
                            DropdownMenuItem<String>(value: x, child: Text(x)),
                      )
                      .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _originalKey = value);
              },
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: '和弦（每行一段）',
              hint: '例如：C D7 G7 C',
              controller: _chordsController,
            ),
            const SizedBox(height: 12),
            _buildSection(
              title: '旋律（每行一段）',
              hint: '例如：033551 17 | 76366-',
              controller: _melodyController,
            ),
            const SizedBox(height: 12),
            _buildSection(
              title: '歌词（每行一段）',
              hint: '例如：我听见雨滴落在 青青草地',
              controller: _lyricsController,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String hint,
    required TextEditingController controller,
  }) {
    return TextFormField(
      controller: controller,
      minLines: 3,
      maxLines: 8,
      decoration: InputDecoration(
        labelText: title,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  List<String> _splitLines(String text) {
    return text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  int _max3(int a, int b, int c) => (a > b ? (a > c ? a : c) : (b > c ? b : c));
}
