import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';
import 'package:hyper_render/src/widgets/virtualized_selection_controller.dart';
import 'package:hyper_render_core/hyper_render_core.dart';

void main() {
  group('Selection Space and Smoothness UI Tests', () {
    testWidgets(
        'HyperSelectionOverlay end handle rect advances over space characters',
        (tester) async {
      // Document with two words separated by a space
      final doc = DocumentNode(children: [
        BlockNode.p(children: [TextNode('WordA WordB')]),
      ]);

      final key = GlobalKey<HyperSelectionOverlayState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 300,
              child: HyperSelectionOverlay(
                key: key,
                document: doc,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find RenderHyperBox to inspect selection rects directly
      final renderBox =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;

      // Select 'WordA' (0..5) vs 'WordA ' (0..6)
      final rectsWithoutSpace = renderBox.getBoxesForCharRange(0, 5);
      final rectsWithSpace = renderBox.getBoxesForCharRange(0, 6);

      expect(rectsWithoutSpace, isNotEmpty);
      expect(rectsWithSpace, isNotEmpty);
      expect(
        rectsWithSpace.first.right,
        greaterThan(rectsWithoutSpace.first.right),
        reason:
            'End handle anchor rect must advance to the right of the space character',
      );
    });

    testWidgets(
        'Dragging handle across paragraph gap updates selection smoothly without dropping',
        (tester) async {
      final doc = DocumentNode(children: [
        BlockNode.p(children: [TextNode('Paragraph one text here.')]),
        BlockNode.p(children: [TextNode('Paragraph two text here.')]),
      ]);

      final key = GlobalKey<HyperSelectionOverlayState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 400,
              child: HyperSelectionOverlay(
                key: key,
                document: doc,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Select all first to materialize handles
      key.currentState!.selectAll();
      await tester.pumpAndSettle();

      expect(key.currentState!.hasSelection, isTrue);

      final renderBox =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      final initialSelection = key.currentState!.selection;
      expect(initialSelection, isNotNull);

      // Locate the gap between paragraphs
      final p1Boxes = renderBox.getBoxesForCharRange(0, 24);
      final p2Boxes = renderBox.getBoxesForCharRange(24, 48);
      final p1Bottom = p1Boxes.last.bottom;
      final p2Top = p2Boxes.first.top;
      final gapDy = (p1Bottom + p2Top) / 2;

      // Simulate dragging start handle into the gap between paragraphs
      renderBox.updateSelectionFromHandle(true, Offset(100, gapDy));
      await tester.pump();

      expect(key.currentState!.hasSelection, isTrue);
      final currentSelection = renderBox.selection;
      expect(currentSelection, isNotNull);
      expect(currentSelection!.start, isNonNegative);
    });

    testWidgets(
        'VirtualizedSelectionController guards against negative offset when hit-testing outside bounds',
        (tester) async {
      final listViewKey = GlobalKey();
      final sections = [
        DocumentNode(children: [
          BlockNode.p(children: [TextNode('Chunk 0 content')])
        ]),
        DocumentNode(children: [
          BlockNode.p(children: [TextNode('Chunk 1 content')])
        ]),
      ];

      final controller = VirtualizedSelectionController(
        sectionsGetter: () => sections,
        listViewKey: listViewKey,
      );

      controller.selectAll();
      expect(controller.hasSelection, isTrue);
      final startAnchorBefore = controller.selection!.start;

      // Update selection from handle pointing to a negative off-screen coordinate
      // where no chunk matches
      controller.updateSelectionFromHandle(true, const Offset(-1000, -1000));
      // Should not throw or crash
      expect(controller.selection, isNotNull);
      expect(controller.selection!.start, equals(startAnchorBefore));
    });
  });
}
