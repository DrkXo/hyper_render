// Layout fuzz: the parser fuzz suite only parses, so a hang or crash in the
// line breaker would never surface there. This lays mutated documents out at
// awkward widths (zero, one pixel, a prime, and a normal one) and asserts the
// render object finishes with a finite size and throws nothing.
//
// Same fixed-seed approach as parser_fuzz_test.dart: a failing mutant is
// printed and should be pinned as its own regression test.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';

const _longWord = 'Supercalifragilisticexpialidocious';
const _cjk = '日本語のテキストは行末で適切に折り返される必要があります。';

const _seeds = <String>[
  '<p>Hello <b>world</b>, $_longWord and a <a href="#">link that wraps</a>.</p>',
  '<p>$_cjk$_cjk$_cjk</p>',
  '<p><b>注意：</b>$_cjk$_cjk Latin words after CJK text follow.</p>',
  '<p style="direction:rtl">هذا نص عربي طويل يجب أن يلتف بشكل صحيح</p>',
  '<div><img src="a.png" style="float:left;width:90px;height:50px">'
      '<p>$_longWord $_longWord text beside a float $_cjk</p></div>',
  '<p style="word-break:break-all">$_longWord $_longWord</p>',
  '<p style="text-align:center">centered <i>inline</i> text that wraps over lines</p>',
  '<ul><li>$_longWord item</li><li>$_cjk</li></ul>',
  '<table><tr><td>$_cjk</td><td><b>x</b> $_longWord</td></tr></table>',
  '<div style="padding:0 40px"><blockquote>$_longWord $_cjk</blockquote></div>',
];

typedef _Mutator = String Function(String input, Random rng);

String _delete(String s, Random rng) {
  if (s.length < 2) return s;
  final i = rng.nextInt(s.length);
  return s.replaceRange(i, i + 1, '');
}

String _insert(String s, Random rng) {
  const chars = '<>"\'&/{}  ​注ا';
  final i = rng.nextInt(s.length + 1);
  return s.replaceRange(i, i, chars[rng.nextInt(chars.length)]);
}

String _duplicate(String s, Random rng) {
  if (s.length < 4) return s;
  final start = rng.nextInt(s.length - 2);
  final end = start + 1 + rng.nextInt(min(60, s.length - start - 1));
  return s.replaceRange(start, start, s.substring(start, end));
}

String _truncate(String s, Random rng) =>
    s.isEmpty ? s : s.substring(0, rng.nextInt(s.length));

const List<_Mutator> _mutators = [_delete, _insert, _duplicate, _truncate];

String _mutate(String seed, Random rng) {
  var out = seed;
  for (var i = 0; i < 3; i++) {
    out = _mutators[rng.nextInt(_mutators.length)](out, rng);
  }
  return out;
}

void main() {
  final rng = Random(20261008);
  final mutants = <String>[
    ..._seeds,
    for (final seed in _seeds)
      for (var i = 0; i < 4; i++) _mutate(seed, rng),
  ];

  for (final width in const [0.0, 1.0, 37.0, 300.0]) {
    testWidgets('layout at ${width}px never throws and stays finite',
        (tester) async {
      for (final html in mutants) {
        final doc = HtmlAdapter().parse(html);
        StyleResolver().resolveStyles(doc);
        await tester.pumpWidget(MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: HyperRenderWidget(document: doc),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull, reason: html);
        final box = tester.renderObject<RenderBox>(
          find.byType(HyperRenderWidget).first,
        );
        expect(box.size.width.isFinite, isTrue, reason: html);
        expect(box.size.height.isFinite, isTrue, reason: html);
        expect(box.size.height, greaterThanOrEqualTo(0), reason: html);
      }
    });
  }
}
