// The README / usage guide show HyperViewer-style usage. This test is the
// compile-and-run proof of the documented snippet: `HyperViewer` has no
// clipboard parameter, so images are handed to `HyperImage` through the
// widget builder. (Earlier docs promised `HyperViewer(imageClipboardHandler:)`,
// which never existed; nothing guarded the snippet, so it went unnoticed.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_clipboard/hyper_render_clipboard.dart';
import 'package:hyper_render_core/hyper_render_core.dart';

/// Copied from `doc/usage_guide.md` — keep in sync.
HyperWidgetBuilder clipboardImageBuilder(ImageClipboardHandler handler) =>
    (node) {
      if (node is AtomicNode && node.tagName == 'img' && node.src != null) {
        return HyperImage(
          src: node.src!,
          width: node.intrinsicWidth ?? node.style.width,
          height: node.intrinsicHeight ?? node.style.height,
          clipboardHandler: handler,
        );
      }
      return null;
    };

void main() {
  testWidgets(
      'the documented widgetBuilder hands SuperClipboardHandler to '
      'every image', (tester) async {
    final handler = SuperClipboardHandler();
    final doc = DocumentNode(children: [
      BlockNode.p(children: [TextNode('Before')]),
      BlockNode.p(children: [AtomicNode.img(src: 'https://example.com/a.png')]),
    ]);

    // Network image fetches fail in the test environment; that is not what is
    // under test, so collect (and ignore) those errors.
    final onError = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = onError);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HyperRenderWidget(
          document: doc,
          widgetBuilder: clipboardImageBuilder(handler),
        ),
      ),
    ));
    await tester.pump();

    final image = tester.widget<HyperImage>(find.byType(HyperImage));
    expect(image.src, 'https://example.com/a.png');
    expect(identical(image.clipboardHandler, handler), isTrue);
  });

  test('non-image nodes fall through to the default renderer', () {
    final builder = clipboardImageBuilder(SuperClipboardHandler());
    expect(builder(BlockNode.p(children: [TextNode('x')])), isNull);
    expect(builder(AtomicNode.img(src: '')), isNotNull,
        reason: 'an empty-src img still reaches HyperImage (it shows its '
            'own error state)');
  });
}
