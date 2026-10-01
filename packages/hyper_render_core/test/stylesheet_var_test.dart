import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_core/hyper_render_core.dart';

/// var() inside stylesheet rules (<style>, customCss). csslib hands these
/// over as VarUsage nodes whose span lacks the "var(" prefix; before the
/// fix they all resolved to nothing. Inline style="" is covered elsewhere.
void main() {
  BlockNode resolve(String css) {
    final p = BlockNode.p(children: [TextNode('t')]);
    StyleResolver()
      ..parseCss(css)
      ..resolveStyles(DocumentNode(children: [p]));
    return p;
  }

  test('inherited :root variable', () {
    final p = resolve(':root { --c: #ff0000; } p { color: var(--c); }');
    expect(p.style.color, const Color(0xFFFF0000));
  });

  test('fallback when undefined', () {
    final p = resolve('p { color: var(--nope, #00ff00); }');
    expect(p.style.color, const Color(0xFF00FF00));
  });

  test('length value and multi-term shorthand', () {
    final p = resolve(
        ':root { --s: 30px; --g: 7px; } p { font-size: var(--s); margin: 0 var(--g) 4px; }');
    expect(p.style.fontSize, 30);
    expect(p.style.margin.right, 7);
    expect(p.style.margin.bottom, 4);
  });

  test('nested var() fallback', () {
    final p =
        resolve(':root { --b: #0000ff; } p { color: var(--a, var(--b)); }');
    expect(p.style.color, const Color(0xFF0000FF));
  });
}
