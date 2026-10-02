import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_core/hyper_render_core.dart';

/// HtmlToSpanConverter: the single-RichText alternative to RenderHyperBox.
void main() {
  String plain(InlineSpan span) => span.toPlainText(includePlaceholders: false);

  // Not visitChildren: it skips spans without their own text, such as the
  // children-only TextSpan a link becomes.
  List<InlineSpan> flatten(InlineSpan span) {
    final out = <InlineSpan>[span];
    span.visitDirectChildren((s) {
      out.addAll(flatten(s));
      return true;
    });
    return out;
  }

  DocumentNode doc(List<UDTNode> children) {
    final d = DocumentNode(children: children);
    StyleResolver().resolveStyles(d);
    return d;
  }

  test('text, inline and block nodes become one span tree', () {
    final span = HtmlToSpanConverter().convert(doc([
      BlockNode.h1(children: [TextNode('Title')]),
      BlockNode.p(children: [
        TextNode('Hello '),
        InlineNode(tagName: 'strong', children: [TextNode('bold')]),
        LineBreakNode(),
        TextNode('next'),
      ]),
      BlockNode.div(children: [TextNode('div')]),
    ]));
    // Headings/paragraphs get a blank line after them, other blocks one.
    expect(plain(span), 'Title\n\nHello bold\nnext\n\ndiv\n');
  });

  test('whitespace collapses, but &nbsp; (U+00A0) is preserved', () {
    final span = HtmlToSpanConverter().convert(doc([
      BlockNode.div(children: [TextNode('a \t\n  b  c')]),
    ]));
    expect(plain(span), 'a b  c\n');
  });

  test('preserveWhitespace keeps runs intact', () {
    final span = HtmlToSpanConverter(preserveWhitespace: true).convert(doc([
      BlockNode.div(children: [TextNode('a   b')]),
    ]));
    expect(plain(span), 'a   b\n');
  });

  test('display:none nodes are skipped', () {
    final hidden = InlineNode(tagName: 'span', children: [TextNode('secret')]);
    final d = doc([
      BlockNode.div(children: [TextNode('shown'), hidden]),
    ]);
    hidden.style.display = DisplayType.none;
    expect(plain(HtmlToSpanConverter().convert(d)), 'shown\n');
  });

  test('links get a recognizer that reports the href; dispose clears them', () {
    final taps = <String>[];
    final converter = HtmlToSpanConverter(onLinkTap: taps.add);
    final span = converter.convert(doc([
      BlockNode.p(children: [
        InlineNode(
          tagName: 'a',
          attributes: {'href': 'https://example.com'},
          children: [TextNode('link')],
        ),
        InlineNode(tagName: 'a', children: [TextNode('no href')]),
      ]),
    ]));
    final recognizers = flatten(span)
        .whereType<TextSpan>()
        .map((s) => s.recognizer)
        .whereType<TapGestureRecognizer>()
        .toList();
    expect(recognizers, hasLength(1), reason: 'only the link with an href');
    recognizers.single.onTap!();
    expect(taps, ['https://example.com']);
    converter.dispose();
  });

  test('atomic nodes: image builder, media builder, formula, placeholder', () {
    final images = <String>[];
    final media = <MediaInfo>[];
    final converter = HtmlToSpanConverter(
      imageBuilder: (src, alt, w, h) {
        images.add(src);
        return const SizedBox();
      },
      mediaBuilder: (context, info) {
        media.add(info);
        return const SizedBox();
      },
    );
    final span = converter.convert(doc([
      BlockNode.div(children: [
        AtomicNode.img(src: 'https://e.com/a.png', alt: 'A'),
        AtomicNode.video(src: 'https://e.com/v.mp4'),
        AtomicNode(tagName: 'formula', attributes: {'formula': r'\alpha'}),
        AtomicNode(tagName: 'iframe'),
      ]),
    ]));
    final widgets = flatten(span).whereType<WidgetSpan>().toList();
    expect(widgets, hasLength(4));
    expect(images, ['https://e.com/a.png']);
    expect(widgets[2].child, isA<FormulaWidget>());
  });

  testWidgets('default image/media widgets and the build helpers render',
      (tester) async {
    final d = doc([
      BlockNode.p(children: [
        TextNode('x'),
        AtomicNode.img(src: 'relative.png', alt: 'alt text'),
        AtomicNode.video(src: 'https://e.com/v.mp4'),
        RubyNode(baseText: '漢字', rubyText: 'かんじ'),
      ]),
    ]);
    final converter = HtmlToSpanConverter(onMediaTap: (_) {});
    for (final build in [
      converter.buildRichText,
      converter.buildSelectableText,
      converter.buildWithSelectionArea,
    ]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: build(d))),
      ));
      expect(tester.takeException(), isNull);
    }
    converter.dispose();
  });
}
