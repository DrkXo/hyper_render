import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'inspector_data.dart';
import 'udt_serializer.dart';

// Import hyper_render_core model types
import 'package:hyper_render_core/hyper_render_core.dart';

/// Registry for [RenderHyperBox] instances for DevTools inspection.
///
/// Each [RenderHyperBox] registers itself automatically via
/// [HyperRenderDebugHooks] when [HyperRenderDevtools.register] has been called.
class _HyperRenderRegistry {
  static final _HyperRenderRegistry instance = _HyperRenderRegistry._();
  _HyperRenderRegistry._();

  final Map<String, _RendererInfo> _renderers = {};

  void register(String id, DocumentNode? Function() getDocument) {
    _renderers[id] = _RendererInfo(id: id, getDocument: getDocument);
  }

  void unregister(String id) {
    _renderers.remove(id);
    timing.remove(id);
    _selections.remove(id);
  }

  final TimingBuffer timing = TimingBuffer();
  final Map<String, ({int? start, int? end})> _selections = {};

  void updateSelection(String id, int? start, int? end) {
    _selections[id] = (start: start, end: end);
  }

  ({int? start, int? end}) getSelection(String id) =>
      _selections[id] ?? (start: null, end: null);

  void updateLayout(
    String id,
    List<Map<String, dynamic>> fragments,
    List<Map<String, dynamic>> lines,
  ) {
    final info = _renderers[id];
    if (info == null) return;
    info.lastFragments = fragments;
    info.lastLines = lines;
  }

  List<String> get registeredIds => _renderers.keys.toList();

  DocumentNode? getDocument(String id) => _renderers[id]?.getDocument();

  List<Map<String, dynamic>>? getFragments(String id) =>
      _renderers[id]?.lastFragments;

  List<Map<String, dynamic>>? getLines(String id) => _renderers[id]?.lastLines;
}

class _RendererInfo {
  final String id;
  final DocumentNode? Function() getDocument;
  List<Map<String, dynamic>>? lastFragments;
  List<Map<String, dynamic>>? lastLines;

  _RendererInfo({required this.id, required this.getDocument});
}

/// DevTools integration for HyperRender.
///
/// Registers VM service extensions that the DevTools panel uses to inspect
/// UDT trees, computed styles, fragments, and performance data.
///
/// ## Setup (once at app startup, debug mode only)
/// ```dart
/// void main() {
///   assert(() {
///     HyperRenderDevtools.register();
///     return true;
///   }());
///   runApp(const MyApp());
/// }
/// ```
///
/// After calling [register], all [HyperViewer] / [HyperRenderWidget] instances
/// are tracked automatically — no per-widget setup required.
class HyperRenderDevtools {
  static bool _registered = false;

  /// Register VM service extensions and wire up the auto-registration hooks.
  ///
  /// Safe to call multiple times — only registers once.
  static void register() {
    if (_registered || !kDebugMode) return;
    _registered = true;

    // ── Hook into RenderHyperBox lifecycle ──────────────────────────────────
    // HyperRenderDebugHooks are static callbacks in hyper_render_core that
    // RenderHyperBox calls in attach/detach/performLayout.  By injecting here
    // we avoid any circular package dependency.

    HyperRenderDebugHooks.onRendererAttached = (id, getDocument) {
      _HyperRenderRegistry.instance.register(id, getDocument);
    };

    HyperRenderDebugHooks.onRendererDetached = (id) {
      _HyperRenderRegistry.instance.unregister(id);
    };

    HyperRenderDebugHooks.onLayoutComplete = (id, getFragments, getLines) {
      _HyperRenderRegistry.instance.updateLayout(
        id,
        getFragments(),
        getLines(),
      );
    };

    HyperRenderDebugHooks.onFrameTiming = (id, phase, micros) {
      _HyperRenderRegistry.instance.timing.add(
        id,
        TimingSample(phase, micros, DateTime.now().millisecondsSinceEpoch),
      );
    };

    HyperRenderDebugHooks.onSelectionChanged = (id, start, end) {
      _HyperRenderRegistry.instance.updateSelection(id, start, end);
    };

    // ── Service extension: list all active renderers ─────────────────────────
    developer.registerExtension(
      'ext.hyperRender.listRenderers',
      (method, parameters) async {
        final ids = _HyperRenderRegistry.instance.registeredIds;
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'renderers': ids}),
        );
      },
    );

    // ── Service extension: get UDT tree for a renderer ───────────────────────
    developer.registerExtension(
      'ext.hyperRender.getUdt',
      (method, parameters) async {
        final id = parameters['id'] ??
            _HyperRenderRegistry.instance.registeredIds.firstOrNull ??
            '';
        final document = _HyperRenderRegistry.instance.getDocument(id);
        if (document == null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            'No renderer found with id: $id',
          );
        }
        final tree = UdtSerializer.serializeTree(document);
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'id': id, 'tree': tree}),
        );
      },
    );

    // ── Service extension: get computed style for a specific node ────────────
    developer.registerExtension(
      'ext.hyperRender.getNodeStyle',
      (method, parameters) async {
        final rendererId = parameters['rendererId'] ?? '';
        final nodeId = parameters['nodeId'] ?? '';
        final document = _HyperRenderRegistry.instance.getDocument(rendererId);
        if (document == null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            'Renderer not found: $rendererId',
          );
        }
        final node = document.findById(nodeId);
        if (node == null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            'Node not found: $nodeId',
          );
        }
        final style = UdtSerializer.serializeStyle(node.style);
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'nodeId': nodeId, 'style': style}),
        );
      },
    );

    // ── Service extension: get fragment + line layout data ───────────────────
    developer.registerExtension(
      'ext.hyperRender.getFragments',
      (method, parameters) async {
        final id = parameters['id'] ??
            _HyperRenderRegistry.instance.registeredIds.firstOrNull ??
            '';
        final fragments = _HyperRenderRegistry.instance.getFragments(id);
        final lines = _HyperRenderRegistry.instance.getLines(id);
        if (fragments == null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            'No layout data for renderer: $id. '
            'Ensure HyperRenderDevtools.register() was called before the '
            'first layout pass.',
          );
        }
        return developer.ServiceExtensionResponse.result(
          jsonEncode({
            'id': id,
            'fragmentCount': fragments.length,
            'lineCount': lines?.length ?? 0,
            'fragments': fragments,
            'lines': lines ?? [],
          }),
        );
      },
    );

    // ── Service extension: get performance data ──────────────────────────────
    developer.registerExtension(
      'ext.hyperRender.getPerformance',
      (method, parameters) async {
        final id = parameters['id'] ??
            _HyperRenderRegistry.instance.registeredIds.firstOrNull ??
            '';
        final data = HyperRenderDebugHooks.getPerformanceData?.call(id);
        if (data == null) {
          // Return summary stats derived from fragment/line counts as a
          // lightweight fallback when no PerformanceMonitor is wired.
          final fragments =
              _HyperRenderRegistry.instance.getFragments(id) ?? [];
          final lines = _HyperRenderRegistry.instance.getLines(id) ?? [];
          return developer.ServiceExtensionResponse.result(
            jsonEncode({
              'id': id,
              'fragmentCount': fragments.length,
              'lineCount': lines.length,
              'note': 'Wire HyperRenderDebugHooks.getPerformanceData for '
                  'full timing data.',
            }),
          );
        }
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'id': id, 'performance': data}),
        );
      },
    );

    // ── Service extension: layout/paint timeline (all renderers) ─────────────
    // Every virtualized chunk is its own renderer, so returning all of them
    // is what makes the timeline "per chunk". Pass `id` to narrow it.
    developer.registerExtension(
      'ext.hyperRender.getTimeline',
      (method, parameters) async {
        return developer.ServiceExtensionResponse.result(
          jsonEncode({
            'renderers': _HyperRenderRegistry.instance.timing
                .toJson(onlyId: parameters['id']),
          }),
        );
      },
    );

    // ── Service extension: current text selection of a renderer ─────────────
    developer.registerExtension(
      'ext.hyperRender.getSelection',
      (method, parameters) async {
        final id = parameters['id'] ??
            _HyperRenderRegistry.instance.registeredIds.firstOrNull ??
            '';
        final sel = _HyperRenderRegistry.instance.getSelection(id);
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'id': id, 'start': sel.start, 'end': sel.end}),
        );
      },
    );

    // ── Service extension: CSS custom property definition sites ──────────────
    developer.registerExtension(
      'ext.hyperRender.getCssVariables',
      (method, parameters) async {
        final id = parameters['id'] ??
            _HyperRenderRegistry.instance.registeredIds.firstOrNull ??
            '';
        final document = _HyperRenderRegistry.instance.getDocument(id);
        if (document == null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            'No renderer found with id: $id',
          );
        }
        return developer.ServiceExtensionResponse.result(
          jsonEncode({
            'id': id,
            'variables': collectCssVariables(document),
            'overrides': HyperRenderDebugHooks.cssVariableOverrides.value,
          }),
        );
      },
    );

    // ── Service extension: live-edit a CSS custom property ───────────────────
    // Every HyperViewer re-resolves its styles with the override. An empty
    // or missing `value` removes the override; `name: '*'` clears them all.
    developer.registerExtension(
      'ext.hyperRender.setCssVariable',
      (method, parameters) async {
        final name = parameters['name'] ?? '';
        final value = parameters['value'] ?? '';
        final next = name == '*'
            ? const <String, String>{}
            : applyCssVariableOverride(
                HyperRenderDebugHooks.cssVariableOverrides.value,
                name,
                value,
              );
        if (next == null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.invalidParams,
            'CSS variable names must start with "--" (got "$name")',
          );
        }
        HyperRenderDebugHooks.cssVariableOverrides.value = next;
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'overrides': next}),
        );
      },
    );

    // ── Service extension: full snapshot for offline analysis ────────────────
    developer.registerExtension(
      'ext.hyperRender.exportSnapshot',
      (method, parameters) async {
        final registry = _HyperRenderRegistry.instance;
        final id = parameters['id'] ?? registry.registeredIds.firstOrNull ?? '';
        final document = registry.getDocument(id);
        if (document == null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            'No renderer found with id: $id',
          );
        }
        return developer.ServiceExtensionResponse.result(
          jsonEncode(buildSnapshot(
            id: id,
            document: document,
            fragments: registry.getFragments(id) ?? const [],
            lines: registry.getLines(id) ?? const [],
            selection: registry.getSelection(id),
            timing: registry.timing.samplesFor(id),
          )),
        );
      },
    );

    debugPrint(
      '[HyperRender DevTools] Service extensions registered: '
      'ext.hyperRender.{listRenderers, getUdt, getNodeStyle, '
      'getFragments, getPerformance}',
    );
  }

  // ── Legacy manual API (kept for back-compat) ─────────────────────────────

  /// Manually register a renderer for inspection.
  ///
  /// Not needed when [register] has been called — renderers auto-register
  /// via [HyperRenderDebugHooks].  Only use this if you need to expose a
  /// custom document source that doesn't go through [RenderHyperBox].
  static void registerRenderer(
    String id,
    DocumentNode Function() getDocument,
  ) {
    if (!kDebugMode) return;
    _HyperRenderRegistry.instance.register(id, getDocument);
  }

  /// Manually unregister a renderer.
  static void unregisterRenderer(String id) {
    if (!kDebugMode) return;
    _HyperRenderRegistry.instance.unregister(id);
  }
}

extension on List<String> {
  String? get firstOrNull => isEmpty ? null : first;
}
