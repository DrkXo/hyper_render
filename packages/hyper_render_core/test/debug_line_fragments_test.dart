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

DocumentNode _paragraph(String text) => DocumentNode(children: [
      BlockNode.p(children: [TextNode(text)])
    ]);

void main() {
  group('debugLineFragments', () {
    testWidgets('reports a positioned fragment for every line', (
      tester,
    ) async {
      final box = await _pump(tester, _paragraph(_longText));

      final lines = box.debugLines();
      expect(lines.length, greaterThan(1), reason: 'the text must wrap');

      final lineFragments = box.debugLineFragments();

      final expected = lines.fold<int>(
        0,
        (sum, line) => sum + (line['fragmentCount'] as int),
      );
      expect(lineFragments.length, expected);

      for (final fragment in lineFragments) {
        expect(fragment['offsetX'], isA<double>());
        expect(fragment['offsetY'], isA<double>());
        expect(fragment['width'], isA<double>());
        expect(fragment['charStart'], isA<int>());
        expect(fragment['charEnd'], isA<int>());
      }
    });

    testWidgets('reports monotonically ordered character ranges', (
      tester,
    ) async {
      final box = await _pump(tester, _paragraph(_longText));
      final fragments = box.debugLineFragments();
      expect(fragments, isNotEmpty);

      for (var index = 1; index < fragments.length; index++) {
        expect(
          fragments[index]['charStart'] as int,
          greaterThanOrEqualTo(fragments[index - 1]['charStart'] as int),
        );
      }

      final joined =
          fragments.map((fragment) => fragment['text'] as String? ?? '').join();
      String stripWhitespace(String text) =>
          text.replaceAll(RegExp(r'\s+'), '');
      expect(stripWhitespace(joined), stripWhitespace(_longText));
      expect(fragments.last['charEnd'], box.totalCharacterCount);
    });

    testWidgets('agrees with debugLines on line bounds and index', (
      tester,
    ) async {
      final box = await _pump(tester, _paragraph(_longText));
      final lines = box.debugLines();
      final fragments = box.debugLineFragments();

      final byIndex = <int, List<Map<String, dynamic>>>{};
      for (final fragment in fragments) {
        byIndex
            .putIfAbsent(fragment['lineIndex'] as int, () => [])
            .add(fragment);
      }

      for (var index = 0; index < lines.length; index++) {
        final inLine = byIndex[index];
        if (inLine == null) continue;
        for (final fragment in inLine) {
          expect(fragment['lineTop'], lines[index]['top']);
          expect(fragment['lineHeight'], lines[index]['height']);
        }
      }
    });

    testWidgets('reports rubyText with the positioned base text', (
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
          .where((fragment) => fragment['type'] == 'ruby')
          .toList();
      expect(ruby, isNotEmpty);
      expect(ruby.first['rubyText'], 'かんじ');
      expect(ruby.first['text'], '漢字');

      final debugRuby = box
          .debugFragments()
          .where((fragment) => fragment['type'] == 'ruby')
          .toList();
      expect(debugRuby, isNotEmpty);
      expect(debugRuby.first['rubyText'], 'かんじ');
    });

    testWidgets('includes ellipsisVisibleLength for every fragment', (
      tester,
    ) async {
      final box = await _pump(tester, _paragraph(_longText));
      for (final fragment in box.debugLineFragments()) {
        expect(fragment.containsKey('ellipsisVisibleLength'), isTrue);
      }
    });
  });

  group('debugFragments geometry for wrapped text', () {
    testWidgets('remains unpositioned while line fragments have geometry', (
      tester,
    ) async {
      final box = await _pump(tester, _paragraph(_longText));
      expect(box.debugLines().length, greaterThan(1));

      final textFragments = box
          .debugFragments()
          .where((fragment) => (fragment['text'] as String? ?? '').isNotEmpty)
          .toList();
      expect(textFragments, isNotEmpty);
      expect(
        textFragments.every((fragment) => fragment['offsetX'] == null),
        isTrue,
      );
      expect(
        box
            .debugLineFragments()
            .every((fragment) => fragment['offsetX'] is double),
        isTrue,
      );
    });
  });
}
