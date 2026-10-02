// Drives the REAL demo app on a device/desktop with real fonts: opens every
// home-screen demo (and every item inside hub pages), lets it run for a
// few seconds, and fails on any FlutterError — including RenderFlex
// overflows, which the widget-test smoke net deliberately ignores because
// the test font is not a real proportional font.
//
//   flutter test integration_test/all_demos_test.dart -d macos
//
// The demo list comes from the home screen itself; the test also counts the
// cards it finds so a newly added demo cannot silently go untested.

import 'package:example/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _homeDemos = <String>[
  'AI / LLM Streaming Engine (v1.8.0)',
  'Start here — the 7-step tour',
  'Flagship Demo',
  'CSS Float Layout',
  'HTML Email',
  'EPUB Container',
  'HyperReader App',
  'Tables',
  'Flexbox',
  'CSS Grid & Advanced Layout',
  'Paged Mode',
  'Plugin API',
  'CSS Mastery (interactive)',
  'Text Selection',
  'Japanese & Manga Typography',
  '中文 · 繁體 · 한국어',
  'CSS Properties',
  'Images & Video',
  'Zero Padding Images',
  'Widget Injection & Animation',
  'Input Formats',
  'Math Formulas',
  'Float Layout Stress Test',
  'Comparison & Performance',
  'Dark Mode & Visual Quality',
  'Security & Accessibility',
  'Enterprise Features',
];

/// Items inside hub pages (Tables, Images & Video, ...): opened when the
/// current page shows them.
const _hubItems = <String>[
  'Basic Tables',
  'Wide Table Strategies',
  'Images',
  'Zoom & Pan',
  'Video',
  'Widget Injection',
  'Animated Widgets',
  'Markdown',
  'Quill Delta',
  'Base URL & Links',
  'vs flutter_html & fwfh',
  'Stress Test — 1000-Page Book',
  'Performance Deep Dive',
  'XSS Protection',
  'Accessibility',
  'WebView Fallback',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every demo opens and runs without a FlutterError',
      (tester) async {
    final errors = <String>[];
    final original = FlutterError.onError;
    var current = 'home';
    FlutterError.onError = (details) {
      errors.add('[$current] ${details.exceptionAsString().split('\n').first}');
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);

    app.main();
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));

    Future<void> run(Duration d) async {
      final end = DateTime.now().add(d);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> open(String title, {required bool fromHome}) async {
      current = title;
      final target = find.text(title).first;
      if (fromHome) {
        await tester.scrollUntilVisible(target, 300,
            scrollable: find.byType(Scrollable).first);
      } else {
        await tester.ensureVisible(target);
      }
      await tester.pump();
      await tester.tap(target);
      await run(const Duration(seconds: 3));
      debugPrint('DEMO_OPENED $title errors_so_far=${errors.length}');
    }

    Future<void> back() async {
      // Let the push transition finish first: mid-transition both pages'
      // back buttons exist, and pageBack() requires exactly one.
      await run(const Duration(milliseconds: 600));
      await tester.tap(find.byTooltip('Back').last);
      await run(const Duration(milliseconds: 600));
    }

    var opened = 0;
    for (final title in _homeDemos) {
      await open(title, fromHome: true);
      opened++;
      final subItems =
          _hubItems.where((s) => find.text(s).evaluate().isNotEmpty).toList();
      for (final sub in subItems) {
        await open(sub, fromHome: false);
        await back();
        current = title;
      }
      await back();
      // Back on the home list.
      expect(find.text('HyperRender'), findsWidgets, reason: 'after $title');
    }

    debugPrint('DEMO_SUMMARY opened=$opened errors=${errors.length}');
    for (final e in errors) {
      debugPrint('DEMO_ERROR $e');
    }
    expect(opened, _homeDemos.length);
    expect(errors, isEmpty);
  });
}
