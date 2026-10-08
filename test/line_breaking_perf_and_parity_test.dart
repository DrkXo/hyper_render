// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';
import 'package:hyper_render_core/hyper_render_core.dart'
    show HyperRenderDebugHooks;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Synthetic unspaced CJK sample (100 characters)
  const cjkSample =
      '此開卷第一回也作者自云因曾歷過一番夢幻之后故將真事隱去而借通靈之說撰此石頭記一書也故曰甄士隱云云但書中所記何事何人自又云今風塵碌碌一事無成忽念及當日所有之女子一一細考較去覺其行止見識皆出于我之上';

  group('Group 1: Intrinsic Widths in Shrink-to-Fit Contexts', () {
    testWidgets(
        'getMinIntrinsicWidth and getMaxIntrinsicWidth for long unspaced CJK fragment',
        (WidgetTester tester) async {
      // 1,000 characters of unspaced CJK
      final longText = cjkSample * 10;

      RenderHyperBox? hyperBox;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HyperRenderWidget(
            document: DocumentNode(
              children: [
                BlockNode(
                  tagName: 'p',
                  children: [TextNode(longText)],
                ),
              ],
            ),
          ),
        ),
      );

      final renderObject = tester.renderObject(find.byType(HyperRenderWidget));
      if (renderObject is RenderHyperBox) {
        hyperBox = renderObject;
      }
      expect(hyperBox, isNotNull);

      // CJK characters can break after each character. Min intrinsic width is
      // the width of a single character (~16px), not the full 1,000 chars.
      final minWidth = hyperBox!.getMinIntrinsicWidth(double.infinity);
      expect(minWidth, greaterThan(10.0));
      expect(minWidth, lessThan(30.0));

      // Max intrinsic width represents unwrapped single-line text width.
      // 1,000 CJK characters at default font size (16px) should be ~16,000px.
      // Must NOT be truncated or clamped to layout maxWidth.
      final maxWidth = hyperBox.getMaxIntrinsicWidth(double.infinity);
      expect(maxWidth, greaterThan(10000.0));
    });

    testWidgets('Shrink-to-fit context: table cell with unspaced CJK text',
        (WidgetTester tester) async {
      final text = cjkSample * 2; // 200 chars

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 500,
                  child: HyperRenderWidget(
                    document: DocumentNode(
                      children: [
                        BlockNode(
                          tagName: 'table',
                          style: ComputedStyle(width: 500),
                          children: [
                            BlockNode(
                              tagName: 'tr',
                              children: [
                                BlockNode(
                                  tagName: 'td',
                                  children: [TextNode(text)],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final renderObject =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      expect(renderObject.hasSize, isTrue);
      expect(renderObject.size.width, equals(500.0));
      expect(renderObject.size.height, greaterThan(0.0));
    });

    testWidgets(
        'Shrink-to-fit context: inline-block container with unspaced CJK text',
        (WidgetTester tester) async {
      final text = cjkSample * 2;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 600,
                  child: HyperRenderWidget(
                    document: DocumentNode(
                      children: [
                        BlockNode(
                          tagName: 'div',
                          style:
                              ComputedStyle(display: DisplayType.inlineBlock),
                          children: [TextNode(text)],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final renderObject =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      expect(renderObject.hasSize, isTrue);
      expect(renderObject.size.height, greaterThan(0.0));
      final lines = renderObject.debugLines();
      expect(lines.length, greaterThan(1));
    });
  });

  group('Group 2: Fast-Path Parity & Edge Case Coverage', () {
    testWidgets('Plain text wrapping parity', (WidgetTester tester) async {
      final text = cjkSample * 3; // 300 chars

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 400,
              child: HyperRenderWidget(
                document: DocumentNode(
                  children: [
                    BlockNode(
                      tagName: 'p',
                      children: [TextNode(text)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final box =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      final lines = box.debugLines();
      expect(lines.length, greaterThan(5));
      for (final line in lines) {
        expect(line['width'] as double, lessThanOrEqualTo(400.0));
        expect(line['height'] as double, greaterThan(0.0));
      }
    });

    testWidgets('text-align: justify layout', (WidgetTester tester) async {
      const latinText =
          'The quick brown fox jumps over the lazy dog and runs through the forest with great speed and agility. '
          'Every single animal in the meadow stopped to watch the astonishing performance of the graceful creatures.';

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              child: HyperRenderWidget(
                document: DocumentNode(
                  children: [
                    BlockNode(
                      tagName: 'p',
                      style: ComputedStyle(textAlign: HyperTextAlign.justify),
                      children: [TextNode(latinText)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final box =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      final lines = box.debugLines();
      expect(lines.length, greaterThan(2));
      // First line width within container
      expect(lines.first['width'] as double, lessThanOrEqualTo(300.0));
    });

    testWidgets(
        'text-overflow: ellipsis truncates on single line and does not multi-line wrap',
        (WidgetTester tester) async {
      final text = cjkSample * 5;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              child: HyperRenderWidget(
                document: DocumentNode(
                  children: [
                    BlockNode(
                      tagName: 'p',
                      style: ComputedStyle(
                        textOverflow: TextOverflow.ellipsis,
                        whiteSpace: 'nowrap',
                      ),
                      children: [TextNode(text)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final box =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      final lines = box.debugLines();
      // Ellipsis nowrap must remain on 1 single line
      expect(lines.length, equals(1));
      final lineFrags = box.debugLineFragments();
      expect(lineFrags, isNotEmpty);
      expect(
          lineFrags.any((f) => (f['text'] as String?)?.contains('…') ?? false),
          isTrue);
    });

    testWidgets('non-default textScaler scaling', (WidgetTester tester) async {
      final text = cjkSample * 2;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: SizedBox(
                width: 400,
                child: HyperRenderWidget(
                  document: DocumentNode(
                    children: [
                      BlockNode(
                        tagName: 'p',
                        children: [TextNode(text)],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final box =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      final lines = box.debugLines();
      expect(lines.length, greaterThan(3));
      // At 1.5x scale, line height is noticeably larger than baseline 16px font
      expect(lines.first['height'] as double, greaterThan(20.0));
    });

    testWidgets('mixed CJK and Latin text wrapping',
        (WidgetTester tester) async {
      const mixedText =
          '第一章 Introduction to Ancient Stones. 在古代中國，這是一段測試文本，including various English terms, numbers 12345, '
          'and mixed punctuation！更多詳細內容請參見後續章節。';
      final text = mixedText * 3;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 350,
              child: HyperRenderWidget(
                document: DocumentNode(
                  children: [
                    BlockNode(
                      tagName: 'p',
                      children: [TextNode(text)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final box =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      final lines = box.debugLines();
      expect(lines.length, greaterThan(3));
      for (final line in lines) {
        expect(line['width'] as double, lessThanOrEqualTo(350.0));
      }
    });

    testWidgets(
        'float starting partway through paragraph triggers fallback path properly',
        (WidgetTester tester) async {
      // Paragraph with lead-in text, a floating box, then trailing text
      const textBefore = cjkSample;
      final textAfter = cjkSample * 2;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 500,
              child: HyperRenderWidget(
                document: DocumentNode(
                  children: [
                    BlockNode(
                      tagName: 'p',
                      children: [
                        TextNode(textBefore),
                        AtomicNode(
                          tagName: 'img',
                          style: ComputedStyle(
                            float: HyperFloat.left,
                            width: 100,
                            height: 80,
                          ),
                        ),
                        TextNode(textAfter),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final box =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      expect(box.hasSize, isTrue);
      final lines = box.debugLines();
      expect(lines.length, greaterThan(5));
      // Text alongside 100px float wraps narrower (width <= 400.0) than the full 500px container
      expect(lines.any((l) => (l['width'] as double) <= 400.0), isTrue);
    });

    testWidgets(
        'text after an inline lead-in wraps into multiple lines without single-line tail overflow (Latin & CJK)',
        (WidgetTester tester) async {
      final samples = <String, String>{
        'Latin':
            '<p><b>Note:</b> ${'lorem ipsum dolor sit amet consectetur ' * 10}</p>',
        'CJK': '<p><b>注意：</b>${'日本語のテキストは行末で適切に折り返される必要があります。' * 6}</p>',
      };

      for (final entry in samples.entries) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 300,
                child:
                    HyperViewer(html: entry.value, mode: HyperRenderMode.sync),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        final box = tester.renderObject(find.byType(HyperRenderWidget).first)
            as RenderHyperBox;
        final lines = box.debugLines();
        expect(lines.length, greaterThan(4),
            reason:
                '${entry.key} text after lead-in must wrap into multiple lines');

        final frags =
            box.debugLineFragments().where((f) => f['type'] == 'text').toList();
        for (final f in frags) {
          final text = (f['text'] as String).trimRight();
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: const TextStyle(fontSize: 16),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final x = f['offsetX'] as double;
          expect(
            x + painter.width,
            lessThanOrEqualTo(300.5),
            reason:
                '${entry.key} line fragment "${f['text']}" on line ${f['lineIndex']} runs past the box (x: $x, width: ${painter.width})',
          );
        }
      }
    });
  });

  group('Group 3: Selection and Hit-Testing Continuity', () {
    testWidgets('globalOffset continuity across sliced line fragments',
        (WidgetTester tester) async {
      final text = cjkSample * 3; // 300 chars

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 350,
              child: HyperRenderWidget(
                document: DocumentNode(
                  children: [
                    BlockNode(
                      tagName: 'p',
                      children: [TextNode(text)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final box =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      final fragments = box.debugLineFragments();
      expect(fragments.length, greaterThan(3));

      // Verify strict continuity: fragment[i].charEnd == fragment[i+1].charStart
      int expectedOffset = 0;
      for (var i = 0; i < fragments.length; i++) {
        final frag = fragments[i];
        final start = frag['charStart'] as int;
        final end = frag['charEnd'] as int;
        expect(start, equals(expectedOffset),
            reason:
                'Fragment $i charStart should match prior offset with zero gaps');
        expect(end, greaterThan(start));
        expectedOffset = end;
      }
      expect(expectedOffset, equals(text.length));
    });

    testWidgets('getBoxesForCharRange across line boundaries',
        (WidgetTester tester) async {
      final text = cjkSample * 2;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              child: HyperRenderWidget(
                document: DocumentNode(
                  children: [
                    BlockNode(
                      tagName: 'p',
                      children: [TextNode(text)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final box =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      // Select characters 10 through 60 (spanning across lines)
      final boxes = box.getBoxesForCharRange(10, 60);
      expect(boxes, isNotEmpty);
      expect(boxes.length, greaterThanOrEqualTo(2),
          reason:
              'Range crossing line boundary must produce boxes for each line');
      for (final rect in boxes) {
        expect(rect.width, greaterThan(0.0));
        expect(rect.height, greaterThan(0.0));
      }
    });

    testWidgets('getSelectedText returns exact unbroken substring',
        (WidgetTester tester) async {
      final text = cjkSample * 2;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              child: HyperRenderWidget(
                selectable: true,
                document: DocumentNode(
                  children: [
                    BlockNode(
                      tagName: 'p',
                      children: [TextNode(text)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final box =
          tester.renderObject(find.byType(HyperRenderWidget)) as RenderHyperBox;
      box.startSelectionAt(const Offset(10, 10));
      box.extendSelectionTo(const Offset(250, 80));

      final selected = box.getSelectedText();
      expect(selected, isNotNull);
      expect(selected!.isNotEmpty, isTrue);
      // The extracted text must be a genuine substring of the source text
      expect(text.contains(selected), isTrue);
    });
  });

  group('Group 4: Deterministic Performance Test (CI-Safe)', () {
    testWidgets(
        'TextPainter.layout call-counting on 50-line unspaced paragraph',
        (WidgetTester tester) async {
      final text = cjkSample * 15; // ~1,500 characters, ~50 lines

      int lineLayoutCalls = 0;
      HyperRenderDebugHooks.onLineLayoutTextPainter = () {
        lineLayoutCalls++;
      };

      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 500,
                child: HyperRenderWidget(
                  document: DocumentNode(
                    children: [
                      BlockNode(
                        tagName: 'p',
                        children: [TextNode(text)],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final box = tester.renderObject(find.byType(HyperRenderWidget))
            as RenderHyperBox;
        final lines = box.debugLines();
        expect(lines.length, greaterThan(35));

        // In the old O(N^2) line-by-line breaker, lineLayoutCalls was >= lines.length (40-50+ calls).
        // Under the native multi-line fast path, lineLayoutCalls is exactly 1 (single multiPainter.layout call)!
        expect(lineLayoutCalls, equals(1),
            reason:
                'Native multi-line fast path must perform exactly 1 TextPainter pass for line breaking');
      } finally {
        HyperRenderDebugHooks.onLineLayoutTextPainter = null;
      }
    });

    testWidgets(
        'Scaling ratio between N and 2N demonstrates linear O(N) scaling',
        (WidgetTester tester) async {
      // Compare 1,500 characters (N) vs 3,000 characters (2N)
      final textN = cjkSample * 15; // 1,500 chars
      final text2N = cjkSample * 30; // 3,000 chars

      int callsN = 0;
      int calls2N = 0;

      // Reset cache before measuring N so tests are independent of earlier runs
      RenderHyperBox.setGlobalTextCacheSize(1);
      RenderHyperBox.setGlobalTextCacheSize(5000);

      HyperRenderDebugHooks.onTextPainterLayout = () => callsN++;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 500,
              child: HyperRenderWidget(
                key: const ValueKey('N'),
                document: DocumentNode(
                  children: [
                    BlockNode(
                      tagName: 'p',
                      children: [TextNode(textN)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      HyperRenderDebugHooks.onTextPainterLayout = null;

      // Reset cache before measuring 2N
      RenderHyperBox.setGlobalTextCacheSize(1);
      RenderHyperBox.setGlobalTextCacheSize(5000);

      HyperRenderDebugHooks.onTextPainterLayout = () => calls2N++;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 500,
              child: HyperRenderWidget(
                key: const ValueKey('2N'),
                document: DocumentNode(
                  children: [
                    BlockNode(
                      tagName: 'p',
                      children: [TextNode(text2N)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      HyperRenderDebugHooks.onTextPainterLayout = null;

      // In an O(N) linear line-breaker, doubling the input (N -> 2N) roughly doubles operations (ratio ~2.0).
      // In an O(N^2) quadratic line-breaker, doubling the input quadruples operations (ratio >= 3.5 - 4.0).
      expect(callsN, greaterThan(0));
      expect(calls2N, greaterThan(0));
      final ratio = calls2N / callsN;
      expect(ratio, inInclusiveRange(1.5, 2.5),
          reason:
              'Scaling ratio ($ratio) between N ($callsN calls) and 2N ($calls2N calls) must be linear O(N) (~2.0), not quadratic O(N^2)');
    });
  });
}
