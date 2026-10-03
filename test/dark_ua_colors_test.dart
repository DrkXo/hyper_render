// Issue #23: link / <pre><code> / <h6> (and the code / mark chips) were fixed
// light-surface colors. They now switch to dark-surface variants whenever the
// effective default text color is light.
//
// Contrast is asserted on the RESOLVED style against the surface color, plus one
// pixel test for the case the numbers cannot prove (the text is really painted
// visibly). The light-surface palette is asserted EXACTLY so a regression that
// shifts the unchanged light output is caught here, not only by goldens.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';

const _html = '<h6>six</h6><p><a href="#">link</a> <code>inline</code> '
    '<mark>marked</mark></p><pre><code>block code</code></pre>'
    '<a name="anchor">not a link</a>';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  final hi = x > y ? x : y, lo = x > y ? y : x;
  return (hi + 0.05) / (lo + 0.05);
}

UDTNode? _find(UDTNode n, bool Function(UDTNode) test) {
  if (test(n)) return n;
  for (final c in n.children) {
    final f = _find(c, test);
    if (f != null) return f;
  }
  return null;
}

Future<DocumentNode> _doc(
  WidgetTester t, {
  required Brightness brightness,
  Color? textColor,
  String? css,
  String html = _html,
  HyperRenderMode mode = HyperRenderMode.sync,
  HyperRenderConfig config = const HyperRenderConfig(useMicrotaskParsing: true),
}) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: HyperViewer(
        html: html,
        textColor: textColor,
        customCss: css,
        mode: mode,
        renderConfig: config,
      ),
    ),
  ));
  await t.pumpAndSettle();
  return t
      .widget<HyperRenderWidget>(find.byType(HyperRenderWidget).first)
      .document;
}

ComputedStyle _style(DocumentNode d, String tag, {String? inside}) {
  final n = _find(d, (n) {
    if (n.tagName != tag) return false;
    return inside == null || n.parent?.tagName == inside;
  });
  expect(n, isNotNull, reason: '<$tag> not found');
  return n!.style;
}

const _surface = Color(0xFF121212);
const _card = Color(0xFF1E1E1E);

void main() {
  group('dark Theme: readable built-in colors (>= 4.5:1)', () {
    testWidgets('link, h6 and <pre><code> against the page', (t) async {
      final d = await _doc(t, brightness: Brightness.dark);
      for (final (tag, inside) in [
        ('a', null),
        ('h6', null),
        ('code', 'pre')
      ]) {
        final c = _style(d, tag, inside: inside).color;
        expect(_contrast(c, _surface), greaterThanOrEqualTo(4.5),
            reason: '<$tag> $c on page');
        expect(_contrast(c, _card), greaterThanOrEqualTo(4.5),
            reason: '<$tag> $c on a card');
      }
    });

    testWidgets(
        'inline <code> and <mark> are readable on their own chip and '
        'no longer a glaring light block', (t) async {
      final d = await _doc(t, brightness: Brightness.dark);
      for (final tag in ['mark']) {
        final s = _style(d, tag);
        expect(
            _contrast(s.color, s.backgroundColor!), greaterThanOrEqualTo(4.5));
        expect(s.backgroundColor!.computeLuminance(), lessThan(0.2),
            reason: '<$tag> chip must be dark on a dark page');
      }
      final code = _style(d, 'code', inside: 'p');
      expect(_contrast(code.color, code.backgroundColor!),
          greaterThanOrEqualTo(4.5));
      expect(code.backgroundColor!.computeLuminance(), lessThan(0.2));
    });

    testWidgets('an <a> without href stays plain text (no link color)',
        (t) async {
      final d = await _doc(t, brightness: Brightness.dark);
      final plain =
          _find(d, (n) => n.tagName == 'a' && n.attributes['href'] == null)!;
      expect(plain.style.color, ThemeData.dark().colorScheme.onSurface);
    });
  });

  group('light surfaces keep the exact original palette', () {
    testWidgets('light Theme, no textColor', (t) async {
      final d = await _doc(t, brightness: Brightness.light);
      expect(_style(d, 'a').color, const Color(0xFF1976D2));
      expect(_style(d, 'h6').color, const Color(0xFF6B7280));
      final code = _style(d, 'code', inside: 'p');
      expect(code.color, const Color(0xFF0550AE));
      expect(code.backgroundColor, const Color(0xFFF6F8FA));
      final mark = _style(d, 'mark');
      expect(mark.color, const Color(0xFF713F12));
      expect(mark.backgroundColor, const Color(0xFFFEF08A));
    });

    testWidgets(
        'dark Theme + dark textColor (a white email pane) keeps the '
        'light-surface palette — switching would put light blue on white',
        (t) async {
      final d =
          await _doc(t, brightness: Brightness.dark, textColor: Colors.black87);
      expect(_style(d, 'a').color, const Color(0xFF1976D2));
      expect(_style(d, 'h6').color, const Color(0xFF6B7280));
      expect(_style(d, 'code', inside: 'p').backgroundColor,
          const Color(0xFFF6F8FA));
    });
  });

  group('the surface is judged by the effective text color', () {
    testWidgets(
        'light Theme + light textColor (a dark pane) uses the dark '
        'variants', (t) async {
      final d =
          await _doc(t, brightness: Brightness.light, textColor: Colors.white);
      expect(
          _contrast(_style(d, 'a').color, _surface), greaterThanOrEqualTo(4.5));
      expect(_style(d, 'a').color, isNot(const Color(0xFF1976D2)));
    });

    testWidgets('a theme toggle switches the palette (silent re-parse)',
        (t) async {
      Widget app(Brightness b) => MaterialApp(
            theme: ThemeData(brightness: b),
            home: const Scaffold(
              body: HyperViewer(html: _html, mode: HyperRenderMode.sync),
            ),
          );
      DocumentNode doc() => t
          .widget<HyperRenderWidget>(find.byType(HyperRenderWidget).first)
          .document;
      await t.pumpWidget(app(Brightness.light));
      await t.pumpAndSettle();
      expect(_style(doc(), 'a').color, const Color(0xFF1976D2));
      await t.pumpWidget(app(Brightness.dark));
      await t.pumpAndSettle();
      expect(_style(doc(), 'a').color, isNot(const Color(0xFF1976D2)));
      await t.pumpWidget(app(Brightness.light));
      await t.pumpAndSettle();
      expect(_style(doc(), 'a').color, const Color(0xFF1976D2));
    });
  });

  group('author CSS still wins over the dark variants', () {
    testWidgets('customCss and inline style', (t) async {
      final d = await _doc(t,
          brightness: Brightness.dark,
          css: 'a { color: #ff0000; }',
          html:
              '<p><a href="#">link</a></p><p><a href="#" style="color:#00ff00">'
              'inline</a></p><h6 style="color:#0000ff">six</h6>');
      final links = <UDTNode>[];
      void walk(UDTNode n) {
        if (n.tagName == 'a') links.add(n);
        n.children.forEach(walk);
      }

      walk(d);
      expect(links[0].style.color, const Color(0xFFFF0000));
      expect(links[1].style.color, const Color(0xFF00FF00));
      expect(_style(d, 'h6').color, const Color(0xFF0000FF));
    });
  });

  group('every parse path', () {
    testWidgets('virtualized compute() isolate carries the dark surface',
        (t) async {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: HyperViewer(
            html: _html,
            mode: HyperRenderMode.virtualized,
            renderConfig: HyperRenderConfig(useMicrotaskParsing: false),
          ),
        ),
      ));
      for (var i = 0;
          i < 50 && find.byType(HyperRenderWidget).evaluate().isEmpty;
          i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
      await t.pump(const Duration(milliseconds: 400));
      final d = t
          .widget<HyperRenderWidget>(find.byType(HyperRenderWidget).first)
          .document;
      expect(
          _contrast(_style(d, 'a').color, _surface), greaterThanOrEqualTo(4.5));
    });

    testWidgets('markdown links on a dark Theme', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: HyperViewer.markdown(markdown: '[a link](https://example.com)'),
        ),
      ));
      await t.pumpAndSettle();
      final d = t
          .widget<HyperRenderWidget>(find.byType(HyperRenderWidget).first)
          .document;
      expect(
          _contrast(_style(d, 'a').color, _surface), greaterThanOrEqualTo(4.5));
    });
  });

  testWidgets(
      'pixels: a link on a dark surface is painted with the new color '
      'and is clearly visible', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: _surface,
        body: RepaintBoundary(
          key: key,
          child: const SizedBox(
            width: 300,
            height: 80,
            child: HyperViewer(
              html: '<p><a href="#">LINKLINKLINK</a></p>',
              mode: HyperRenderMode.sync,
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    final (bright, oldBlue) = (await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final d = (await (await b.toImage()).toByteData())!;
      var bright = 0, old = 0;
      for (var i = 0; i < d.lengthInBytes; i += 4) {
        final r = d.getUint8(i), g = d.getUint8(i + 1), bl = d.getUint8(i + 2);
        if (r + g + bl > 450) bright++;
        // The old #1976D2, anti-aliased: blue-dominant and darker.
        if (bl > 150 && r < 60 && g > 90 && g < 140) old++;
      }
      return (bright, old);
    }))!;
    expect(bright, greaterThan(100),
        reason: 'link text must be clearly bright');
    expect(oldBlue, lessThan(bright ~/ 4),
        reason: 'the dark-on-dark #1976D2 must be gone');
  });
}
