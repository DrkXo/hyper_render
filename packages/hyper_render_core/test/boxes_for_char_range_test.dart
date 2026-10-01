import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_core/hyper_render_core.dart';

const _sampleText = 'The quick brown fox jumps over the lazy dog';

RenderHyperBox? _findBox(RenderObject? root) {
  if (root == null) return null;
  if (root is RenderHyperBox) return root;
  RenderHyperBox? found;
  root.visitChildren((child) => found ??= _findBox(child));
  return found;
}

Future<RenderHyperBox> _pump(WidgetTester tester, DocumentNode document, {double width = 300}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
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
  group('RenderHyperBox.getBoxesForCharRange', () {
    testWidgets('returns empty list for inverted or invalid ranges', (tester) async {
      final box = await _pump(tester, _paragraph(_sampleText));
      expect(box.getBoxesForCharRange(10, 5), isEmpty);
      expect(box.getBoxesForCharRange(5, 5), isEmpty);
    });

    testWidgets('returns exact bounding box for single word', (tester) async {
      final box = await _pump(tester, _paragraph(_sampleText));
      // "quick" is at offsets 4..9
      final rects = box.getBoxesForCharRange(4, 9);
      expect(rects, hasLength(1));
      final rect = rects.first;
      expect(rect.width, greaterThan(10.0));
      expect(rect.height, greaterThan(8.0));
      expect(rect.left, greaterThan(0.0));
    });

    testWidgets('returns contiguous boxes across multiple words on single line', (tester) async {
      final box = await _pump(tester, _paragraph(_sampleText), width: 600);
      // "The quick brown" at 0..15
      final rects = box.getBoxesForCharRange(0, 15);
      expect(rects, hasLength(1));
      expect(rects.first.left, closeTo(0.0, 2.0));
      expect(rects.first.width, greaterThan(50.0));
    });

    testWidgets('returns boxes across lines when range wraps', (tester) async {
      // Narrow container forces wrapping
      final box = await _pump(tester, _paragraph(_sampleText), width: 120);
      // Full sentence range 0..43
      final rects = box.getBoxesForCharRange(0, _sampleText.length);
      expect(rects.length, greaterThan(1), reason: 'should produce rects per line');
    });
  });
}
