import 'package:hyper_render_core/hyper_render_core.dart';

import 'udt_serializer.dart';

/// One layout or paint measurement for a renderer.
class TimingSample {
  /// `'layout'` or `'paint'` (paint = canvas recording, not raster).
  final String phase;
  final int micros;

  /// Wall-clock capture time, ms since epoch — lets the panel line up
  /// samples from different renderers (virtualized chunks) on one axis.
  final int timestampMs;

  const TimingSample(this.phase, this.micros, this.timestampMs);

  Map<String, dynamic> toJson() =>
      {'phase': phase, 'micros': micros, 't': timestampMs};
}

/// Fixed-size per-renderer history of [TimingSample]s.
///
/// Paint fires every frame while anything animates, so the buffer must not
/// grow without bound — the oldest sample is dropped once [capacity] is hit.
class TimingBuffer {
  final int capacity;
  final Map<String, List<TimingSample>> _samples = {};

  TimingBuffer({this.capacity = 120});

  void add(String id, TimingSample sample) {
    final list = _samples.putIfAbsent(id, () => []);
    if (list.length >= capacity) list.removeAt(0);
    list.add(sample);
  }

  void remove(String id) => _samples.remove(id);

  List<TimingSample> samplesFor(String id) =>
      List.unmodifiable(_samples[id] ?? const []);

  Map<String, dynamic> toJson({String? onlyId}) => {
        for (final e in _samples.entries)
          if (onlyId == null || e.key == onlyId)
            e.key: e.value.map((s) => s.toJson()).toList(),
      };
}

/// Where each CSS custom property is *defined* in a resolved document.
///
/// Custom properties inherit, so every descendant carries a copy; a node
/// counts as a definition site only when its value differs from its
/// parent's (or the parent lacks it). `var()` references are substituted
/// at resolve time, so use sites are not recoverable from the UDT.
List<Map<String, dynamic>> collectCssVariables(DocumentNode document) {
  final out = <Map<String, dynamic>>[];
  void walk(UDTNode node, Map<String, String> inherited) {
    final own = node.style.customProperties;
    own.forEach((name, value) {
      if (inherited[name] != value) {
        out.add({
          'name': name,
          'value': value,
          'nodeId': node.id,
          'nodeTag': node.tagName ?? node.type.name,
        });
      }
    });
    for (final child in node.children) {
      walk(child, own);
    }
  }

  walk(document, const {});
  return out;
}

/// The override map after setting `name` to `value` — a new map, so the
/// `ValueNotifier` holding it notifies. An empty [value] removes the
/// override. Returns null when [name] is not a custom property.
Map<String, String>? applyCssVariableOverride(
  Map<String, String> current,
  String name,
  String value,
) {
  if (!name.startsWith('--') || name.length < 3) return null;
  final next = Map<String, String>.of(current);
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    next.remove(name);
  } else {
    next[name] = trimmed;
  }
  return Map.unmodifiable(next);
}

/// Everything the inspector knows about one renderer, as a single
/// self-describing JSON object for offline analysis.
Map<String, dynamic> buildSnapshot({
  required String id,
  required DocumentNode document,
  required List<Map<String, dynamic>> fragments,
  required List<Map<String, dynamic>> lines,
  required ({int? start, int? end}) selection,
  required List<TimingSample> timing,
  DateTime? capturedAt,
}) {
  return {
    'schema': 'hyper_render_devtools.snapshot/1',
    'rendererId': id,
    'capturedAt': (capturedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'tree': UdtSerializer.serializeTree(document),
    'fragments': fragments,
    'lines': lines,
    'selection': {'start': selection.start, 'end': selection.end},
    'timing': timing.map((s) => s.toJson()).toList(),
    'cssVariables': collectCssVariables(document),
  };
}
