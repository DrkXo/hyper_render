import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_core/hyper_render_core.dart';

RenderHyperBox? _findBox(RenderObject? root) {
  if (root == null) return null;
  if (root is RenderHyperBox) return root;
  RenderHyperBox? found;
  root.visitChildren((child) => found ??= _findBox(child));
  return found;
}

Future<RenderHyperBox> _pump(
  WidgetTester tester,
  DocumentNode document, {
  double width = 400,
}) async {
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

void main() {
  group('Selection spaces and smoothness tests', () {
    testWidgets(
        'selecting single space between words produces non-empty bounding box',
        (tester) async {
      // "Hello World" -> 'Hello' is 0..5, space is 5..6, 'World' is 6..11
      final doc = DocumentNode(children: [
        BlockNode.p(children: [TextNode('Hello World')]),
      ]);
      final box = await _pump(tester, doc);

      final spaceRects = box.getBoxesForCharRange(5, 6);
      expect(spaceRects, isNotEmpty,
          reason: 'selecting a space must produce a bounding box');
      expect(spaceRects.first.width, greaterThan(0.0),
          reason: 'space bounding box must have non-zero width');
    });

    testWidgets('selecting word with trailing space is wider than word alone',
        (tester) async {
      // "Hello World"
      final doc = DocumentNode(children: [
        BlockNode.p(children: [TextNode('Hello World')]),
      ]);
      final box = await _pump(tester, doc);

      final wordOnly = box.getBoxesForCharRange(0, 5);
      final wordWithSpace = box.getBoxesForCharRange(0, 6);

      expect(wordOnly, hasLength(1));
      expect(wordWithSpace, hasLength(1));
      expect(
        wordWithSpace.first.width,
        greaterThan(wordOnly.first.width),
        reason:
            'bounding box including trailing space must be wider than word alone',
      );
    });

    testWidgets(
        'selecting multiple consecutive spaces produces bounding box covering all spaces',
        (tester) async {
      final doc = DocumentNode(children: [
        BlockNode.p(children: [
          TextNode('A   B', style: ComputedStyle(whiteSpace: 'pre')),
        ]),
      ]);
      final box = await _pump(tester, doc);

      // 'A' is 0..1, spaces are 1..4, 'B' is 4..5
      final singleSpace = box.getBoxesForCharRange(1, 2);
      final threeSpaces = box.getBoxesForCharRange(1, 4);

      expect(singleSpace, isNotEmpty);
      expect(threeSpaces, isNotEmpty);
      expect(threeSpaces.first.width, greaterThan(singleSpace.first.width));
    });

    testWidgets(
        'dragging into vertical paragraph gap snaps to nearer line without freezing',
        (tester) async {
      // Two paragraphs with vertical margin
      final doc = DocumentNode(children: [
        BlockNode.p(children: [TextNode('First paragraph line.')]),
        BlockNode.p(children: [TextNode('Second paragraph line.')]),
      ]);
      final box = await _pump(tester, doc);

      // 'First paragraph line.' length: 21 (0..21)
      // 'Second paragraph line.' length: 22 (21..43)
      final p1Rects = box.getBoxesForCharRange(0, 21);
      final p2Rects = box.getBoxesForCharRange(21, 43);
      expect(p1Rects, isNotEmpty);
      expect(p2Rects, isNotEmpty);

      final p1Bottom = p1Rects.last.bottom;
      final p2Top = p2Rects.first.top;
      expect(p2Top, greaterThan(p1Bottom),
          reason: 'paragraphs should have margin between them');

      final midGapDy = (p1Bottom + p2Top) / 2;

      // Hit-testing in the vertical gap with clampOutOfBounds must NOT return -1
      final posInGap = box.getCharacterPositionAtOffset(Offset(50, midGapDy));
      expect(posInGap, isNot(-1),
          reason:
              'hit test in paragraph gap should resolve to nearest line, not -1');

      // Dragging handle into gap should update selection smoothly
      box.selection = const HyperTextSelection(start: 0, end: 5);
      box.updateSelectionFromHandle(false, Offset(50, midGapDy));
      expect(box.selection, isNotNull);
      expect(box.selection!.end, equals(posInGap));
    });

    testWidgets(
        'hit-testing above top and below bottom lines clamps gracefully',
        (tester) async {
      final doc = DocumentNode(children: [
        BlockNode.p(children: [TextNode('Only paragraph.')]),
      ]);
      final box = await _pump(tester, doc);

      // Above top and left of first char: dy = -50, dx = -10
      final aboveLeftPos =
          box.getCharacterPositionAtOffset(const Offset(-10, -50));
      expect(aboveLeftPos, equals(0),
          reason: 'above and left of line 0 must clamp to offset 0');

      // Above top at dx = 50: clamps to line 0 at dx = 50
      final aboveMidPos =
          box.getCharacterPositionAtOffset(const Offset(50, -50));
      expect(aboveMidPos, greaterThan(0),
          reason:
              'above line 0 should hit-test the corresponding character column');

      // Below bottom: dy = 5000, dx = 5000
      final belowPos =
          box.getCharacterPositionAtOffset(const Offset(5000, 5000));
      expect(belowPos, equals(box.totalCharacterCount),
          reason: 'below bottom must clamp to end of document');
    });

    testWidgets(
        'midpoint snapping between adjacent inline fragments on same line',
        (tester) async {
      final doc = DocumentNode(children: [
        BlockNode.p(children: [
          InlineNode.strong(children: [TextNode('Left')]),
          InlineNode.em(children: [TextNode('Right')]),
        ]),
      ]);
      final box = await _pump(tester, doc, width: 600);

      final leftRects = box.getBoxesForCharRange(0, 4);
      final rightRects = box.getBoxesForCharRange(4, 9);
      expect(leftRects, isNotEmpty);
      expect(rightRects, isNotEmpty);

      final leftRight = leftRects.first.right;
      final rightLeft = rightRects.first.left;
      final y = leftRects.first.center.dy;

      // Position just to the left of midpoint: should snap to left fragment end (4)
      final midDx = (leftRight + rightLeft) / 2;
      final posBeforeMid =
          box.getCharacterPositionAtOffset(Offset(midDx - 0.5, y));
      expect(posBeforeMid, equals(4));

      // Position just past midpoint: should snap to right fragment
      final posAfterMid =
          box.getCharacterPositionAtOffset(Offset(midDx + 0.5, y));
      expect(posAfterMid, greaterThanOrEqualTo(4));
    });

    testWidgets('painting selection across spaces renders without error',
        (tester) async {
      final doc = DocumentNode(children: [
        BlockNode.p(children: [TextNode('Hello World')]),
      ]);
      final box = await _pump(tester, doc);

      // Select just the space: 5..6
      box.selection = const HyperTextSelection(start: 5, end: 6);
      await tester.pump();

      expect(box.getSelectionRects(), isNotEmpty);
      expect(box.getStartHandleRect(), isNotNull);
      expect(box.getEndHandleRect(), isNotNull);
      expect(tester.takeException(), isNull);
    });
  });
}
