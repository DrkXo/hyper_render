import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_core/hyper_render_core.dart';

/// DevTools hooks added for the v2.x inspector: per-renderer layout/paint
/// timing, selection change reporting, and the extra fragment fields the
/// selection panel reads.
void main() {
  tearDown(() {
    HyperRenderDebugHooks.onFrameTiming = null;
    HyperRenderDebugHooks.onSelectionChanged = null;
  });

  Widget doc() => Directionality(
        textDirection: TextDirection.ltr,
        child: HyperRenderWidget(
          document: DocumentNode(children: [
            BlockNode.p(children: [TextNode('Hello timing hooks')]),
          ]),
        ),
      );

  RenderHyperBox box(WidgetTester tester) =>
      tester.renderObject<RenderHyperBox>(find.byType(HyperRenderWidget));

  testWidgets('onFrameTiming reports layout and paint for one renderer id',
      (tester) async {
    final samples = <(String, String, int)>[];
    HyperRenderDebugHooks.onFrameTiming =
        (id, phase, micros) => samples.add((id, phase, micros));

    await tester.pumpWidget(doc());

    expect(samples.map((s) => s.$2), containsAll(['layout', 'paint']));
    expect(samples.map((s) => s.$1).toSet(), hasLength(1));
    expect(samples.every((s) => s.$3 >= 0), isTrue);
    expect(HyperRenderDebugHooks.isActive, isTrue);
  });

  testWidgets('no timing work when the hook is null', (tester) async {
    await tester.pumpWidget(doc());
    expect(tester.takeException(), isNull);
    expect(HyperRenderDebugHooks.isActive, isFalse);
  });

  testWidgets('onSelectionChanged fires on change only, null on clear',
      (tester) async {
    final events = <(int?, int?)>[];
    HyperRenderDebugHooks.onSelectionChanged =
        (id, start, end) => events.add((start, end));

    await tester.pumpWidget(doc());
    expect(events, isEmpty, reason: 'no selection yet — nothing to report');

    box(tester).selectAll();
    await tester.pump();
    expect(events, [(0, 'Hello timing hooks'.length)]);

    // Repaint without a selection change must not re-report.
    box(tester).markNeedsPaint();
    await tester.pump();
    expect(events, hasLength(1));

    box(tester).clearSelection();
    await tester.pump();
    expect(events.last, (null, null));
  });

  testWidgets('debugFragments exposes globalOffset and charLength',
      (tester) async {
    await tester.pumpWidget(doc());
    final text =
        box(tester).debugFragments().where((f) => f['type'] == 'text').toList();
    expect(text, isNotEmpty);
    var expected = 0;
    for (final f in text) {
      expect(f['globalOffset'], expected);
      expected += f['charLength'] as int;
    }
    expect(expected, 'Hello timing hooks'.length);
  });
}
