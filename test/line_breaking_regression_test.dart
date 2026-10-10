// Line-breaking regressions found while reviewing #29: on a 300px box the
// wrapped lines must stay inside the box, RTL text must wrap, `word-break`
// must inherit, centered lines must center their visible glyphs, and a word
// that does not fit beside a float must move below it.
//
// The test font is Ahem: every glyph is a 16px square at the default size, so
// a line's visible width is predictable and measured independently here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';

const double _boxWidth = 300;

Future<RenderHyperBox> _pump(WidgetTester tester, String html) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: _boxWidth,
        child: HyperViewer(html: html, mode: HyperRenderMode.sync),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  return tester.renderObject<RenderHyperBox>(
    find.byType(HyperRenderWidget).first,
  );
}

List<Map<String, dynamic>> _textLines(RenderHyperBox box) =>
    box.debugLineFragments().where((f) => f['type'] == 'text').toList();

/// Width of [text] without its trailing spaces, measured from scratch rather
/// than trusting the fragment's own reported width.
double _visibleWidth(String text) {
  final painter = TextPainter(
    text: TextSpan(
      text: text.trimRight(),
      style: const TextStyle(fontSize: 16),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

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

void main() {
  group('Line breaking stays inside the box', () {
    final samples = <String, String>{
      'latin': '<p>${_words(40)}</p>',
      'cjk': '<p>${'日本語のテキストは行末で適切に折り返される必要があります' * 4}</p>',
      'rtl':
          '<p style="direction:rtl">${'هذا نص عربي طويل يجب أن يلتف ' * 4}</p>',
      'text after an inline element': '<p><b>Note:</b> ${_words(40)}</p>',
      'cjk after an inline element':
          '<p><b>注意：</b>${'日本語のテキストは行末で適切に' * 6}</p>',
      'beside a float': '<div><img src="x" '
          'style="float:left;width:120px;height:40px">${_words(40)}</div>',
      'break-all': '<p style="word-break:break-all">'
          'Supercalifragilistic expialidocious antidisestablishmentarianism</p>',
    };

    for (final entry in samples.entries) {
      testWidgets(entry.key, (tester) async {
        final box = await _pump(tester, entry.value);
        final lines = _textLines(box);
        expect(lines.length, greaterThan(2), reason: 'sample should wrap');
        for (final f in lines) {
          final x = f['offsetX'] as double;
          final text = f['text'] as String;
          expect(
            x + _visibleWidth(text),
            lessThanOrEqualTo(_boxWidth + 0.5),
            reason: 'line ${f['lineIndex']} "$text" runs past the box',
          );
        }
      });
    }
  });

  testWidgets('RTL paragraph wraps without one-glyph lines', (tester) async {
    final box = await _pump(
      tester,
      '<p style="direction:rtl">${'هذا نص عربي طويل يجب أن يلتف ' * 4}</p>',
    );
    final lines = _textLines(box);
    // 116 chars at 18 glyphs per line: at least 7 lines, none of them a lone
    // glyph (the old x-probe read the RTL painter from the wrong end).
    expect(lines.length, greaterThanOrEqualTo(7));
    for (final f in lines.take(lines.length - 1)) {
      expect((f['text'] as String).trim().length, greaterThan(8));
    }
  });

  testWidgets('word-break: break-all on <p> reaches its text and fills lines',
      (tester) async {
    const text = 'consectetur consectetur consectetur consectetur';
    final normal = _textLines(await _pump(tester, '<p>$text</p>'));
    // Without break-all each 11-char word fits a line but two do not.
    expect(normal.first['text'], 'consectetur');

    final box = await _pump(
      tester,
      '<p style="word-break:break-all">$text</p>',
    );
    final lines = _textLines(box);
    // break-all fills each line to 18 glyphs, mid-word. It used to be ignored
    // because word-break was not inherited from the <p> by its text node.
    expect(lines.first['text'], 'consectetur consec');
    expect(lines.length, 3);
  });

  testWidgets('a word wider than the line breaks after as many chars as fit',
      (tester) async {
    final box = await _pump(
      tester,
      '<p>pneumonoultramicroscopicsilicovolcanoconiosis</p>',
    );
    final lines = _textLines(box);
    expect(lines.first['text'], 'pneumonoultramicro');
    expect((lines.first['text'] as String).length, 18);
  });

  testWidgets('centered lines center their visible glyphs', (tester) async {
    final box = await _pump(
      tester,
      '<p style="text-align:center">${_words(20)}</p>',
    );
    for (final f in _textLines(box)) {
      final x = f['offsetX'] as double;
      final text = f['text'] as String;
      expect(text, isNot(endsWith(' ')));
      expect(x * 2 + _visibleWidth(text), closeTo(_boxWidth, 1.0),
          reason: '"$text" is off-center');
    }
  });

  testWidgets('a word that does not fit beside a float moves below it',
      (tester) async {
    final box = await _pump(
      tester,
      '<div><img src="x" style="float:left;width:120px;height:40px">'
      '${_words(40)}</div>',
    );
    final lines = _textLines(box);
    // "consectetur" (176px) does not fit in the 172px beside the float. It
    // used to be split as "c" / "onsectetur". Every line must hold whole words.
    const vocabulary = {
      'lorem',
      'ipsum',
      'dolor',
      'sit',
      'amet',
      'consectetur'
    };
    for (final f in lines) {
      for (final word in (f['text'] as String).trim().split(' ')) {
        expect(vocabulary, contains(word),
            reason: 'line ${f['lineIndex']} splits a word: "${f['text']}"');
      }
    }
    // The first "consectetur" starts the first line below the float.
    final word = lines.firstWhere(
      (f) => (f['text'] as String).contains('consectetur'),
    );
    expect((word['text'] as String).startsWith('consectetur'), isTrue);
    expect(word['offsetX'], 0.0);
    expect(word['lineTop'] as double, greaterThanOrEqualTo(40.0));
  });

  testWidgets('copying across a wrapped line keeps the space', (tester) async {
    const html = '<p>The quick brown fox jumps over the lazy dog again '
        'and again and again until the line has wrapped twice.</p>';
    final box = await _pump(tester, html);
    final lines = _textLines(box);
    final firstLineText = (lines.first['text'] as String).trimRight();
    expect(firstLineText, isNot(endsWith(' ')));
    box.selection = const HyperTextSelection(start: 0, end: 30);
    expect(box.getSelectedText(), 'The quick brown fox jumps over');
  });

  testWidgets('spaces at the start of a line are removed', (tester) async {
    final box = await _pump(
      tester,
      '<p>\n   first line<br>   second line<br> <b>third</b></p>'
      // "Bold with nested" is 16 glyphs, so " inside" moves whole to the
      // next line, which must not start with its space.
      '<p><b>Bold with <i>nested</i> inside</b> and back</p>',
    );
    final lines = _textLines(box);
    for (final f in lines.where((f) => f['offsetX'] == 0.0)) {
      expect((f['text'] as String).startsWith(' '), isFalse,
          reason: 'line ${f['lineIndex']} starts with a space');
    }
    expect(lines.map((f) => f['text']),
        containsAll(['first line', 'second line', 'third', 'inside']));
  });

  testWidgets('right-aligned lines end flush, ignoring the trailing space',
      (tester) async {
    final box = await _pump(
      tester,
      '<p style="text-align:right">short line \n</p>',
    );
    final f = _textLines(box).single;
    final x = f['offsetX'] as double;
    expect(x + _visibleWidth(f['text'] as String), closeTo(_boxWidth, 0.5));
    expect(f['text'], 'short line');
  });

  testWidgets('text-overflow: ellipsis works on the first block of a document',
      (tester) async {
    // No preceding block, margin or padding: this block used to emit no
    // block-start fragment, so ellipsisDepth never rose and the text wrapped.
    final box = await _pump(
      tester,
      '<div style="overflow:hidden;text-overflow:ellipsis;'
      'white-space:nowrap">${_words(20)}</div>',
    );
    final lines = _textLines(box);
    expect(lines, hasLength(1));
    expect(lines.single['text'] as String, endsWith('\u2026'));
    expect(
      (lines.single['offsetX'] as double) +
          _visibleWidth(lines.single['text'] as String),
      lessThanOrEqualTo(_boxWidth + 0.5),
    );
  });

  testWidgets('a floated block does not add a phantom line height',
      (tester) async {
    const text = 'One two three four five six seven eight nine ten';
    final box = await _pump(
      tester,
      '<div style="float:left;width:150px">$text</div><p>$text</p>',
    );
    // Known gap: the floated div's text is laid out in normal flow. Its first
    // line must be one text line tall (16px at Ahem), not 24.
    final lines = _textLines(box);
    expect(lines[1]['lineTop'], 16.0);
  });
}
