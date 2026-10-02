import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render/hyper_render.dart';

/// Pixel-level checks for RenderHyperBox paint paths that "does not throw"
/// tests cannot see: each case renders, rasterizes, and counts pixels of
/// the colour that path is supposed to draw.
void main() {
  final boundaryKey = GlobalKey();

  Future<ui.Image> render(
    WidgetTester tester,
    String html, {
    bool debugBounds = false,
    void Function(RenderHyperBox box)? before,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: 400,
            height: 300,
            child: HyperViewer(
              html: html,
              mode: HyperRenderMode.sync,
              selectable: true,
              debugShowHyperRenderBounds: debugBounds,
              selectionColor: const Color(0xFF00FF00),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    if (before != null) {
      before(tester
          .renderObject<RenderHyperBox>(find.byType(HyperRenderWidget).first));
      await tester.pumpAndSettle();
    }
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    late ui.Image image;
    await tester.runAsync(() async {
      image = await boundary.toImage();
    });
    return image;
  }

  /// Pixels within [tolerance] per channel of [color] (alpha ignored).
  /// The boundary has no background, so translucent paints keep their own
  /// RGB rather than blending toward white.
  Future<int> countPixels(WidgetTester tester, ui.Image image, Color color,
      {int tolerance = 40}) async {
    late ByteData data;
    await tester.runAsync(() async {
      data =
          (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
    });
    final r = (color.r * 255).round(),
        g = (color.g * 255).round(),
        b = (color.b * 255).round();
    var n = 0;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      if ((data.getUint8(i) - r).abs() <= tolerance &&
          (data.getUint8(i + 1) - g).abs() <= tolerance &&
          (data.getUint8(i + 2) - b).abs() <= tolerance) {
        n++;
      }
    }
    return n;
  }

  const red = Color(0xFFFF0000);

  for (final style in ['solid', 'dashed', 'dotted', 'double']) {
    testWidgets('block border-style: $style paints the border colour',
        (tester) async {
      final image = await render(
          tester,
          '<div style="border: 6px $style #ff0000; padding: 8px">'
          'Bordered</div>');
      final borderPixels = await countPixels(tester, image, red);
      // A 6px border around a ~400px-wide box: hundreds of red pixels even
      // for dotted/dashed (which leave gaps) — none would mean not painted.
      expect(borderPixels, greaterThan(200), reason: style);
    });
  }

  testWidgets('dashed leaves gaps a solid border does not', (tester) async {
    final solid = await countPixels(
        tester,
        await render(tester,
            '<div style="border: 6px solid #ff0000; padding: 8px">x</div>'),
        red);
    final dashed = await countPixels(
        tester,
        await render(tester,
            '<div style="border: 6px dashed #ff0000; padding: 8px">x</div>'),
        red);
    expect(dashed, lessThan(solid));
  });

  testWidgets('block background and rounded border', (tester) async {
    final image = await render(
        tester,
        '<div style="background-color: #00ff00; border: 2px solid #0000ff; '
        'border-radius: 12px; padding: 20px">Box</div>');
    expect(await countPixels(tester, image, const Color(0xFF00FF00)),
        greaterThan(2000));
    expect(await countPixels(tester, image, const Color(0xFF0000FF)),
        greaterThan(100));
  });

  testWidgets('inline background and border on a span', (tester) async {
    // Padding: the test font (Ahem) draws glyphs as solid em boxes, which
    // would hide a background drawn at exactly the glyph box.
    final image = await render(
        tester,
        '<p>Before <span style="background-color: #ffff00; padding: 6px; '
        'border: 3px solid #ff00ff">highlighted</span> after</p>');
    expect(await countPixels(tester, image, const Color(0xFFFFFF00)),
        greaterThan(100));
    expect(await countPixels(tester, image, const Color(0xFFFF00FF)),
        greaterThan(100));
  });

  testWidgets('debugShowHyperRenderBounds outlines line rows', (tester) async {
    const html = '<p>Debug bounds paint outlines</p>';
    final plain = await render(tester, html);
    final debug = await render(tester, html, debugBounds: true);
    // Line rows are outlined in 0x66007BFF. (Fragment outlines sit under
    // the solid test-font glyphs, so count the line colour.)
    const lineBlue = Color(0xFF007BFF);
    expect(await countPixels(tester, plain, lineBlue, tolerance: 10), 0);
    expect(await countPixels(tester, debug, lineBlue, tolerance: 10),
        greaterThan(300));
  });

  testWidgets('selection highlight is painted behind selected text',
      (tester) async {
    // Transparent text: solid test-font glyphs would cover the highlight.
    const html =
        '<p style="color: transparent">Select all of this text please</p>';
    final before = await render(tester, html);
    final after = await render(tester, html, before: (b) => b.selectAll());
    const green = Color(0xFF00FF00); // selectionColor passed to the viewer
    final c0 = await countPixels(tester, before, green, tolerance: 10);
    final c1 = await countPixels(tester, after, green, tolerance: 10);
    expect(c0, 0);
    expect(c1, greaterThan(1000));
  });

  testWidgets('a float with an unloaded image paints its placeholder',
      (tester) async {
    final image = await render(
        tester,
        '<img src="https://example.invalid/a.png" width="120" height="80" '
        'style="float: left"><p>Text flows beside the float.</p>');
    // The placeholder is a light-grey box; plain white would mean nothing
    // was drawn where the float sits.
    expect(
        await countPixels(tester, image, const Color(0xFFEEEEEE),
            tolerance: 18),
        greaterThan(500));
  });
}
