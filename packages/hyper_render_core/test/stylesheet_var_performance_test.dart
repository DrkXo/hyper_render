import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_core/hyper_render_core.dart';

/// A Bootstrap-5-style stylesheet: hundreds of :root custom properties and
/// var() in most rules. Defining variables must not make every element pay
/// O(#variables) — before the fixes this was ~15× the var-free cost
/// (`:root` matched every element, and each element copied the full map).
void main() {
  String stylesheet({required bool withVars}) {
    final css = StringBuffer(':root {');
    if (withVars) {
      for (var i = 0; i < 300; i++) {
        css.write('--bs-v$i: ${i}px;');
      }
    }
    css.write('--bs-body-color: #212529; }');
    for (var i = 0; i < 400; i++) {
      css.write('.c$i { margin: var(--bs-v${i % 300}, 1px); '
          'color: var(--bs-body-color); }');
    }
    return css.toString();
  }

  int fastestMs(String css) {
    var best = 1 << 30;
    for (var run = 0; run < 5; run++) {
      final doc = DocumentNode(children: [
        for (var i = 0; i < 2000; i++)
          BlockNode.p(children: [TextNode('para $i')])
            ..attributes['class'] = 'c${i % 400}',
      ]);
      final sw = Stopwatch()..start();
      StyleResolver()
        ..parseCss(css)
        ..resolveStyles(doc);
      if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
    }
    return best;
  }

  test('300 :root variables cost about the same as none (2000 elements)', () {
    final without = fastestMs(stylesheet(withVars: false));
    final withVars = fastestMs(stylesheet(withVars: true));
    // Ratio, not absolute time, so slow CI runners don't flake. Measured
    // ~1.4× after the fixes, ~15× before.
    expect(withVars, lessThan((without + 5) * 5),
        reason: 'with vars ${withVars}ms vs without ${without}ms');
  });
}
