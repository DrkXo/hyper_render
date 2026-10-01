/// Pure-Dart helpers behind the Timeline and Selection tabs, kept out of
/// the widget code so they can be unit-tested without a VM service.
library;

/// Aggregate of one phase's samples for one renderer.
class PhaseStats {
  final int count;
  final int avgMicros;
  final int maxMicros;
  final int lastMicros;

  const PhaseStats({
    required this.count,
    required this.avgMicros,
    required this.maxMicros,
    required this.lastMicros,
  });

  static PhaseStats? of(List<int> micros) {
    if (micros.isEmpty) return null;
    var sum = 0;
    var max = 0;
    for (final m in micros) {
      sum += m;
      if (m > max) max = m;
    }
    return PhaseStats(
      count: micros.length,
      avgMicros: sum ~/ micros.length,
      maxMicros: max,
      lastMicros: micros.last,
    );
  }
}

/// Layout + paint timing for one renderer (one virtualized chunk).
class RendererTiming {
  final String id;
  final PhaseStats? layout;
  final PhaseStats? paint;

  /// Paint durations oldest → newest, for the sparkline.
  final List<int> paintHistory;

  const RendererTiming({
    required this.id,
    this.layout,
    this.paint,
    this.paintHistory = const [],
  });

  /// Worst single layout + worst single paint — what ranks a chunk as slow.
  int get worstMicros => (layout?.maxMicros ?? 0) + (paint?.maxMicros ?? 0);
}

/// Summarise the `renderers` map from `ext.hyperRender.getTimeline`
/// (`{id: [{phase, micros, t}, ...]}`), slowest renderer first.
List<RendererTiming> summarizeTimeline(Map<String, dynamic> renderers) {
  final out = <RendererTiming>[];
  renderers.forEach((id, raw) {
    final layout = <int>[];
    final paint = <int>[];
    for (final s in (raw as List? ?? const [])) {
      final m = s as Map;
      final micros = (m['micros'] as num?)?.toInt() ?? 0;
      if (m['phase'] == 'layout') {
        layout.add(micros);
      } else if (m['phase'] == 'paint') {
        paint.add(micros);
      }
    }
    out.add(RendererTiming(
      id: id,
      layout: PhaseStats.of(layout),
      paint: PhaseStats.of(paint),
      paintHistory: paint,
    ));
  });
  out.sort((a, b) => b.worstMicros.compareTo(a.worstMicros));
  return out;
}

/// `1234` → `1.23 ms`, `456` → `456 µs`.
String formatMicros(int? micros) {
  if (micros == null) return '—';
  if (micros >= 1000) return '${(micros / 1000).toStringAsFixed(2)} ms';
  return '$micros µs';
}

/// A text/ruby fragment's character range, and the part of it (if any)
/// covered by the current selection.
class FragmentSpan {
  final int index;
  final Map<String, dynamic> fragment;

  /// Global character range `[start, end)` — the same coordinate space
  /// as the renderer's selection offsets.
  final int start;
  final int end;

  /// Selected sub-range in fragment-local offsets, or null if unselected.
  final int? selectedFrom;
  final int? selectedTo;

  const FragmentSpan({
    required this.index,
    required this.fragment,
    required this.start,
    required this.end,
    this.selectedFrom,
    this.selectedTo,
  });

  bool get isSelected => selectedFrom != null;
  bool get isRuby => fragment['type'] == 'ruby';
}

/// Character-addressable fragments (text + ruby, the ones selection counts)
/// with their boundaries and selection overlap. Mirrors
/// `RenderHyperBox.getSelectedText`: a fragment covers
/// `[globalOffset, globalOffset + charLength)`.
List<FragmentSpan> fragmentSpans(
  List<dynamic> fragments, {
  int? selectionStart,
  int? selectionEnd,
}) {
  final hasSelection = selectionStart != null &&
      selectionEnd != null &&
      selectionEnd > selectionStart;
  final out = <FragmentSpan>[];
  for (var i = 0; i < fragments.length; i++) {
    final f = (fragments[i] as Map).cast<String, dynamic>();
    final type = f['type'];
    if (type != 'text' && type != 'ruby') continue;
    final start = (f['globalOffset'] as num?)?.toInt();
    final length = (f['charLength'] as num?)?.toInt() ?? 0;
    if (start == null || length == 0) continue;
    final end = start + length;
    int? from;
    int? to;
    if (hasSelection && end > selectionStart && start < selectionEnd) {
      from = (selectionStart - start).clamp(0, length);
      to = (selectionEnd - start).clamp(0, length);
    }
    out.add(FragmentSpan(
      index: i,
      fragment: f,
      start: start,
      end: end,
      selectedFrom: from,
      selectedTo: to,
    ));
  }
  return out;
}
