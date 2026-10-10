# Migration Guide

> **Current version: v1.13.0**

## Upgrading to v1.13.0

No breaking changes. New: `RenderHyperBox.getBoxesForCharRange` and `debugLineFragments` ([#26](https://github.com/brewkits/hyper_render/pull/26)). Two small `text-overflow: ellipsis` changes: selecting truncated text no longer highlights the `…` glyph, and a line where not even one character fits before the ellipsis now shows `…` instead of staying empty.

**Line breaking changed in a few cases**, so wrapped text can land on different lines than in 1.12.0: lines no longer overflow the box by part of a glyph (most visible in CJK), RTL paragraphs wrap properly, `word-break` / `overflow-wrap` on a block now apply to its text, an over-long word breaks after as many characters as fit, a word that doesn't fit beside a float moves below it, lines no longer start one space in after `<br>` or an indented tag, and centered / right-aligned lines no longer count trailing spaces. If you have pixel tests of wrapped text, expect to regenerate them.

```yaml
dependencies:
  hyper_render: ^1.13.0
```

## Upgrading to v1.12.0

No API changes, but on a **dark surface** (a dark `Theme`, or a light `textColor`) the built-in colors of links, `<h6>`, `<code>` / `<pre>` and `<mark>` change to dark-surface variants with at least 4.5:1 contrast ([#23](https://github.com/brewkits/hyper_render/issues/23)); inline `<code>` and `<mark>` become dark chips instead of bright blocks. Light-surface output is unchanged. The palette is chosen from the effective text color, so a dark `Theme` with `textColor: Colors.black87` (a white pane) keeps the light-surface palette. Your own CSS (`a { color }`, inline `style`) still wins.

```yaml
dependencies:
  hyper_render: ^1.12.0
```

## Upgrading to v1.11.0

One new parameter (`HyperViewer(textColor:)`, and `EpubReader(textColor:)`), but **rendering changes in three cases** — check them before you ship:

- **Dark `Theme` → unstyled text is now `colorScheme.onSurface`** (it was always dark gray `#1F2937`). This fixes [#20](https://github.com/brewkits/hyper_render/issues/20), but if your app puts `HyperViewer` on a surface that stays light under a dark theme (a white email pane, a paper-colored reader page), the text is now light on light. Fix: pass `textColor: Colors.black87` (or any color) on that viewer. Light themes are unchanged.
- **`body { color }` / `html { color }` now apply.** They were silently ignored. Content that declares one (EPUB stylesheets often do) renders in that color. On a dark theme a publisher `body { color: #000 }` stays black unless you pass `textColor`, which wins over it.
- **`:root` now matches only the document root.** 1.10.0 intended this, but top-level blocks (`parent == null`) still matched, so `:root { color: #fff } p { color: red }` rendered white. A rule that relied on `:root` styling every top-level block no longer does; `:root { --var }` and inherited properties are unaffected.

Also new: elements with their own opaque background and no `color` (`<blockquote>`, `<kbd>`, `<th>`, `style="background:#eee"`) never inherit text below 3:1 contrast once a theme or `textColor` default is in play.

```yaml
dependencies:
  hyper_render: ^1.11.0
  hyper_render_epub: ^0.1.3   # optional: EpubReader(textColor:)
```

## Upgrading to v1.10.0

No API changes, but **rendering can change** for pages that relied on CSS which used to be silently ignored:

- **`var()`, `url()` and `calc()` in `<style>` / `customCss` now resolve.** Before 1.10.0 they only worked in inline `style=""`. A page with `:root { --brand: … } p { color: var(--brand) }` now gets the brand color instead of the default.
- **`:root` matches only the document root.** It used to match every element, so `:root { font-size: 125% }` compounded at each nesting level and `:root { --x }` reset descendant overrides.
- **Stylesheet background URLs follow the `<img src>` scheme policy** (no `javascript:`, `file:`, `data:image/svg`, …).

```yaml
dependencies:
  hyper_render: ^1.10.0
  hyper_render_devtools: ^1.8.0   # optional: new Timeline / Selection / CSS Vars / Export tabs
```

## Upgrading to v1.4.0

### New in v1.4.0

- **CSS `transition` execution** — `HyperTransitionWidget` now animates `opacity`/`transform` on style changes using the declared duration and timing function
- **CSS `aspect-ratio`** — `W/H` and bare-number syntax applied to `<img>`/`<video>` sizing
- **`animation-iteration-count: infinite`** loops correctly via `AnimationController.repeat()`; `animation-direction: alternate` is handled distinctly
- **Cross-Chunk Float Carryover paint** — tall floated images now continue painting correctly in the next virtualized section
- **~25 previously-silent CSS properties** now resolved (white-space, word-spacing, text-transform, min/max-width/height, overflow, border-top/right/bottom/color/width, animation sub-properties, aspect-ratio, transition)
- Multiple bug fixes (rem units, text-decoration inheritance, linear-gradient diagonals, border:none width, Delta adapter indent precedence, Markdown CRLF)

No breaking changes. Bump versions:

```yaml
dependencies:
  hyper_render: ^1.4.0
  hyper_render_clipboard: ^1.4.0   # only if you use SuperClipboardHandler
  hyper_render_math: ^1.4.0        # only if you use MathNodePlugin / LatexNodePlugin
```

---

## Upgrading to v1.3.3 / v1.3.2

### ⚠️ Breaking change — clipboard and math are now opt-in (since v1.3.2)

`hyper_render_clipboard` and `hyper_render_math` are no longer transitive dependencies of the root `hyper_render` package. If you use either, add them explicitly:

```yaml
dependencies:
  hyper_render: ^1.4.0
  hyper_render_clipboard: ^1.4.0   # only if you use SuperClipboardHandler
  hyper_render_math: ^1.4.0        # only if you use MathNodePlugin / LatexNodePlugin
```

If you don't use either feature, **no changes are needed** — just bump the version and your Android build will no longer require a `compileSdk = 35` workaround.

### New in v1.3.3

- `onMemoryPressure` public callback for low-memory resource management
- CSS `object-fit` support for `<img>` elements (`cover`, `contain`, `fill`, `none`, `scale-down`)
- Performance: replaced CPU-side `Path.combine` with fast GPU-deferred `addRRect` calls in `_paintSelection`
- Version bumped across all sub-packages

### New in 1.3.2

- `list-style-type`, `list-style-position`, `list-style` shorthand CSS support
- `background-repeat`, `background-position` CSS support
- Edge-to-edge images: `width: 100%` now truly fills the container
- Selection drag performance improved (rects cached, auto-scroll proportional)

---

## Starting fresh with 1.4.0

**No migration needed!** If you're starting fresh:

```yaml
dependencies:
  hyper_render: ^1.4.0
  # opt-in extras:
  hyper_render_clipboard: ^1.4.0   # image copy/save/share
  hyper_render_math: ^1.4.0        # LaTeX/MathML
```

```dart
import 'package:hyper_render/hyper_render.dart';

HyperViewer(html: '<p>Hello World</p>')
HyperViewer.markdown(markdown: '# Hello')
HyperViewer(html: '...', mode: HyperRenderMode.paged, pageController: HyperPageController())
```

---

## v1.2.0 — What's New (March 2026)

### ✨ Plugin API, Paged Mode, Incremental Layout, A11y

#### New: Multi-tier Plugin API

Register custom HTML tag renderers at startup:

```dart
final registry = HyperPluginRegistry()
  ..register(MyBlockPlugin())   // isInline == false (full-width)
  ..register(MyInlinePlugin()); // isInline == true (flows with text)

HyperViewer(html: html, pluginRegistry: registry)
```

#### New: Paged Mode

```dart
final ctrl = HyperPageController();

HyperViewer(
  html: longHtml,
  mode: HyperRenderMode.paged,
  pageController: ctrl,
)

// Navigate programmatically:
ctrl.nextPage();
ctrl.animateToPage(3, duration: Duration(milliseconds: 300), curve: Curves.easeInOut);

// Reactive page indicator:
ValueListenableBuilder<int>(
  valueListenable: ctrl.currentPage,
  builder: (_, page, __) => Text('Page ${page + 1} of ${ctrl.pageCount}'),
)
```

#### New: Incremental Layout

Sections whose content hasn't changed are automatically reused — no API changes required.
Flutter skips re-layout and repaint for unchanged `RepaintBoundary` sections.
Approximately 90% layout rebuild reduction for live-updating feeds.

#### New: Accessibility (WCAG 2.1 AA)

- `<img alt="…">` now produces a discrete `SemanticsNode` at the image's layout rect (WCAG 1.1.1).
- `<a aria-label="…">` uses the `aria-label` value as the semantic label (WCAG 4.1.2).

### 🏗️ Internal Refactor — Dead-code elimination

- **No API changes.** Internal cleanup for better performance.
- Root `lib/src/` had 31 stale duplicate files shadowing `hyper_render_core`. All deleted.
- `LazyImageQueue` singleton is now the single shared instance from `hyper_render_core`.
- All v1.2.0 symbols (`HyperRenderConfig`, `LazyImageQueue`, `HyperNodePlugin`, `HyperPluginRegistry`,
  `HyperPluginBuildContext`, `LoadingSkeleton`, `HyperErrorWidget`, `FloatCarryover`) are now
  accessible from `package:hyper_render` directly.

---

## Future: Migration from v1.x to v2.x

> **This section is for planning purposes only and describes potential breaking changes in a future v2.0 release.**

When v2.0 is released (planned features):
- Modular plugin architecture with separate parser packages
- Zero-dependency core package
- Improved tree-shaking for smaller bundle sizes
- Enhanced plugin system

### Potential Changes in v2.0 (Not Yet Released)

**Current v1.0:**
```yaml
dependencies:
  hyper_render_core: ^1.0.0
```

**Future v2.0 (example structure):**
```yaml
dependencies:
  hyper_render_core: ^2.0.0       # Core engine
  hyper_render_html: ^2.0.0       # HTML parser plugin
  hyper_render_markdown: ^2.0.0   # Markdown parser plugin (optional)
```

### What Won't Change

These APIs are stable and will remain backward-compatible in v2.0:

- Core widget: `HyperViewer`
- Plugin interfaces: `ImageClipboardHandler`, `CodeHighlighter`
- Design tokens system
- CSS support
- Float layout

---

## Version History

### v1.13.0 (October 2026)
- `RenderHyperBox.getBoxesForCharRange` / `debugLineFragments`, ellipsis character-count fix ([#26](https://github.com/brewkits/hyper_render/pull/26))

### v1.12.0 (October 2026)
- Dark-surface colors for links, `<h6>`, `<code>` / `<pre>` and `<mark>` ([#23](https://github.com/brewkits/hyper_render/issues/23))

### v1.11.0 (October 2026)
- Dark-theme text default, `HyperViewer(textColor:)`, `body`/`html` `color`, `:root` fix, contrast guard ([#20](https://github.com/brewkits/hyper_render/issues/20))

### v1.10.0 (October 2026)
- Stylesheet `var()` / `url()` / `calc()`, `:root` scoping, DevTools v2

### v1.3.0 (April 2026)
- High Coverage Milestone: >80% total line coverage (900+ tests)
- Fixed missing `foundation` import for `compute` function
- Virtualized selection logic refinements for off-screen chunks
- Flexible Markdown tag parsing (<b> vs <strong> compatibility)

### v1.2.0 (March 2026)
- Multi-tier Plugin API (`HyperNodePlugin` / `HyperPluginRegistry`)
- `HyperRenderMode.paged` + `HyperPageController`
- Dirty-flag incremental layout (~90% rebuild reduction)
- WCAG 2.1 AA: img alt SemanticsNode + aria-label on links
- Dead-code elimination — 31 duplicate root files removed
- `LazyImageQueue` singleton unified (single shared instance)
- All v1.2.0 symbols now accessible from `package:hyper_render`

### v1.1.x (March 2026)
- CSS @keyframes / animation support
- Ruby/furigana selection fixes
- Wikipedia / rich HTML display fixes (`display:none`, `<pre>`, `<hr>`)
- Over 800 automated tests for production reliability

### v1.0.0 (February 2026)
- Initial stable release
- Full HTML rendering support
- CSS styling with design tokens
- Plugin architecture with clipboard support
- Cross-platform (iOS, Android, Web, Desktop)

---

## Getting Help

For the current v1.4.0 release:
- See [README](../README.md) for usage
- Check [CHANGELOG](../CHANGELOG.md) for version history
- Review [Plugin Development Guide](PLUGIN_DEVELOPMENT.md) for extending
- File issues at [GitHub Issues](https://github.com/brewkits/hyper_render/issues)

---

*Last Updated: June 24, 2026 for v1.4.0*
