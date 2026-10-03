// A block-tier plugin on a CUSTOM tag (`<info-box>`, `<x-badge>`), reached the
// documented way — HyperViewer(html:, pluginRegistry:). The adapters build a
// custom tag as an InlineNode (no UA display style), so the block-plugin path
// was never taken: the widget was built, linked to no fragment, laid out at
// 0x0 and never painted ("Layout Warning: More child widgets than fragments").
//
// The older plugin tests constructed `BlockNode(tagName: 'figure')` by hand or
// used `findsOneWidget`, which a 0x0 widget satisfies — so none could see it.
// These assert size, position and pixels.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';

const _amber = Color(0xFFFFC107);

class _Block implements HyperNodePlugin {
  const _Block(this.tag, {this.height = 40});
  final String tag;
  final double height;
  @override
  List<String> get tagNames => [tag];
  @override
  bool get isInline => false;
  @override
  Widget? buildWidget(UDTNode node, HyperPluginBuildContext ctx) => SizedBox(
        key: ValueKey(tag),
        height: height,
        child: const ColoredBox(color: _amber),
      );
}

Future<({List<String> warnings, GlobalKey capture})> _pump(
  WidgetTester t,
  String html,
  List<HyperNodePlugin> plugins, {
  HyperRenderMode mode = HyperRenderMode.sync,
}) async {
  final warnings = <String>[];
  final reg = HyperPluginRegistry();
  for (final p in plugins) {
    reg.register(p);
  }
  final key = GlobalKey();
  // flutter_test fails a test that leaves `debugPrint` replaced, and tearDown
  // callbacks run after that check — so restore it here, not in addTearDown.
  final old = debugPrint;
  debugPrint = (m, {wrapWidth}) {
    if (m != null && m.contains('More child widgets than fragments')) {
      warnings.add(m);
    }
  };
  try {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 400,
            height: 400,
            child: HyperViewer(
              html: html,
              pluginRegistry: reg,
              mode: mode,
              renderConfig: const HyperRenderConfig(useMicrotaskParsing: true),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
  } finally {
    debugPrint = old;
  }
  return (warnings: warnings, capture: key);
}

/// Top offset of each text fragment, keyed by its text.
Map<String, double> _textTops(WidgetTester t) {
  RenderHyperBox? box;
  void walk(RenderObject o) {
    if (o is RenderHyperBox) box ??= o;
    o.visitChildren(walk);
  }

  walk(t.renderObject(find.byType(HyperRenderWidget).first));
  return {
    for (final f in box!.debugFragments())
      if (f['text'] != null && f['offsetY'] != null)
        (f['text'] as String).trim(): (f['offsetY'] as num).toDouble(),
  };
}

Future<int> _amberPixels(WidgetTester t, GlobalKey key) async =>
    (await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final d = (await (await b.toImage()).toByteData())!;
      var n = 0;
      for (var i = 0; i < d.lengthInBytes; i += 4) {
        if (d.getUint8(i) == 255 &&
            d.getUint8(i + 1) == 193 &&
            d.getUint8(i + 2) == 7) {
          n++;
        }
      }
      return n;
    }))!;

void main() {
  for (final html in [
    '<p>Before</p><x-a></x-a><p>After</p>',
    '<p>Before</p><x-a type="tip">content the plugin owns</x-a><p>After</p>',
  ]) {
    testWidgets(
        'block plugin on a custom tag is sized, placed and painted: '
        '$html', (t) async {
      final r = await _pump(t, html, [const _Block('x-a')]);
      final f = find.byKey(const ValueKey('x-a'));
      expect(f, findsOneWidget);

      // Full available width, its own height.
      expect(t.getSize(f), const Size(400, 40));

      // Between the two paragraphs, not stacked on top of either. Text is
      // painted on the canvas, so read its position from the render object.
      final y = _textTops(t);
      final top = t.getTopLeft(f).dy;
      expect(top, greaterThan(y['Before']!));
      expect(y['After']!, greaterThanOrEqualTo(top + 40 - 0.5));

      expect(await _amberPixels(t, r.capture), 400 * 40,
          reason: 'the plugin widget must actually paint');
      expect(r.warnings, isEmpty);
    });
  }

  testWidgets('the plugin owns its children: their text is not also rendered',
      (t) async {
    await _pump(
        t, '<p>Before</p><x-a>SECRET-CHILD</x-a>', [const _Block('x-a')]);
    expect(
        find.textContaining('SECRET-CHILD', findRichText: true), findsNothing);
  });

  testWidgets('three adjacent block plugins stack, none overlapping',
      (t) async {
    await _pump(t, '<x-a></x-a><x-b></x-b><x-c></x-c>', [
      const _Block('x-a'),
      const _Block('x-b', height: 30),
      const _Block('x-c', height: 20)
    ]);
    final ys = [
      for (final k in ['x-a', 'x-b', 'x-c'])
        t.getTopLeft(find.byKey(ValueKey(k))).dy,
    ];
    expect(ys[1], greaterThanOrEqualTo(ys[0] + 40 - 0.5));
    expect(ys[2], greaterThanOrEqualTo(ys[1] + 30 - 0.5));
  });

  testWidgets('works in virtualized mode too', (t) async {
    final r = await _pump(
        t, '<p>Before</p><x-a></x-a><p>After</p>', [const _Block('x-a')],
        mode: HyperRenderMode.virtualized);
    expect(t.getSize(find.byKey(const ValueKey('x-a'))), const Size(400, 40));
    expect(r.warnings, isEmpty);
  });

  testWidgets(
      'an unregistered custom tag is unaffected (no widget, no warning)',
      (t) async {
    final r = await _pump(t, '<p>Before</p><x-zzz>inline text</x-zzz>', []);
    expect(find.byKey(const ValueKey('x-zzz')), findsNothing);
    expect(r.warnings, isEmpty);
  });

  testWidgets('an INLINE plugin on a custom tag still flows with text',
      (t) async {
    final reg = HyperPluginRegistry()..register(const _InlineChip());
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: HyperViewer(
            html: '<p>Status: <x-chip></x-chip> done</p>',
            pluginRegistry: reg,
            mode: HyperRenderMode.sync,
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('chip')), findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('chip'))).width, greaterThan(0));
  });
}

class _InlineChip implements HyperNodePlugin {
  const _InlineChip();
  @override
  List<String> get tagNames => const ['x-chip'];
  @override
  bool get isInline => true;
  @override
  Widget? buildWidget(UDTNode node, HyperPluginBuildContext ctx) =>
      const SizedBox(key: ValueKey('chip'), width: 40, height: 16);
}
