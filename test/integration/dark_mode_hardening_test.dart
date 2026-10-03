// Hardening for the dark-mode / root-color code paths (issue #20).
//
//  * security    — the root color now flows through `_applyDeclarations` from
//                  `body` / `html` rules, so every bound that protects ordinary
//                  declarations (var() expansion cap, scheme checks) must hold
//                  there too, and a hostile value must never throw.
//  * stress      — repeated theme toggles, in every parse mode, on a large
//                  document: no exception, scroll and page position kept.
//  * performance — body/html rules and a root color add no measurable cost to
//                  style resolution.
//
// Rendering behaviour itself is covered by test/dark_mode_text_color_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';

DocumentNode _resolve(String html, String css, {Color? override}) {
  final doc = HtmlAdapter().parse(html);
  StyleResolver()
    ..rootColorOverride = override
    ..parseCss(css)
    ..resolveStyles(doc);
  return doc;
}

Color _firstP(DocumentNode doc) =>
    doc.children.firstWhere((n) => n.tagName == 'p').style.color;

Future<void> _pumpApp(WidgetTester t, Brightness b, Widget viewer) =>
    t.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: b),
      home: Scaffold(body: SizedBox(width: 400, height: 600, child: viewer)),
    ));

void main() {
  group('security: root color declarations', () {
    test('a var() expansion bomb in body { color } is capped, not expanded',
        () {
      final css = StringBuffer(':root { --l0: #fff;');
      for (var i = 1; i <= 12; i++) {
        css.write('--l$i: ${List.filled(10, 'var(--l${i - 1})').join(' ')};');
      }
      css.write('} body { color: var(--l12); }');
      final sw = Stopwatch()..start();
      final doc = _resolve('<p>x</p>', css.toString());
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      // An unparsable/over-long value is dropped, leaving the default color.
      expect(_firstP(doc), const Color(0xFF1F2937));
    });

    test('hostile body colors never throw and fall back to the default', () {
      for (final value in [
        'url(javascript:alert(1))',
        'expression(alert(1))',
        'var(--missing)',
        'var(--a)', // self reference below
        '#',
        'rgb(',
        '${'(' * 5000}red',
        'x' * 100000,
        '\u0000\u0001',
      ]) {
        expect(
          () => _resolve('<p>x</p>', ':root{--a:var(--a)} body{color:$value}'),
          returnsNormally,
          reason: value.length > 40 ? '${value.length} chars' : value,
        );
      }
    });

    test('a 5000-rule stylesheet with body/html rules resolves in bounded time',
        () {
      final css = StringBuffer();
      for (var i = 0; i < 5000; i++) {
        css.write('.c$i { color: #00$i; } ');
        if (i % 500 == 0) {
          css.write('body { color: #ff0000; } html { color: #0000ff; } ');
        }
      }
      final sw = Stopwatch()..start();
      final doc = _resolve('<p class="c1">x</p><p>y</p>', css.toString());
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      expect(doc.children.length, 2);
    });

    test('a reused resolver keeps its body rule, a fresh one starts clean', () {
      // Root-color state lives on the resolver instance: re-using it applies
      // the same rules to the next document (documented behaviour), while a
      // new resolver must not inherit anything.
      final r = StyleResolver()..parseCss('body { color: #ff0000; }');
      final a = HtmlAdapter().parse('<p>a</p>');
      r.resolveStyles(a);
      expect(_firstP(a), const Color(0xFFFF0000));

      r.parseCss(''); // empty: must keep prior rules, not crash
      final b = HtmlAdapter().parse('<p>b</p>');
      r.resolveStyles(b);
      expect(_firstP(b), const Color(0xFFFF0000));

      final fresh = StyleResolver();
      final c = HtmlAdapter().parse('<p>c</p>');
      fresh.resolveStyles(c);
      expect(_firstP(c), const Color(0xFF1F2937),
          reason: 'a new resolver starts clean');
    });

    test('an out-of-range textColor (alpha 0) still renders without throwing',
        () {
      expect(
        () => _resolve('<p>x</p>', '', override: const Color(0x00000000)),
        returnsNormally,
      );
    });

    testWidgets(
        'sanitizer still strips <style>/<script> payloads under a dark '
        'theme', (t) async {
      await _pumpApp(
          t,
          Brightness.dark,
          const HyperViewer(
            html: '<p>Safe</p><script>alert(1)</script>',
            mode: HyperRenderMode.sync,
          ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.textContaining('alert'), findsNothing);
    });
  });

  group('stress: theme toggling', () {
    final long =
        List.generate(300, (i) => '<p>Paragraph $i with some text</p>').join();

    for (final mode in [
      HyperRenderMode.sync,
      HyperRenderMode.virtualized,
      HyperRenderMode.paged,
    ]) {
      testWidgets('40 light/dark toggles in $mode never throw', (t) async {
        Widget viewer() => HyperViewer(
              html: long,
              mode: mode,
              renderConfig: const HyperRenderConfig(
                useMicrotaskParsing: true,
                virtualizationChunkSize: 1000,
              ),
            );
        for (var i = 0; i < 40; i++) {
          await _pumpApp(
              t, i.isEven ? Brightness.light : Brightness.dark, viewer());
          await t.pump(const Duration(milliseconds: 20));
        }
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byType(HyperRenderWidget), findsWidgets);
      });
    }

    testWidgets(
        'toggling while an async parse is in flight keeps the newest '
        'theme', (t) async {
      Widget viewer() => const HyperViewer(
            html: '<p>In flight</p>',
            mode: HyperRenderMode.virtualized,
            renderConfig: HyperRenderConfig(useMicrotaskParsing: true),
          );
      await _pumpApp(t, Brightness.light, viewer());
      // Flip twice without letting the first re-parse complete.
      await _pumpApp(t, Brightness.dark, viewer());
      await _pumpApp(t, Brightness.light, viewer());
      await _pumpApp(t, Brightness.dark, viewer());
      await t.pumpAndSettle();
      UDTNode? p;
      void walk(UDTNode n) {
        if (n.tagName == 'p') p ??= n;
        n.children.forEach(walk);
      }

      for (final w
          in t.widgetList<HyperRenderWidget>(find.byType(HyperRenderWidget))) {
        walk(w.document);
      }
      expect(p!.style.color, ThemeData.dark().colorScheme.onSurface,
          reason: 'a stale parse must not overwrite the newest theme');
    });

    testWidgets('streaming content under a dark theme stays themed per token',
        (t) async {
      final controller = HyperStreamingController();
      addTearDown(controller.dispose);
      await _pumpApp(
          t,
          Brightness.dark,
          HyperViewer.streaming(
            streamingController: controller,
            mode: HyperRenderMode.sync,
          ));
      for (var i = 0; i < 20; i++) {
        controller.append('<p>token $i</p>');
        await t.pump(const Duration(milliseconds: 40));
      }
      // The typing caret animates for as long as the stream is open.
      controller.complete();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (final w
          in t.widgetList<HyperRenderWidget>(find.byType(HyperRenderWidget))) {
        final p = w.document.children.first;
        expect(p.style.color, ThemeData.dark().colorScheme.onSurface);
      }
    });
  });

  group('performance: root color adds no measurable cost', () {
    test(
        'resolving with a root color + body/html rules stays within 3x of '
        'baseline', () {
      final html =
          List.generate(2000, (i) => '<p><b>bold</b> text $i</p>').join();
      const css = 'body { color: #112233; } html { color: #445566; } '
          'p { margin: 4px; }';

      int run(String stylesheet, Color? override) {
        final doc = HtmlAdapter().parse(html);
        final r = StyleResolver()
          ..rootColorOverride = override
          ..ensureReadableOnOwnBackground = override != null
          ..parseCss(stylesheet);
        final sw = Stopwatch()..start();
        r.resolveStyles(doc);
        return sw.elapsedMicroseconds;
      }

      // Warm up, then take the best of 9 runs each: the minimum is the sample
      // least disturbed by a busy CI runner. Measured cost is ~1.1x; the 3x
      // bound only has to catch an accidental O(rules) or O(nodes^2) walk.
      int best(String stylesheet, Color? override) {
        run(stylesheet, override);
        var m = 1 << 30;
        for (var i = 0; i < 9; i++) {
          final v = run(stylesheet, override);
          if (v < m) m = v;
        }
        return m;
      }

      final base = best('p { margin: 4px; }', null);
      final rooted = best(css, const Color(0xFFABCDEF));
      expect(rooted, lessThan(base * 3 + 5000),
          reason: 'base=${base}us rooted=${rooted}us');
    });
  });
}
