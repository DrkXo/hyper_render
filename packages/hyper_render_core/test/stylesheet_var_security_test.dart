import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_core/hyper_render_core.dart';

/// Stylesheet var() is reachable from untrusted HTML (<style> is extracted
/// before sanitization), so substitution must stay bounded and must not
/// smuggle values past the per-property validators.
void main() {
  BlockNode resolve(String css) {
    final p = BlockNode.p(children: [TextNode('t')]);
    StyleResolver()
      ..parseCss(css)
      ..resolveStyles(DocumentNode(children: [p]));
    return p;
  }

  String bomb({required int refs, required int depth, required String use}) {
    final b = StringBuffer(':root { --l0: 1px;');
    for (var i = 1; i <= depth; i++) {
      b.write('--l$i: ${List.filled(refs, 'var(--l${i - 1})').join(' ')};');
    }
    return '$b } p { $use: var(--l$depth); }';
  }

  test('exponential expansion is capped, fast, and ignored', () {
    // 10 refs × 10 levels would expand to ~10^10 characters uncapped.
    final sw = Stopwatch()..start();
    final p = resolve(bomb(refs: 10, depth: 10, use: 'font-family'));
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    expect(p.style.fontFamily, isNot(contains('1px 1px 1px 1px')));
    expect(p.style.fontFamily ?? '', hasLength(lessThan(16 * 1024 + 1)));
  });

  test('a bomb does not affect other declarations on the element', () {
    final p = resolve('${bomb(refs: 8, depth: 8, use: 'font-family')} '
        'p { color: #00ff00; }');
    expect(p.style.color, const Color(0xFF00FF00));
  });

  test('reference cycles terminate', () {
    final sw = Stopwatch()..start();
    resolve(':root { --a: var(--b); --b: var(--a); } '
        'p { color: var(--a); width: var(--a); }');
    resolve(':root { --a: var(--a); } p { color: var(--a, #ff0000); }');
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  group('background URLs follow the <img src> scheme policy', () {
    const blocked = [
      'javascript:alert(1)',
      'JaVaScRiPt:alert(1)',
      'vbscript:x',
      'data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=',
      'data:text/html,x',
      'file:///etc/passwd',
    ];
    for (final url in blocked) {
      test(url, () {
        for (final css in [
          'p { background-image: url($url); }',
          'p { background: url($url); }',
          ':root { --bg: url($url); } p { background-image: var(--bg); }',
        ]) {
          expect(resolve(css).style.backgroundImage, isNull, reason: css);
        }
        final inline = BlockNode.p(children: [TextNode('t')])
          ..attributes['style'] = 'background-image: url($url)';
        StyleResolver().resolveStyles(DocumentNode(children: [inline]));
        expect(inline.style.backgroundImage, isNull, reason: 'inline');
      });
    }
  });

  test('a safe URL still resolves through var()', () {
    final p = resolve(':root { --bg: url(https://example.com/a.png); } '
        'p { background-image: var(--bg); }');
    expect(p.style.backgroundImage, contains('https://example.com/a.png'));
  });

  test('a value that resolves to nothing is ignored, not applied empty', () {
    final p = resolve('p { font-family: Georgia; } '
        'p { font-family: var(--undefined); }');
    expect(p.style.fontFamily, 'Georgia');
  });
}
