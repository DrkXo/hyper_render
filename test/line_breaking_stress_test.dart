// Stress, boundary and termination tests for the line breaker.
//
// The line breaker bounds how much text it shapes per line (for performance on
// very long paragraphs), which is exactly the kind of optimisation that breaks
// on inputs the happy-path tests never produce: zero-width boxes, padding wider
// than the container, floats wider than the container, glyphs narrower than the
// bound assumes, and shrink-to-fit parents asking for intrinsic sizes.
//
// Every test here must terminate (the default 30 s test timeout is the hang
// detector), throw nothing, and keep every character exactly once.
//
// Flutter's test font (Ahem) makes every glyph 1em wide, which hides any bug
// that depends on narrow glyphs. `textScaler` below 1 makes glyphs narrower
// without changing the em the layout bounds are computed from, so it is how
// those cases are reached.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';

String _words(int count) => List.generate(
      count,
      (i) => const [
        'lorem',
        'ipsum',
        'dolor',
        'sit',
        'amet',
        'consectetur'
      ][i % 6],
    ).join(' ');

const _cjk = '日本語のテキストは行末で適切に折り返される必要があります。';
const _arabic = 'هذا نص عربي طويل يجب أن يلتف بشكل صحيح عبر عدة أسطر ';

Future<RenderHyperBox> _pump(
  WidgetTester tester,
  String html, {
  double width = 300,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
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
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  return tester.renderObject<RenderHyperBox>(
    find.byType(HyperRenderWidget).first,
  );
}

List<Map<String, dynamic>> _textFragments(RenderHyperBox box) =>
    box.debugLineFragments().where((f) => f['type'] == 'text').toList();

/// All text on the lines, in order, with whitespace removed.
String _flatText(RenderHyperBox box) => _textFragments(box)
    .map((f) => f['text'] as String)
    .join()
    .replaceAll(RegExp(r'\s+'), '');

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), '');

void main() {
  group('Narrow glyphs do not under-fill lines', () {
    // 800px at 8px per glyph is 100 characters per line. A bound derived from
    // the first 32 characters containing CJK (0.75em per glyph) used to cut
    // the first line at about 83.
    testWidgets('Latin text after a single CJK character', (tester) async {
      final text = _words(120);
      final box = await _pump(
        tester,
        '<p><b>注</b>日本語 $text</p>',
        width: 800,
        textScale: 0.5,
      );
      final lines = <int, double>{};
      for (final f in _textFragments(box)) {
        final line = f['lineIndex'] as int;
        final right = (f['offsetX'] as double) + (f['width'] as double);
        if (right > (lines[line] ?? 0)) lines[line] = right;
      }
      final ordered = lines.keys.toList()..sort();
      expect(ordered.length, greaterThan(2));
      // Every line but the last reaches within one long word (11 glyphs at
      // 8px) of the right edge.
      for (final line in ordered.take(ordered.length - 1)) {
        expect(800 - lines[line]!, lessThan(11 * 8 + 1),
            reason: 'line $line stops ${800 - lines[line]!}px short');
      }
    });

    testWidgets('Latin text beside a float', (tester) async {
      final box = await _pump(
        tester,
        '<div><img src="x" style="float:left;width:100px;height:40px">'
        '<p>${_words(150)}</p></div>',
        width: 800,
        textScale: 0.5,
      );
      expect(_flatText(box), _squash(_words(150)));
    });
  });

  group('No characters are lost or duplicated', () {
    final samples = <String, String>{
      'unspaced latin': 'x' * 2000,
      'unspaced CJK': _cjk * 40,
      'spaced latin': _words(400),
      'arabic': _arabic * 10,
      'mixed scripts': '${_words(20)} ${_cjk * 3} ${_words(20)}',
    };
    for (final entry in samples.entries) {
      for (final width in const [1.0, 37.0, 300.0, 5000.0]) {
        testWidgets('${entry.key} at ${width.toInt()}px', (tester) async {
          final box =
              await _pump(tester, '<p>${entry.value}</p>', width: width);
          expect(tester.takeException(), isNull);
          expect(_flatText(box), _squash(entry.value));
        });
      }
    }

    testWidgets('after an inline element', (tester) async {
      final box = await _pump(
        tester,
        '<p><b>Note:</b> ${_words(300)}</p>',
      );
      expect(_flatText(box), _squash('Note: ${_words(300)}'));
    });

    testWidgets('CJK after an inline element', (tester) async {
      final box = await _pump(tester, '<p><b>注意：</b>${_cjk * 30}</p>');
      expect(_flatText(box), _squash('注意：${_cjk * 30}'));
    });
  });

  group('Terminates on degenerate geometry', () {
    for (final width in const [0.0, 0.5, 1.0]) {
      testWidgets('width $width', (tester) async {
        for (final html in [
          '<p>${'x' * 500}</p>',
          '<p>${_cjk * 20}</p>',
          '<p style="direction:rtl">${_arabic * 5}</p>',
          '<p><b>a</b> ${_words(50)}</p>',
          '<p style="word-break:break-all">${_words(30)}</p>',
        ]) {
          await _pump(tester, html, width: width);
          expect(tester.takeException(), isNull, reason: html);
        }
      });
    }

    testWidgets('padding wider than the container', (tester) async {
      final box = await _pump(
        tester,
        '<div style="padding:0 200px"><p>${_cjk * 20}</p></div>',
      );
      expect(tester.takeException(), isNull);
      expect(_flatText(box), _squash(_cjk * 20));
    });

    testWidgets('nested padding wider than the container', (tester) async {
      final box = await _pump(
        tester,
        '<div style="padding:0 120px"><div style="padding:0 120px">'
        '<p>${_words(60)}</p></div></div>',
      );
      expect(tester.takeException(), isNull);
      expect(_flatText(box), _squash(_words(60)));
    });

    testWidgets('a float wider than the container, then unspaced CJK',
        (tester) async {
      final box = await _pump(
        tester,
        '<div><img src="x" style="float:left;width:400px;height:40px">'
        '<p>${_cjk * 20}</p></div>',
      );
      expect(tester.takeException(), isNull);
      expect(_flatText(box), _squash(_cjk * 20));
    });

    testWidgets('floats on both sides leaving no room', (tester) async {
      final box = await _pump(
        tester,
        '<div><img src="x" style="float:left;width:150px;height:40px">'
        '<img src="y" style="float:right;width:150px;height:40px">'
        '<p>${_words(40)}</p></div>',
      );
      expect(tester.takeException(), isNull);
      expect(_flatText(box), _squash(_words(40)));
    });
  });

  group('Intrinsic sizes stay finite', () {
    // A shrink-to-fit parent asks for intrinsic widths. A long tail after an
    // inline element used to carry an estimated infinite width.
    for (final entry in {
      'table cell': '<table><tr><td><b>注</b> ${_cjk * 15}</td></tr></table>',
      'table cell, Latin': '<table><tr><td><b>x</b> ${_words(120)}</td></tr>'
          '</table>',
      'inline-block': '<div style="display:inline-block"><b>注</b> '
          '${_cjk * 15}</div>',
      'plain paragraph': '<p><b>x</b> ${_words(200)}</p>',
    }.entries) {
      testWidgets(entry.key, (tester) async {
        await _pump(tester, entry.value);
        expect(tester.takeException(), isNull);
        final boxes = tester
            .renderObjectList<RenderBox>(find.byType(HyperRenderWidget))
            .toList();
        expect(boxes, isNotEmpty);
        for (final box in boxes) {
          for (final w in [0.0, 1.0, 100.0, 300.0, double.infinity]) {
            final max = box.getMaxIntrinsicWidth(w);
            final min = box.getMinIntrinsicWidth(w);
            expect(max.isFinite, isTrue, reason: 'max intrinsic at $w');
            expect(min.isFinite, isTrue, reason: 'min intrinsic at $w');
            expect(min, lessThanOrEqualTo(max + 0.01));
          }
          expect(box.size.width.isFinite, isTrue);
          expect(box.size.height.isFinite, isTrue);
        }
      });
    }
  });

  group('Stress', () {
    testWidgets('one 200,000-character unspaced CJK paragraph', (tester) async {
      final text = (_cjk * 8000).substring(0, 200000);
      final stopwatch = Stopwatch()..start();
      final box = await _pump(tester, '<p>$text</p>');
      stopwatch.stop();
      expect(tester.takeException(), isNull);
      final lines = _textFragments(box).map((f) => f['lineIndex']).toSet();
      // 18 glyphs fit a 300px line at the test font size.
      expect(lines.length, inInclusiveRange(200000 ~/ 19, 200000 ~/ 17 + 50));
      // Generous ceiling: a quadratic breaker needs minutes here, a linear one
      // a couple of seconds. This is a hang guard, not a benchmark.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 60)));
    });

    // `word-break: break-all` keeps the text off the single-pass native path
    // (which would make this fast whatever the candidate bound is), so every
    // line goes through the bounded fallback breaker. Without the bound on the
    // candidate prefix each line re-shapes the whole remaining paragraph:
    // quadratic. That blocks the test isolate, so a regression shows up as the
    // run hanging until the job timeout, not as a clean failure. With the
    // bound it takes a couple of seconds.
    testWidgets('100,000 unspaced characters on the bounded fallback path',
        (tester) async {
      final text = (_cjk * 4000).substring(0, 100000);
      final box = await _pump(
        tester,
        '<p style="word-break:break-all"><b>注意：</b>$text</p>',
      );
      expect(tester.takeException(), isNull);
      final lines = _textFragments(box).map((f) => f['lineIndex']).toSet();
      expect(lines.length, inInclusiveRange(100000 ~/ 19, 100000 ~/ 17 + 50));
    });

    testWidgets('50,000 spaced Latin characters after an inline element',
        (tester) async {
      final text = _words(8000);
      final box = await _pump(tester, '<p><b>Note:</b> $text</p>');
      expect(tester.takeException(), isNull);
      expect(_flatText(box), _squash('Note: $text'));
    });

    testWidgets('thousands of short inline runs in one paragraph',
        (tester) async {
      final html = '<p>${List.generate(1500, (i) => '<b>w$i</b> ').join()}</p>';
      final box = await _pump(tester, html);
      expect(tester.takeException(), isNull);
      expect(_textFragments(box), isNotEmpty);
    });
  });
}
