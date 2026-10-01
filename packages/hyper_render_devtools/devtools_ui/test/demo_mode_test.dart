import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_devtools_ui/main.dart';

/// Smoke test: with no VM service connected, Demo mode must populate every
/// tab and the export dialog without throwing.
void main() {
  testWidgets('demo mode renders all six tabs and the export dialog',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const HyperRenderInspectorApp());
    // No VM service in a test: the initial refresh never resolves and its
    // spinner never settles, so pump a few frames instead of settling.
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Demo').first);
    await tester.pumpAndSettle();
    expect(find.text('DEMO'), findsOneWidget);

    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.text('demo-renderer'), findsWidgets);
    expect(find.text('demo-chunk-2'), findsOneWidget);

    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('[12, 40)'), findsOneWidget);
    expect(find.textContaining('ruby: "かんじ"'), findsWidgets);

    await tester.tap(find.text('CSS Vars'));
    await tester.pumpAndSettle();
    expect(find.text('--brand'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Export UDT snapshot (JSON)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('hyper_render_devtools.snapshot/1'),
        findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
