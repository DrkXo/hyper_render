// Issue #20: default text color on dark surfaces + body/html { color }.
//
// These are pixel tests on purpose: the bug is "text paints in a color that is
// invisible on the background", which no widget-tree or style assertion sees.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';

const _html = '<p>Hello world, readable text</p>';

/// Counts text-ish pixels by color class on a 400x120 surface.
class _Px {
  _Px(this.light, this.dark, this.red);
  final int light; // near-white
  final int dark; // near-black / dark gray
  final int red;
  @override
  String toString() => 'light=$light dark=$dark red=$red';
}

Future<_Px> _shoot(
  WidgetTester t, {
  required Brightness brightness,
  required Color surface,
  String html = _html,
  String? css,
  Color? textColor,
}) async {
  final key = GlobalKey();
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      backgroundColor: surface,
      body: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: 400,
          height: 120,
          child: HyperViewer(
            html: html,
            customCss: css,
            textColor: textColor,
            mode: HyperRenderMode.sync,
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return _sample(t, key);
}

Future<_Px> _sample(WidgetTester t, GlobalKey key) async {
  return (await t.runAsync(() async {
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage();
    final d = (await img.toByteData())!;
    var light = 0, dark = 0, red = 0;
    for (var i = 0; i < d.lengthInBytes; i += 4) {
      final r = d.getUint8(i), g = d.getUint8(i + 1), bl = d.getUint8(i + 2);
      if (r > 200 && g < 90 && bl < 90) {
        red++;
      } else if (r + g + bl > 600) {
        light++;
      } else if (r + g + bl < 240 && r + g + bl > 0) {
        dark++;
      }
    }
    return _Px(light, dark, red);
  }))!;
}

void main() {
  group('default text color follows the theme', () {
    testWidgets('dark theme: text is light, not the dark default', (t) async {
      final px =
          await _shoot(t, brightness: Brightness.dark, surface: Colors.black);
      expect(px.light, greaterThan(200), reason: '$px');
    });

    testWidgets('light theme: unchanged dark text on a light surface',
        (t) async {
      final px =
          await _shoot(t, brightness: Brightness.light, surface: Colors.white);
      expect(px.dark, greaterThan(200), reason: '$px');
      expect(px.light, lessThan(30000), reason: 'sanity: surface only');
    });

    testWidgets('explicit textColor wins over the theme', (t) async {
      final px = await _shoot(t,
          brightness: Brightness.dark,
          surface: Colors.black,
          textColor: const Color(0xFFFF0000));
      expect(px.red, greaterThan(200), reason: '$px');
      expect(px.light, lessThan(50), reason: '$px');
    });

    testWidgets('content CSS still overrides the default', (t) async {
      final px = await _shoot(t,
          brightness: Brightness.dark,
          surface: Colors.black,
          css: 'p { color: #ff0000; }');
      expect(px.red, greaterThan(200), reason: '$px');
      expect(px.light, lessThan(50), reason: '$px');
    });

    testWidgets('inline style on an element still overrides', (t) async {
      final px = await _shoot(t,
          brightness: Brightness.dark,
          surface: Colors.black,
          html: '<p style="color:#ff0000">Hello world, readable text</p>');
      expect(px.red, greaterThan(200), reason: '$px');
    });

    testWidgets('switching the theme re-resolves the text color', (t) async {
      final key = GlobalKey();
      Widget app(Brightness b, Color surface) => MaterialApp(
            theme: ThemeData(brightness: b),
            home: Scaffold(
              backgroundColor: surface,
              body: RepaintBoundary(
                key: key,
                child: const SizedBox(
                  width: 400,
                  height: 120,
                  child: HyperViewer(html: _html, mode: HyperRenderMode.sync),
                ),
              ),
            ),
          );
      await t.pumpWidget(app(Brightness.light, Colors.white));
      await t.pumpAndSettle();
      final before = await _sample(t, key);
      expect(before.dark, greaterThan(200), reason: '$before');

      await t.pumpWidget(app(Brightness.dark, Colors.black));
      await t.pumpAndSettle();
      final after = await _sample(t, key);
      expect(after.light, greaterThan(200), reason: '$after');
    });
  });

  group('body / html { color }', () {
    for (final sel in ['body', 'html']) {
      testWidgets('$sel { color } is applied (was silently ignored)',
          (t) async {
        final px = await _shoot(t,
            brightness: Brightness.light,
            surface: Colors.black,
            css: '$sel { color: #ffffff; }');
        expect(px.light, greaterThan(200), reason: '$px');
      });
    }

    testWidgets('body { color } beats :root { color } (body is the descendant)',
        (t) async {
      final px = await _shoot(t,
          brightness: Brightness.light,
          surface: Colors.black,
          css: ':root { color: #ff0000; } body { color: #ffffff; }');
      expect(px.light, greaterThan(200), reason: '$px');
      expect(px.red, lessThan(50), reason: '$px');
    });

    testWidgets('body { color: var(--x) } resolves a :root custom property',
        (t) async {
      final px = await _shoot(t,
          brightness: Brightness.light,
          surface: Colors.black,
          css: ':root { --x: #ffffff; } body { color: var(--x); }');
      expect(px.light, greaterThan(200), reason: '$px');
    });

    testWidgets('body { color: … !important } beats an inline root default',
        (t) async {
      final px = await _shoot(t,
          brightness: Brightness.dark,
          surface: Colors.black,
          css: 'body { color: #ff0000 !important; }');
      expect(px.red, greaterThan(200), reason: '$px');
    });

    testWidgets('other body properties stay ignored (no display:none)',
        (t) async {
      final px = await _shoot(t,
          brightness: Brightness.light,
          surface: Colors.white,
          css: 'body { display: none; }');
      expect(px.dark, greaterThan(200),
          reason: 'content must still render: $px');
    });
  });

  group('layering: theme default < html < :root < body < textColor', () {
    testWidgets('dark theme + publisher body { color:#000 } stays black',
        (t) async {
      // Browser-faithful: the content decides. Pinned so a regression to
      // "theme always wins" is caught.
      final px = await _shoot(t,
          brightness: Brightness.dark,
          surface: Colors.black,
          css: 'body { color: #ff0000; }');
      expect(px.red, greaterThan(200), reason: '$px');
      expect(px.light, lessThan(50), reason: '$px');
    });

    testWidgets('textColor beats the publisher body color (host override)',
        (t) async {
      final px = await _shoot(t,
          brightness: Brightness.dark,
          surface: Colors.black,
          css: 'body { color: #ff0000 !important; }',
          textColor: Colors.white);
      expect(px.light, greaterThan(200), reason: '$px');
      expect(px.red, lessThan(50), reason: '$px');
    });

    testWidgets('textColor does not beat an element-level color', (t) async {
      final px = await _shoot(t,
          brightness: Brightness.dark,
          surface: Colors.black,
          css: 'p { color: #ff0000; }',
          textColor: Colors.white);
      expect(px.red, greaterThan(200), reason: '$px');
    });

    testWidgets('html < :root regardless of source order', (t) async {
      for (final css in [
        'html { color: #ff0000; } :root { color: #ffffff; }',
        ':root { color: #ffffff; } html { color: #ff0000; }',
      ]) {
        final px = await _shoot(t,
            brightness: Brightness.light, surface: Colors.black, css: css);
        expect(px.light, greaterThan(200), reason: '$css -> $px');
        expect(px.red, lessThan(50), reason: '$css -> $px');
      }
    });

    testWidgets(':root < body regardless of source order', (t) async {
      for (final css in [
        ':root { color: #ffffff; } body { color: #ff0000; }',
        'body { color: #ff0000; } :root { color: #ffffff; }',
      ]) {
        final px = await _shoot(t,
            brightness: Brightness.light, surface: Colors.black, css: css);
        expect(px.red, greaterThan(200), reason: '$css -> $px');
        expect(px.light, lessThan(50), reason: '$css -> $px');
      }
    });

    testWidgets('html, body { color } selector list is honoured', (t) async {
      final px = await _shoot(t,
          brightness: Brightness.light,
          surface: Colors.black,
          css: 'html, body { color: #ffffff; }');
      expect(px.light, greaterThan(200), reason: '$px');
    });
  });

  group(':root matches the document root only (not top-level blocks)', () {
    ComputedStyle pStyle(String css, [String html = '<p>x</p>']) {
      final doc = HtmlAdapter().parse(html);
      StyleResolver()
        ..parseCss(css)
        ..resolveStyles(doc);
      return doc.children.first.style;
    }

    test('a type selector beats :root on a top-level block', () {
      expect(pStyle(':root { color: #ffffff; } p { color: #ff0000; }').color,
          const Color(0xFFFF0000));
    });

    test('the root value is still inherited by unstyled blocks', () {
      expect(
          pStyle(':root { color: #ffffff; }').color, const Color(0xFFFFFFFF));
    });

    test(':root { font-size: 62.5% } does not compound on top-level blocks',
        () {
      // Before the fix the top-level <p> matched :root itself, applying 62.5%
      // a second time on top of the inherited value.
      final inherited = pStyle(':root { font-size: 62.5%; }').fontSize;
      final plain = pStyle('').fontSize;
      expect(inherited, closeTo(plain * 0.625, 0.001));
    });
  });

  group('every parse path applies the default', () {
    Color pColor(WidgetTester t) {
      for (final w
          in t.widgetList<HyperRenderWidget>(find.byType(HyperRenderWidget))) {
        UDTNode? p;
        void walk(UDTNode n) {
          if (n.tagName == 'p') p ??= n;
          n.children.forEach(walk);
        }

        walk(w.document);
        if (p != null) return p!.style.color;
      }
      fail('no <p> rendered');
    }

    Future<void> pumpDark(WidgetTester t, Widget viewer) async {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: SizedBox(width: 400, height: 600, child: viewer)),
      ));
      await t.pumpAndSettle();
    }

    final onSurface = ThemeData.dark().colorScheme.onSurface;

    testWidgets('virtualized, microtask parse', (t) async {
      await pumpDark(
          t,
          const HyperViewer(
            html: _html,
            mode: HyperRenderMode.virtualized,
            renderConfig: HyperRenderConfig(useMicrotaskParsing: true),
          ));
      expect(pColor(t), onSurface);
    });

    testWidgets('virtualized, compute() isolate parse', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: HyperViewer(
            html: _html,
            textColor: Color(0xFF123456),
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
      // The explicit override crossed the isolate boundary as an int.
      expect(pColor(t), const Color(0xFF123456));
    });

    testWidgets('markdown (sync fallback)', (t) async {
      await pumpDark(
          t, const HyperViewer.markdown(markdown: 'Hello **world**'));
      expect(find.byType(HyperRenderWidget), findsWidgets,
          reason: 'the loop below must have something to check');
      for (final w
          in t.widgetList<HyperRenderWidget>(find.byType(HyperRenderWidget))) {
        expect(w.document.children.first.style.color, onSurface);
      }
    });

    testWidgets('paged mode keeps its page across a theme toggle', (t) async {
      final controller = HyperPageController();
      addTearDown(controller.dispose);
      final long = List.generate(400, (i) => '<p>Paragraph $i text</p>').join();
      Widget app(Brightness b) => MaterialApp(
            theme: ThemeData(brightness: b),
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 300,
                child: HyperViewer(
                  html: long,
                  mode: HyperRenderMode.paged,
                  pageController: controller,
                  renderConfig: const HyperRenderConfig(
                    useMicrotaskParsing: true,
                    virtualizationChunkSize: 1000,
                  ),
                ),
              ),
            ),
          );
      await t.pumpWidget(app(Brightness.light));
      await t.pumpAndSettle();
      expect(controller.pageCount, greaterThan(2));
      controller.jumpToPage(2);
      await t.pumpAndSettle();
      expect(controller.currentPage.value, 2);

      await t.pumpWidget(app(Brightness.dark));
      await t.pumpAndSettle();
      expect(controller.currentPage.value, 2,
          reason: 'a theme toggle must not send the reader back to page 0');
    });
  });

  group('light surfaces never inherit unreadable text', () {
    // Resolved style of the first node with [tag].
    Future<ComputedStyle> styleOf(
      WidgetTester t,
      String html,
      String tag, {
      Brightness brightness = Brightness.dark,
      Color? textColor,
    }) async {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: HyperViewer(
            html: html,
            textColor: textColor,
            mode: HyperRenderMode.sync,
          ),
        ),
      ));
      await t.pumpAndSettle();
      UDTNode? found;
      void walk(UDTNode n) {
        if (n.tagName == tag) found ??= n;
        n.children.forEach(walk);
      }

      walk(
          t.widget<HyperRenderWidget>(find.byType(HyperRenderWidget)).document);
      return found!.style;
    }

    double contrastOf(ComputedStyle s) {
      final a = s.color.computeLuminance();
      final b = s.backgroundColor!.computeLuminance();
      return ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
    }

    for (final c in [
      ('blockquote', '<blockquote>q</blockquote>'),
      ('kbd', '<p><kbd>k</kbd></p>'),
      ('th', '<table><tr><th>h</th></tr></table>'),
      ('div', '<div style="background:#f5f5f5">x</div>'),
    ]) {
      testWidgets('dark theme: <${c.$1}> text has >= 3:1 contrast', (t) async {
        final s = await styleOf(t, c.$2, c.$1);
        expect(contrastOf(s), greaterThanOrEqualTo(3.0),
            reason: 'color=${s.color} bg=${s.backgroundColor}');
      });
    }

    testWidgets("an element's own color is never replaced", (t) async {
      final s = await styleOf(
          t, '<div style="background:#f5f5f5;color:#ffffff">x</div>', 'div');
      expect(s.color, const Color(0xFFFFFFFF));
    });

    testWidgets('a dark own-background keeps the light theme text', (t) async {
      final s =
          await styleOf(t, '<div style="background:#101010">x</div>', 'div');
      expect(s.color, ThemeData.dark().colorScheme.onSurface);
    });

    testWidgets('textColor in a light theme is guarded the same way',
        (t) async {
      final s = await styleOf(t, '<blockquote>q</blockquote>', 'blockquote',
          brightness: Brightness.light, textColor: Colors.white);
      expect(contrastOf(s), greaterThanOrEqualTo(3.0));
    });

    testWidgets('light theme without textColor is left exactly as before',
        (t) async {
      // Guard off: output must not change for anyone who set nothing, even for
      // an (unreadable) author combination.
      final s = await styleOf(
          t, '<div style="background:#101010">x</div>', 'div',
          brightness: Brightness.light);
      expect(s.color, const Color(0xFF1F2937));
    });
  });

  group('epub-style publisher CSS', () {
    testWidgets(
        'customCss "body { color … !important }" beats a chapter <style> color',
        (t) async {
      // The workaround for EpubReader (which has no textColor yet): chapter
      // <style> CSS is applied after customCss, so only !important wins.
      final px = await _shoot(t,
          brightness: Brightness.dark,
          surface: Colors.black,
          html: '<style>body { color: #ff0000; }</style>$_html',
          css: 'body { color: #ffffff !important; }');
      expect(px.light, greaterThan(200), reason: '$px');
      expect(px.red, lessThan(50), reason: '$px');
    });
  });

  group('theme toggle in virtualized mode', () {
    testWidgets('keeps the scroll offset and shows no placeholder', (t) async {
      final long = List.generate(400, (i) => '<p>Paragraph $i text</p>').join();
      var placeholders = 0;
      Widget app(Brightness b) => MaterialApp(
            theme: ThemeData(brightness: b),
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 300,
                child: HyperViewer(
                  html: long,
                  mode: HyperRenderMode.virtualized,
                  placeholderBuilder: (_) {
                    placeholders++;
                    return const SizedBox();
                  },
                  renderConfig: const HyperRenderConfig(
                    useMicrotaskParsing: true,
                    virtualizationChunkSize: 1000,
                  ),
                ),
              ),
            ),
          );
      ScrollPosition position() =>
          t.state<ScrollableState>(find.byType(Scrollable).first).position;
      double offset() => position().pixels;
      await t.pumpWidget(app(Brightness.light));
      await t.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
      position().jumpTo(1500);
      await t.pumpAndSettle();
      final before = offset();
      expect(before, greaterThan(1000));
      final placeholdersBefore = placeholders;

      await t.pumpWidget(app(Brightness.dark));
      await t.pumpAndSettle();
      expect(offset(), closeTo(before, 1.0),
          reason: 'a theme toggle must not reset the reader to the top');
      expect(placeholders, placeholdersBefore,
          reason: 'no loading placeholder frame on a theme toggle');
    });
  });
}
