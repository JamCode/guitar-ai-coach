import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_helper/chords/chord_symbol.dart';

void main() {
  test('buildChordSymbol 拼接根音性质 slash', () {
    expect(
      buildChordSymbol(root: 'C', qualId: '', bassId: ''),
      'C',
    );
    expect(
      buildChordSymbol(root: 'A', qualId: 'm', bassId: '/C'),
      'Am/C',
    );
    expect(
      buildChordSymbol(root: 'G', qualId: 'maj7', bassId: ''),
      'Gmaj7',
    );
  });

  test('ChordSelectCatalog 键与难度非空', () {
    expect(ChordSelectCatalog.keys, isNotEmpty);
    expect(ChordSelectCatalog.levels, contains('中级'));
    expect(ChordSelectCatalog.referenceKey, 'C');
  });
}
