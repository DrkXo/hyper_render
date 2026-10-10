// Edge cases for the 1.13.0 additions that the main suites reach only
// indirectly: character-range boxes over ruby text, the ellipsis-only line,
// and the TextPainter-layout debug hooks (used for a deterministic,
// clock-free check that line breaking does a bounded amount of shaping).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';
import 'package:hyper_render_core/hyper_render_core.dart'
    show HyperRenderDebugHooks;

Future<RenderHyperBox> _pump(
  WidgetTester tester,
  String html, {
  double width = 300,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: HyperViewer(html: html, mode: HyperRenderMode.sync),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  return tester.renderObject<RenderHyperBox>(
    find.byType(HyperRenderWidget).first,
  );
}

void main() {
  group('getBoxesForCharRange', () {
    testWidgets('a ruby fragment yields one box spanning its line',
        (tester) async {
      final box = await _pump(
        tester,
        '<p>前<ruby>日本語<rt>にほんご</rt></ruby>後</p>',
      );
      final ruby = box
          .debugLineFragments()
          .firstWhere((f) => f['type'] == 'ruby' || f['rubyText'] != null);
      final start = ruby['charStart'] as int;
      final end = ruby['charEnd'] as int;
      final boxes = box.getBoxesForCharRange(start, end);
      expect(boxes, hasLength(1));
      expect(boxes.single.left, closeTo(ruby['offsetX'] as double, 0.5));
      expect(boxes.single.width, closeTo(ruby['width'] as double, 0.5));
      // The box spans the whole line, not just the base text.
      expect(
          boxes.single.height, greaterThanOrEqualTo(ruby['height'] as double));
    });

    testWidgets('an out-of-range or empty range yields nothing',
        (tester) async {
      final box = await _pump(tester, '<p>Some plain text.</p>');
      expect(box.getBoxesForCharRange(500, 600), isEmpty);
      expect(box.getBoxesForCharRange(3, 3), isEmpty);
      expect(box.getBoxesForCharRange(0, 4), isNotEmpty);
    });
  });

  group('text-overflow: ellipsis', () {
    testWidgets('a box too narrow for any character shows only the ellipsis',
        (tester) async {
      final box = await _pump(
        tester,
        '<div style="overflow:hidden;text-overflow:ellipsis;'
        'white-space:nowrap">Truncated heading</div>',
        width: 10,
      );
      final lines =
          box.debugLineFragments().where((f) => f['type'] == 'text').toList();
      expect(lines, hasLength(1));
      expect(lines.single['text'], '…');
      expect(lines.single['ellipsisVisibleLength'], 0);
      // The ellipsis glyph is not a source character: no box for char 0.
      expect(box.getBoxesForCharRange(0, 16), isEmpty);
    });
  });

  group('TextPainter layout hooks', () {
    late int layouts;
    late int lineLayouts;

    setUp(() {
      layouts = 0;
      lineLayouts = 0;
      HyperRenderDebugHooks.onTextPainterLayout = () => layouts++;
      HyperRenderDebugHooks.onLineLayoutTextPainter = () => lineLayouts++;
    });

    tearDown(() {
      HyperRenderDebugHooks.onTextPainterLayout = null;
      HyperRenderDebugHooks.onLineLayoutTextPainter = null;
    });

    testWidgets('the bounded breaker shapes a bounded amount per line',
        (tester) async {
      // break-all keeps this off the single-pass native path, so it measures
      // candidate prefixes line by line.
      final text = 'あいうえおかきくけこ' * 500; // 5,000 characters
      final box = await _pump(
        tester,
        '<p style="word-break:break-all"><b>注</b>$text</p>',
      );
      final lines = box
          .debugLineFragments()
          .map((f) => f['lineIndex'] as int)
          .toSet()
          .length;
      expect(lines, greaterThan(200));
      expect(lineLayouts, greaterThan(0), reason: 'hook should fire');
      // A constant number of candidate layouts per line, not a number that
      // grows with the remaining text.
      expect(lineLayouts, lessThanOrEqualTo(lines * 4 + 20));
      expect(layouts, greaterThanOrEqualTo(lineLayouts));
    });

    testWidgets('hooks are silent when unset', (tester) async {
      HyperRenderDebugHooks.onTextPainterLayout = null;
      HyperRenderDebugHooks.onLineLayoutTextPainter = null;
      final before = layouts + lineLayouts;
      await _pump(tester, '<p>${'word ' * 200}</p>');
      expect(layouts + lineLayouts, before);
    });

    testWidgets('intrinsic measurement of a long paragraph is bounded',
        (tester) async {
      final box = await _pump(
        tester,
        '<table><tr><td><b>x</b> ${'あいうえお' * 400}</td></tr></table>',
      );
      layouts = 0;
      final max = box.getMaxIntrinsicWidth(double.infinity);
      expect(max.isFinite, isTrue);
      expect(layouts, lessThan(2000));
    });
  });
}
