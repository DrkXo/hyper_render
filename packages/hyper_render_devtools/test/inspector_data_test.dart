import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_core/hyper_render_core.dart';
import 'package:hyper_render_devtools/src/inspector_data.dart';

void main() {
  group('TimingBuffer', () {
    test('keeps at most capacity samples per renderer, dropping oldest', () {
      final buf = TimingBuffer(capacity: 3);
      for (var i = 0; i < 5; i++) {
        buf.add('a', TimingSample('paint', i, i));
      }
      buf.add('b', const TimingSample('layout', 9, 0));
      expect(buf.samplesFor('a').map((s) => s.micros), [2, 3, 4]);
      expect(buf.samplesFor('b'), hasLength(1));
    });

    test('toJson can narrow to one renderer; remove forgets it', () {
      final buf = TimingBuffer()
        ..add('a', const TimingSample('layout', 1, 0))
        ..add('b', const TimingSample('paint', 2, 0));
      expect(buf.toJson().keys, ['a', 'b']);
      expect(buf.toJson(onlyId: 'b').keys, ['b']);
      buf.remove('a');
      expect(buf.samplesFor('a'), isEmpty);
    });
  });

  group('collectCssVariables', () {
    DocumentNode doc() {
      final root = DocumentNode(children: [
        BlockNode.div(children: [
          BlockNode.p(children: [TextNode('x')]),
        ]),
      ]);
      final div = root.children.first;
      final p = div.children.first;
      root.style.customProperties['--brand'] = 'red';
      // Inherited copy — not a definition site.
      div.style.customProperties['--brand'] = 'red';
      // Override + new variable — both definition sites.
      p.style.customProperties
        ..['--brand'] = 'blue'
        ..['--gap'] = '4px';
      return root;
    }

    test('reports only nodes that define or change a variable', () {
      final vars = collectCssVariables(doc());
      expect(
        vars.map((v) => '${v['nodeTag']}:${v['name']}=${v['value']}'),
        ['document:--brand=red', 'p:--brand=blue', 'p:--gap=4px'],
      );
    });
  });

  group('applyCssVariableOverride', () {
    test('sets, trims, and removes on empty value', () {
      final a = applyCssVariableOverride(const {}, '--c', ' blue ')!;
      expect(a, {'--c': 'blue'});
      final b = applyCssVariableOverride(a, '--g', '4px')!;
      expect(b, {'--c': 'blue', '--g': '4px'});
      expect(applyCssVariableOverride(b, '--c', '')!, {'--g': '4px'});
      expect(a, {'--c': 'blue'}, reason: 'input map is not mutated');
    });

    test('rejects non custom-property names', () {
      expect(applyCssVariableOverride(const {}, 'color', 'red'), isNull);
      expect(applyCssVariableOverride(const {}, '--', 'red'), isNull);
    });
  });

  test('buildSnapshot is JSON-encodable and self-describing', () {
    final document = DocumentNode(children: [
      BlockNode.p(children: [TextNode('hi')]),
    ]);
    final snap = buildSnapshot(
      id: 'r1',
      document: document,
      fragments: const [
        {'type': 'text', 'text': 'hi'},
      ],
      lines: const [],
      selection: (start: 0, end: 2),
      timing: const [TimingSample('layout', 120, 0)],
      capturedAt: DateTime.utc(2026, 10, 2),
    );
    final decoded = jsonDecode(jsonEncode(snap)) as Map<String, dynamic>;
    expect(decoded['schema'], 'hyper_render_devtools.snapshot/1');
    expect(decoded['rendererId'], 'r1');
    expect(decoded['capturedAt'], '2026-10-02T00:00:00.000Z');
    expect(decoded['selection'], {'start': 0, 'end': 2});
    expect((decoded['tree'] as List).single['type'], 'document');
    expect(decoded['timing'], [
      {'phase': 'layout', 'micros': 120, 't': 0},
    ]);
  });
}
