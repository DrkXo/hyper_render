import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_core/hyper_render_core.dart';

/// Long enough to wrap several times at the widths used below.
const _longText =
    'The quick brown fox jumps over the lazy dog while the reader turns '
    'another page of a long chapter without pausing to consider anything.';

RenderHyperBox? _findBox(RenderObject? root) {
  if (root == null) return null;
  if (root is RenderHyperBox) return root;
  RenderHyperBox? found;
  root.visitChildren((child) => found ??= _findBox(child));
  return found;
}

Future<RenderHyperBox> _pump(WidgetTester tester, DocumentNode document) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          child: HyperRenderWidget(document: document),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final box = _findBox(
    find.byType(HyperRenderWidget).evaluate().first.renderObject,
  );
  expect(box, isNotNull, reason: 'no RenderHyperBox was built');
  return box!;
}

DocumentNode _paragraph(String text) =>
    DocumentNode(children: [BlockNode.p(children: [TextNode(text)])]);

void main() {
  group('debugLineFragments', () {
    testWidgets('reports a positioned fragment for every line', (
      tester,
    ) async {
      final box = await _pump(tester, _paragraph(_longText));

      final lines = box.debugLines();
      expect(lines.length, greaterThan(1), reason: 'the text must wrap');

      final lineFragments = box.debugLineFragments();

      // One entry per fragment across all lines, as reported by debugLines.
      final expected = lines.fold<int>(
        0,
        (sum, l) => sum + (l['fragmentCount'] as int),
      );
      expect(lineFragments.length, expected);

      for (final f in lineFragments) {
        expect(f['offsetX'], isA<double>(), reason: 'every reported fragment '
            'was positioned, which is the whole point of this method');
        expect(f['offsetY'], isA<double>());
        expect(f['width'], isA<double>());
        expect(f['charStart'], isA<int>());
        expect(f['charEnd'], isA<int>());
      }
    });

    testWidgets('every character of a wrapped paragraph is covered', (
      tester,
    ) async {
      final box = await _pump(tester, _paragraph(_longText));
      final fragments = box.debugLineFragments();
      expect(fragments, isNotEmpty);

      // Ranges advance monotonically.
      for (var i = 1; i < fragments.length; i++) {
        expect(
          fragments[i]['charStart'] as int,
          greaterThanOrEqualTo(fragments[i - 1]['charStart'] as int),
        );
      }

      // Ranges are contiguous-with-gaps: concatenating them loses exactly the
      // whitespace trimmed at each wrap and nothing else. This is the property
      // that lets a consumer treat a gap as "not drawn" rather than as a bug.
      final joined = fragments.map((f) => f['text'] as String? ?? '').join();
      String strip(String s) => s.replaceAll(RegExp(r'\s+'), '');
      expect(strip(joined), strip(_longText));

      // The last range ends at the renderer's own total.
      expect(
        fragments.last['charEnd'] as int,
        box.totalCharacterCount,
      );
    });

    testWidgets('agrees with debugLines on line bounds and index', (
      tester,
    ) async {
      final box = await _pump(tester, _paragraph(_longText));
      final lines = box.debugLines();
      final fragments = box.debugLineFragments();

      final byIndex = <int, List<Map<String, dynamic>>>{};
      for (final f in fragments) {
        byIndex.putIfAbsent(f['lineIndex'] as int, () => []).add(f);
      }

      for (var i = 0; i < lines.length; i++) {
        final inLine = byIndex[i];
        if (inLine == null) continue;
        for (final f in inLine) {
          expect(f['lineTop'], lines[i]['top']);
          expect(f['lineHeight'], lines[i]['height']);
        }
      }
    });

    testWidgets('exposes rubyText, which debugFragments omits', (
      tester,
    ) async {
      final document = DocumentNode(
        children: [
          BlockNode.p(
            children: [RubyNode(baseText: '漢字', rubyText: 'かんじ')],
          ),
        ],
      );
      final box = await _pump(tester, document);

      final ruby = box
          .debugLineFragments()
          .where((f) => f['type'] == 'ruby')
          .toList();
      expect(ruby, isNotEmpty, reason: 'the ruby fragment was positioned');
      expect(ruby.first['rubyText'], 'かんじ');
      // The base characters are what gets drawn; the reading is a different
      // string of a different length, which is why a consumer needs both.
      expect(ruby.first['text'], '漢字');

      expect(
        box.debugFragments().every((f) => !f.containsKey('rubyText')),
        isTrue,
        reason: 'this is the blind spot that motivated the field being added',
      );
    });

    testWidgets('reports an ellipsisVisibleLength key for every fragment', (
      tester,
    ) async {
      final box = await _pump(tester, _paragraph(_longText));
      for (final f in box.debugLineFragments()) {
        expect(
          f.containsKey('ellipsisVisibleLength'),
          isTrue,
          reason: 'null when untruncated, but the key must exist so a consumer '
              'can tell "not truncated" from "not reported"',
        );
      }
    });
  });

  group('debugFragments does not report geometry for wrapped text', () {
    // The reason this method exists, pinned as a regression test. If a future
    // layout change starts populating the tokenizer fragment, this fails and
    // the method can be reconsidered rather than silently kept.
    testWidgets('a wrapped text node is unpositioned', (tester) async {
      final box = await _pump(tester, _paragraph(_longText));
      expect(box.debugLines().length, greaterThan(1));

      final text = box
          .debugFragments()
          .where((f) => (f['text'] as String? ?? '').isNotEmpty)
          .toList();
      expect(text, isNotEmpty);
      expect(text.every((f) => f['offsetX'] == null), isTrue);
    });
  });
}
