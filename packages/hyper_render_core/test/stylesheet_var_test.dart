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

  group('other csslib terms whose span drops the function name', () {
    test('url() in a stylesheet rule', () {
      expect(
          resolve('p { background-image: url(https://e.com/a.png); }')
              .style
              .backgroundImage,
          'https://e.com/a.png');
      expect(
          resolve("p { background: url('https://e.com/b.png'); }")
              .style
              .backgroundImage,
          'https://e.com/b.png');
    });

    test('calc() in a stylesheet rule, with and without var()', () {
      expect(resolve('p { width: calc(100px - 20px); }').style.width, 80);
      expect(
          resolve(':root { --x: 5px; } p { width: calc(10px + var(--x)); }')
              .style
              .width,
          15);
    });
  });

  group(':root matches only the document root', () {
    test('a descendant override of a :root variable is inherited', () {
      final span = InlineNode(tagName: 'span', children: [TextNode('s')]);
      final p = BlockNode.p(children: [span])..attributes['class'] = 'x';
      StyleResolver()
        ..parseCss(':root { --c: #ff0000; } .x { --c: #0000ff; } '
            'span { color: var(--c); }')
        ..resolveStyles(DocumentNode(children: [p]));
      expect(span.style.color, const Color(0xFF0000FF));
    });

    test(':root font-size does not compound per level', () {
      final span = InlineNode(tagName: 'span', children: [TextNode('s')]);
      final p = BlockNode.p(children: [span]);
      final doc = DocumentNode(children: [p]);
      StyleResolver()
        ..parseCss(':root { font-size: 125%; }')
        ..resolveStyles(doc);
      expect(doc.style.fontSize, 20); // 125% of the 16px default
      expect(span.style.fontSize, 20,
          reason: 'inherited, not re-applied as 125% at every level');
    });
  });

  group('cascade order — custom properties resolve before var()', () {
    BlockNode resolveX(String css, {String? inline}) {
      final p = BlockNode.p(children: [TextNode('t')]);
      p.attributes['class'] = 'x';
      if (inline != null) p.attributes['style'] = inline;
      StyleResolver()
        ..parseCss(css)
        ..resolveStyles(DocumentNode(children: [p]));
      return p;
    }

    test('definition in a higher-specificity rule', () {
      final p = resolveX('p { color: var(--c); } .x { --c: #0000ff; }');
      expect(p.style.color, const Color(0xFF0000FF));
    });

    test('definition after use in the same rule', () {
      final p = resolveX('p { color: var(--c); --c: #0000ff; }');
      expect(p.style.color, const Color(0xFF0000FF));
    });

    test('a lower-specificity definition does not win mid-cascade', () {
      // Rules apply in specificity order: p{--c:red}, then .x{color},
      // then #id-less .x.x{--c:blue}. color must see the FINAL --c.
      final p = resolveX('p { --c: #ff0000; } .x { color: var(--c); } '
          '.x.x { --c: #0000ff; }');
      expect(p.style.color, const Color(0xFF0000FF));
    });

    test('inline and !important definitions', () {
      expect(
        resolveX('p { color: var(--c); }', inline: '--c: #0000ff').style.color,
        const Color(0xFF0000FF),
      );
      expect(
        resolveX('p { color: var(--c); } p { --c: #0000ff !important; }',
                inline: '--c: #ff0000')
            .style
            .color,
        const Color(0xFF0000FF),
      );
    });

    test('children inherit the final value', () {
      final span = InlineNode(tagName: 'span', children: [TextNode('s')]);
      final p = BlockNode.p(children: [span]);
      p.attributes['class'] = 'x';
      StyleResolver()
        ..parseCss('span { color: var(--c); } p { --c: #ff0000; } '
            '.x { --c: #0000ff; }')
        ..resolveStyles(DocumentNode(children: [p]));
      expect(span.style.color, const Color(0xFF0000FF));
    });
  });

  group('customPropertyOverrides (DevTools live edit)', () {
    BlockNode resolveWith(String css, Map<String, String> overrides) {
      final p = BlockNode.p(children: [TextNode('t')]);
      p.attributes['style'] = '--inline: 1px';
      StyleResolver()
        ..customPropertyOverrides = overrides
        ..parseCss(css)
        ..resolveStyles(DocumentNode(children: [p]));
      return p;
    }

    test('replaces a :root definition', () {
      final p = resolveWith(
          ':root { --c: #ff0000; } p { color: var(--c); }', {'--c': '#0000ff'});
      expect(p.style.color, const Color(0xFF0000FF));
    });

    test('applies to a var defined and used in the same rule', () {
      // A trailing `* { --c: … !important }` cannot do this: var() is
      // substituted during the normal pass, before !important runs.
      final p = resolveWith(
          'p { --c: #ff0000; color: var(--c); }', {'--c': '#0000ff'});
      expect(p.style.color, const Color(0xFF0000FF));
    });

    test('applies to inline custom properties', () {
      final p = resolveWith('', {'--inline': '9px'});
      expect(p.style.customProperties['--inline'], '9px');
    });

    test('leaves undeclared variables to their fallback', () {
      final p = resolveWith(
          'p { color: var(--nope, #00ff00); }', {'--other': '#0000ff'});
      expect(p.style.color, const Color(0xFF00FF00));
    });
  });
}
