import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';
import 'package:hyper_render_core/hyper_render_core.dart'
    show HyperRenderDebugHooks;

/// DevTools live CSS-variable editing: setting
/// [HyperRenderDebugHooks.cssVariableOverrides] makes every HyperViewer
/// re-resolve its styles with the new `--var` values.
void main() {
  const html = '<style>:root { --brand: #ff0000; } '
      'p { color: var(--brand); }</style><p>Brand text</p>';

  tearDown(() => HyperRenderDebugHooks.cssVariableOverrides.value = const {});

  Color paragraphColor(WidgetTester tester) {
    for (final w in tester
        .widgetList<HyperRenderWidget>(find.byType(HyperRenderWidget))) {
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

  testWidgets('sync mode re-renders with an overridden variable',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HyperViewer(html: html, mode: HyperRenderMode.sync)),
    ));
    await tester.pumpAndSettle();
    expect(paragraphColor(tester), const Color(0xFFFF0000));

    HyperRenderDebugHooks.cssVariableOverrides.value = {'--brand': '#0000ff'};
    await tester.pumpAndSettle();
    expect(paragraphColor(tester), const Color(0xFF0000FF));

    HyperRenderDebugHooks.cssVariableOverrides.value = const {};
    await tester.pumpAndSettle();
    expect(paragraphColor(tester), const Color(0xFFFF0000));
  });

  testWidgets('virtualized (async parse) mode picks up overrides too',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HyperViewer(
          html: html,
          mode: HyperRenderMode.virtualized,
          renderConfig: HyperRenderConfig(useMicrotaskParsing: true),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(paragraphColor(tester), const Color(0xFFFF0000));

    HyperRenderDebugHooks.cssVariableOverrides.value = {'--brand': '#00ff00'};
    await tester.pumpAndSettle();
    expect(paragraphColor(tester), const Color(0xFF00FF00));
  });

  testWidgets('a disposed viewer stops listening', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HyperViewer(html: html, mode: HyperRenderMode.sync)),
    ));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    HyperRenderDebugHooks.cssVariableOverrides.value = {'--brand': '#0000ff'};
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
