import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_devtools_ui/src/inspector_logic.dart';

void main() {
  group('summarizeTimeline', () {
    test('aggregates per phase and sorts slowest renderer first', () {
      final rows = summarizeTimeline({
        'fast': [
          {'phase': 'layout', 'micros': 100, 't': 0},
          {'phase': 'paint', 'micros': 50, 't': 1},
        ],
        'slow': [
          {'phase': 'layout', 'micros': 900, 't': 0},
          {'phase': 'layout', 'micros': 300, 't': 1},
          {'phase': 'paint', 'micros': 40, 't': 2},
          {'phase': 'paint', 'micros': 60, 't': 3},
        ],
      });
      expect(rows.map((r) => r.id), ['slow', 'fast']);
      final slow = rows.first;
      expect(slow.layout!.count, 2);
      expect(slow.layout!.avgMicros, 600);
      expect(slow.layout!.maxMicros, 900);
      expect(slow.layout!.lastMicros, 300);
      expect(slow.paintHistory, [40, 60]);
    });

    test('a renderer with no samples has null stats', () {
      final rows = summarizeTimeline({'idle': []});
      expect(rows.single.layout, isNull);
      expect(rows.single.paint, isNull);
      expect(rows.single.worstMicros, 0);
    });
  });

  test('formatMicros switches to ms at 1000 µs', () {
    expect(formatMicros(null), '—');
    expect(formatMicros(999), '999 µs');
    expect(formatMicros(1234), '1.23 ms');
  });

  group('fragmentSpans', () {
    final fragments = [
      {'type': 'blockStart'},
      {'type': 'text', 'text': 'Hello ', 'globalOffset': 0, 'charLength': 6},
      {'type': 'atomic', 'globalOffset': 6, 'charLength': 0},
      {
        'type': 'ruby',
        'text': '漢字',
        'rubyText': 'かんじ',
        'globalOffset': 6,
        'charLength': 2,
      },
      {'type': 'text', 'text': ' world', 'globalOffset': 8, 'charLength': 6},
    ];

    test('keeps only text/ruby fragments with their global boundaries', () {
      final spans = fragmentSpans(fragments);
      expect(spans.map((s) => '${s.index}:${s.start}-${s.end}'),
          ['1:0-6', '3:6-8', '4:8-14']);
      expect(spans.any((s) => s.isSelected), isFalse);
      expect(spans[1].isRuby, isTrue);
    });

    test('maps a selection onto fragment-local ranges', () {
      // Select "lo 漢字 w" = global [3, 9).
      final spans =
          fragmentSpans(fragments, selectionStart: 3, selectionEnd: 9);
      expect(
        spans.map(
            (s) => s.isSelected ? '${s.selectedFrom}-${s.selectedTo}' : '-'),
        ['3-6', '0-2', '0-1'],
      );
    });

    test('collapsed selection selects nothing', () {
      final spans =
          fragmentSpans(fragments, selectionStart: 4, selectionEnd: 4);
      expect(spans.any((s) => s.isSelected), isFalse);
    });
  });
}
