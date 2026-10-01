import 'dart:async';
import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/inspector_logic.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Demo / sample data (shown when no real app is connected)
// ─────────────────────────────────────────────────────────────────────────────

const _kDemoRendererId = 'demo-renderer';

final _kDemoUdtTree = <String, dynamic>{
  'id': 'doc-0',
  'type': 'document',
  'tagName': '#document',
  'attributes': <String, String>{},
  'style': <String, dynamic>{},
  'childCount': 3,
  'children': [
    {
      'id': 'h1-1',
      'type': 'block',
      'tagName': 'h1',
      'attributes': <String, String>{},
      'style': <String, dynamic>{'fontSize': 28.0, 'fontWeight': 7},
      'childCount': 1,
      'children': [
        {
          'id': 'text-2',
          'type': 'text',
          'tagName': '(text)',
          'text': 'HyperRender DevTools Inspector',
          'attributes': <String, String>{},
          'style': <String, dynamic>{},
          'childCount': 0,
          'children': <dynamic>[],
        }
      ],
    },
    {
      'id': 'p-3',
      'type': 'block',
      'tagName': 'p',
      'attributes': <String, String>{},
      'style': <String, dynamic>{
        'fontSize': 16.0,
        'lineHeight': 1.6,
        'margin': {'top': 8.0, 'right': 0.0, 'bottom': 8.0, 'left': 0.0},
      },
      'childCount': 2,
      'children': [
        {
          'id': 'text-4',
          'type': 'text',
          'tagName': '(text)',
          'text': 'This is a ',
          'attributes': <String, String>{},
          'style': <String, dynamic>{},
          'childCount': 0,
          'children': <dynamic>[],
        },
        {
          'id': 'strong-5',
          'type': 'inline',
          'tagName': 'strong',
          'attributes': <String, String>{},
          'style': <String, dynamic>{'fontWeight': 7},
          'childCount': 1,
          'children': [
            {
              'id': 'text-6',
              'type': 'text',
              'tagName': '(text)',
              'text': 'demo document',
              'attributes': <String, String>{},
              'style': <String, dynamic>{},
              'childCount': 0,
              'children': <dynamic>[],
            }
          ],
        },
      ],
    },
    {
      'id': 'div-7',
      'type': 'block',
      'tagName': 'div',
      'attributes': <String, String>{'class': 'float-container'},
      'style': <String, dynamic>{
        'float': 'left',
        'width': 200.0,
        'margin': {'top': 0.0, 'right': 12.0, 'bottom': 0.0, 'left': 0.0},
        'backgroundColor': 0xFFE3F2FD,
        'borderRadius': 'BorderRadius.circular(8.0)',
        'padding': {'top': 8.0, 'right': 8.0, 'bottom': 8.0, 'left': 8.0},
      },
      'childCount': 1,
      'children': [
        {
          'id': 'img-8',
          'type': 'atomic',
          'tagName': 'img',
          'src': 'https://example.com/cover.jpg',
          'alt': 'Book cover',
          'intrinsicWidth': 200.0,
          'intrinsicHeight': 300.0,
          'attributes': <String, String>{
            'src': 'https://example.com/cover.jpg',
            'alt': 'Book cover',
          },
          'style': <String, dynamic>{},
          'childCount': 0,
          'children': <dynamic>[],
        }
      ],
    },
  ],
};

final _kDemoFragments = () {
  final types = ['text', 'inline', 'block', 'image', 'text', 'ruby'];
  var offset = 0;
  return List.generate(12, (i) {
    final type = types[i % types.length];
    final text = type == 'ruby'
        ? '漢字'
        : (type == 'text' ? 'Sample text fragment $i ' : null);
    final length = text?.length ?? 0;
    final fragment = <String, dynamic>{
      'type': type,
      'text': text,
      'width': 80.0 + (i * 13.7) % 200,
      'height': 18.0 + (i * 3.1) % 10,
      'offsetX': (i % 4) * 90.0,
      'offsetY': (i ~/ 4) * 24.0,
      'globalOffset': offset,
      'charLength': length,
      if (type == 'ruby') 'rubyText': 'かんじ',
      if (type == 'ruby') 'rubyHeight': 9.0,
    };
    offset += length;
    return fragment;
  });
}();

/// Demo selection spanning the end of fragment 0 into fragment 4.
const _kDemoSelection = (start: 12, end: 40);

final _kDemoTimeline = <String, dynamic>{
  _kDemoRendererId: List.generate(
    24,
    (i) => {
      'phase': i % 6 == 0 ? 'layout' : 'paint',
      'micros': i % 6 == 0 ? 2400 + i * 40 : 180 + (i * 37) % 260,
      't': i * 16,
    },
  ),
  'demo-chunk-2': List.generate(
    12,
    (i) => {
      'phase': i.isEven ? 'layout' : 'paint',
      'micros': i.isEven ? 900 : 120,
      't': i * 16,
    },
  ),
};

final _kDemoCssVariables = <Map<String, dynamic>>[
  {
    'name': '--brand',
    'value': '#3F51B5',
    'nodeId': 'doc',
    'nodeTag': 'document'
  },
  {'name': '--gap', 'value': '12px', 'nodeId': 'doc', 'nodeTag': 'document'},
  {'name': '--brand', 'value': '#E91E63', 'nodeId': 'p-1', 'nodeTag': 'p'},
];

final _kDemoLines = List.generate(
    4,
    (i) => <String, dynamic>{
          'fragmentCount': 3 + i,
          'top': i * 24.0,
          'height': 22.0,
          'baseline': 17.0,
        });

final _kDemoStyle = <String, dynamic>{
  'display': 'block',
  'fontSize': 28.0,
  'fontWeight': 7,
  'fontStyle': 0,
  'fontFamily': null,
  'color': 0xFF212121,
  'lineHeight': 1.2,
  'letterSpacing': 0.0,
  'textAlign': 'start',
  'float': 'none',
  'opacity': 1.0,
  'margin': {'top': 16.0, 'right': 0.0, 'bottom': 12.0, 'left': 0.0},
  'padding': {'top': 0.0, 'right': 0.0, 'bottom': 0.0, 'left': 0.0},
  'width': null,
  'height': null,
};

void main() {
  runApp(const HyperRenderInspectorApp());
}

class HyperRenderInspectorApp extends StatelessWidget {
  const HyperRenderInspectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DevToolsExtension(
      child: MaterialApp(
        title: 'HyperRender Inspector',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1976D2),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: const InspectorShell(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shell
// ─────────────────────────────────────────────────────────────────────────────

class InspectorShell extends StatefulWidget {
  const InspectorShell({super.key});

  @override
  State<InspectorShell> createState() => _InspectorShellState();
}

class _InspectorShellState extends State<InspectorShell>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // ── State ────────────────────────────────────────────────────────────────
  List<String> _rendererIds = [];
  String? _selectedRendererId;

  Map<String, dynamic>? _udtTree;
  Map<String, dynamic>? _selectedNodeStyle;
  String? _selectedNodeId;

  List<dynamic> _fragments = [];
  List<dynamic> _lines = [];

  Map<String, dynamic>? _perfData;

  /// `{rendererId: [{phase, micros, t}]}` from ext.hyperRender.getTimeline.
  Map<String, dynamic> _timeline = {};
  ({int? start, int? end}) _selection = (start: null, end: null);
  List<Map<String, dynamic>> _cssVariables = [];

  /// Live `--var` overrides currently applied in the app.
  Map<String, String> _cssOverrides = {};

  /// Polls the timeline + selection once a second while enabled.
  Timer? _liveTimer;

  bool _loading = false;
  String? _error;

  // Demo mode — shows sample data when no real app is connected.
  bool _demoMode = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _refresh();
  }

  void _enterDemoMode() {
    setState(() {
      _demoMode = true;
      _error = null;
      _rendererIds = [_kDemoRendererId];
      _selectedRendererId = _kDemoRendererId;
      _udtTree = _kDemoUdtTree;
      _fragments = _kDemoFragments;
      _lines = _kDemoLines;
      _selectedNodeStyle = _kDemoStyle;
      _selectedNodeId = 'h1-1';
      _timeline = _kDemoTimeline;
      _selection = _kDemoSelection;
      _cssVariables = [..._kDemoCssVariables];
      _cssOverrides = {};
      _loading = false;
    });
    _tabs.animateTo(0);
  }

  void _exitDemoMode() {
    _setLive(false);
    setState(() {
      _demoMode = false;
      _rendererIds = [];
      _selectedRendererId = null;
      _udtTree = null;
      _fragments = [];
      _lines = [];
      _selectedNodeStyle = null;
      _selectedNodeId = null;
      _perfData = null;
      _timeline = {};
      _selection = (start: null, end: null);
      _cssVariables = [];
      _cssOverrides = {};
    });
    _refresh();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  // ── Service extension helpers ─────────────────────────────────────────────

  Future<Map<String, dynamic>?> _call(
    String method, [
    Map<String, Object> args = const {},
  ]) async {
    try {
      final result = await serviceManager.callServiceExtensionOnMainIsolate(
        method,
        args: args,
      );
      // vm_service has already unwrapped the JSON-RPC envelope: `json` IS
      // the object the extension passed to ServiceExtensionResponse.result
      // (e.g. {'renderers': [...]}), not a wrapper holding it under 'result'.
      return result.json;
    } catch (e) {
      return {'_error': e.toString()};
    }
  }

  // ── Refresh flow ─────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. List renderers
      final listResult = await _call('ext.hyperRender.listRenderers');
      if (listResult == null || listResult.containsKey('_error')) {
        setState(() {
          _loading = false;
          _error = listResult?['_error'] as String? ??
              'Could not connect to app. '
                  'Ensure HyperRenderDevtools.register() is called at startup.';
        });
        return;
      }
      final ids =
          (listResult['renderers'] as List?)?.cast<String>() ?? <String>[];

      // 2. Select first renderer if none selected yet
      final selectedId =
          (_selectedRendererId != null && ids.contains(_selectedRendererId))
              ? _selectedRendererId
              : ids.firstOrNull;

      setState(() {
        _rendererIds = ids;
        _selectedRendererId = selectedId;
      });

      if (selectedId != null) await _loadRenderer(selectedId);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadRenderer(String id) => Future.wait([
        _loadUdt(id),
        _loadFragments(id),
        _loadPerformance(id),
        _loadTimeline(),
        _loadSelection(id),
        _loadCssVariables(id),
      ]);

  Future<void> _loadTimeline() async {
    final result = await _call('ext.hyperRender.getTimeline');
    if (result != null && !result.containsKey('_error')) {
      setState(
          () => _timeline = result['renderers'] as Map<String, dynamic>? ?? {});
    }
  }

  Future<void> _loadSelection(String id) async {
    final result = await _call('ext.hyperRender.getSelection', {'id': id});
    if (result != null && !result.containsKey('_error')) {
      setState(() => _selection = (
            start: (result['start'] as num?)?.toInt(),
            end: (result['end'] as num?)?.toInt(),
          ));
    }
  }

  Future<void> _loadCssVariables(String id) async {
    final result = await _call('ext.hyperRender.getCssVariables', {'id': id});
    if (result != null && !result.containsKey('_error')) {
      setState(() {
        _cssVariables =
            ((result['variables'] as List?) ?? []).cast<Map<String, dynamic>>();
        _cssOverrides =
            ((result['overrides'] as Map?) ?? {}).cast<String, String>();
      });
    }
  }

  /// Set (or with an empty [value], remove) a live `--var` override. Pass
  /// `'*'` as [name] to clear every override.
  Future<void> _setCssVariable(String name, String value) async {
    if (_demoMode) {
      // Demo: rewrite the sample definition sites in place.
      setState(() {
        if (name == '*') {
          _cssOverrides = {};
        } else if (value.trim().isEmpty) {
          _cssOverrides = {..._cssOverrides}..remove(name);
        } else {
          _cssOverrides = {..._cssOverrides, name: value.trim()};
        }
        _cssVariables = [
          for (final v in _kDemoCssVariables)
            {...v, 'value': _cssOverrides[v['name']] ?? v['value']},
        ];
      });
      return;
    }
    final result = await _call(
      'ext.hyperRender.setCssVariable',
      {'name': name, 'value': value},
    );
    if (!mounted) return;
    if (result == null || result.containsKey('_error')) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not set $name: ${result?['_error']}')));
      return;
    }
    // The app re-parses; virtualized chunks come back as new renderers, so
    // reload the renderer list rather than just this renderer.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) await _refresh();
  }

  Future<void> _editCssVariable(String name, String current) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) =>
          _CssVariableEditDialog(name: name, initialValue: current),
    );
    if (value != null) await _setCssVariable(name, value);
  }

  void _setLive(bool live) {
    _liveTimer?.cancel();
    _liveTimer = null;
    if (live && !_demoMode) {
      _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final id = _selectedRendererId;
        // Fragments too: the selection panel maps offsets onto them, and
        // a relayout (resize, new content) changes their boundaries.
        _loadTimeline();
        if (id != null) {
          _loadSelection(id);
          _loadFragments(id);
        }
      });
    }
    setState(() {});
  }

  // ── Export ───────────────────────────────────────────────────────────────

  Future<void> _exportSnapshot() async {
    final id = _selectedRendererId;
    if (id == null) return;
    Map<String, dynamic>? snapshot;
    if (_demoMode) {
      snapshot = {
        'schema': 'hyper_render_devtools.snapshot/1',
        'rendererId': id,
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'tree': [_udtTree],
        'fragments': _fragments,
        'lines': _lines,
        'selection': {'start': _selection.start, 'end': _selection.end},
        'timing': _timeline[id] ?? [],
        'cssVariables': _cssVariables,
      };
    } else {
      snapshot = await _call('ext.hyperRender.exportSnapshot', {'id': id});
    }
    if (!mounted || snapshot == null) return;
    if (snapshot.containsKey('_error')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: ${snapshot['_error']}')),
      );
      return;
    }
    final json = const JsonEncoder.withIndent('  ').convert(snapshot);
    await showDialog<void>(
      context: context,
      builder: (context) => _SnapshotDialog(json: json, rendererId: id),
    );
  }

  Future<void> _loadUdt(String id) async {
    final result = await _call('ext.hyperRender.getUdt', {'id': id});
    if (result != null && !result.containsKey('_error')) {
      final treeList = result['tree'] as List?;
      setState(() {
        _udtTree = treeList?.isNotEmpty == true
            ? treeList!.first as Map<String, dynamic>
            : null;
        _selectedNodeStyle = null;
        _selectedNodeId = null;
      });
    }
  }

  Future<void> _loadFragments(String id) async {
    final result = await _call('ext.hyperRender.getFragments', {'id': id});
    if (result != null && !result.containsKey('_error')) {
      setState(() {
        _fragments = result['fragments'] as List? ?? [];
        _lines = result['lines'] as List? ?? [];
      });
    }
  }

  Future<void> _loadPerformance(String id) async {
    final result = await _call('ext.hyperRender.getPerformance', {'id': id});
    if (result != null && !result.containsKey('_error')) {
      setState(() => _perfData = result);
    }
  }

  Future<void> _loadNodeStyle(String rendererId, String nodeId) async {
    final result = await _call(
      'ext.hyperRender.getNodeStyle',
      {'rendererId': rendererId, 'nodeId': nodeId},
    );
    if (result != null && !result.containsKey('_error')) {
      setState(() {
        _selectedNodeStyle = result['style'] as Map<String, dynamic>?;
        _selectedNodeId = nodeId;
        _tabs.animateTo(1);
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.account_tree, size: 20),
            const SizedBox(width: 8),
            const Text('HyperRender Inspector'),
            const SizedBox(width: 16),
            if (_rendererIds.isNotEmpty)
              _RendererDropdown(
                ids: _rendererIds,
                selectedId: _selectedRendererId,
                onChanged: (id) {
                  setState(() => _selectedRendererId = id);
                  if (id != null && !_demoMode) _loadRenderer(id);
                },
              ),
            const Spacer(),
            if (_demoMode)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Chip(
                  label: const Text('DEMO', style: TextStyle(fontSize: 11)),
                  backgroundColor: Colors.amber.shade100,
                  side: BorderSide(color: Colors.amber.shade400),
                  onDeleted: _exitDemoMode,
                  deleteIcon: const Icon(Icons.close, size: 14),
                ),
              )
            else
              TextButton.icon(
                onPressed: _enterDemoMode,
                icon: const Icon(Icons.play_circle_outline, size: 16),
                label: const Text('Demo', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.amber.shade800,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export UDT snapshot (JSON)',
              onPressed: _selectedRendererId == null ? null : _exportSnapshot,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _demoMode ? null : _refresh,
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.account_tree, size: 16), text: 'UDT Tree'),
            Tab(icon: Icon(Icons.style, size: 16), text: 'Style'),
            Tab(icon: Icon(Icons.view_list, size: 16), text: 'Layout'),
            Tab(icon: Icon(Icons.timeline, size: 16), text: 'Timeline'),
            Tab(icon: Icon(Icons.select_all, size: 16), text: 'Selection'),
            Tab(icon: Icon(Icons.data_object, size: 16), text: 'CSS Vars'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _rendererIds.isEmpty
                  ? _buildNoRenderers()
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _buildTreeView(),
                        _buildStyleView(),
                        _buildLayoutView(),
                        _buildTimelineView(),
                        _buildSelectionView(),
                        _buildCssVariablesView(),
                      ],
                    ),
    );
  }

  Widget _buildNoRenderers() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No active HyperRender renderers found.\n\n'
            'Make sure your app calls:\n'
            'HyperRenderDevtools.register()\n'
            'at startup in debug mode.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _enterDemoMode,
                icon: const Icon(Icons.play_circle_outline, size: 16),
                label: const Text('Try Demo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amber.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Demo mode loads sample data so you can explore the inspector\n'
              'without a live HyperRender app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // ── UDT Tree tab ──────────────────────────────────────────────────────────

  Widget _buildTreeView() {
    if (_udtTree == null) {
      return const Center(
        child: Text(
          'No document loaded.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.blue.shade50,
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.blue),
              SizedBox(width: 6),
              Text(
                'Click a node to inspect its computed style.',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: _UdtNodeWidget(
              node: _udtTree!,
              selectedId: _selectedNodeId,
              onSelected: (nodeId) {
                if (_selectedRendererId != null) {
                  _loadNodeStyle(_selectedRendererId!, nodeId);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Style tab ─────────────────────────────────────────────────────────────

  Widget _buildStyleView() {
    if (_selectedNodeStyle == null) {
      return const Center(
        child: Text(
          'Select a node in the UDT Tree tab\nto inspect its computed style.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _SectionHeader('Computed Style — Node: $_selectedNodeId'),
        ..._selectedNodeStyle!.entries
            .where((e) => e.value != null && e.value.toString() != 'null')
            .map((e) => _PropertyRow(name: e.key, value: e.value)),
      ],
    );
  }

  // ── Layout tab ────────────────────────────────────────────────────────────

  Widget _buildLayoutView() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        // Performance summary
        if (_perfData != null) ...[
          const _SectionHeader('Renderer'),
          _PropertyRow(name: 'id', value: _perfData!['id']),
          _PropertyRow(name: 'fragments', value: _perfData!['fragmentCount']),
          _PropertyRow(name: 'lines', value: _perfData!['lineCount']),
          if (_perfData!['note'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                _perfData!['note'] as String,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
        ],

        // Fragment list
        _SectionHeader('Fragments (${_fragments.length}) — last layout pass'),
        if (_fragments.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No fragments yet.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          )
        else
          ..._fragments
              .cast<Map<String, dynamic>>()
              .take(200) // cap at 200 rows to keep UI snappy
              .map((f) => _FragmentRow(fragment: f)),

        // Line list
        const SizedBox(height: 8),
        _SectionHeader('Lines (${_lines.length})'),
        if (_lines.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No lines yet.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          )
        else
          ..._lines.cast<Map<String, dynamic>>().map((l) => _LineRow(line: l)),

        const SizedBox(height: 16),
        const _InfoCard(
          title: 'Visual debug bounds',
          description:
              'HyperViewer(html: ..., debugShowHyperRenderBounds: true)\n'
              'Blue = line rows  •  Orange = inline fragments',
        ),
      ],
    );
  }

  Widget _liveToggle() {
    return Row(
      children: [
        const Text('Live (1s)', style: TextStyle(fontSize: 12)),
        Switch(
          value: _liveTimer != null,
          onChanged: _demoMode ? null : _setLive,
        ),
      ],
    );
  }

  // ── Timeline tab ──────────────────────────────────────────────────────────

  Widget _buildTimelineView() {
    final rows = summarizeTimeline(_timeline);
    final scale = rows.isEmpty
        ? 1
        : rows.map((r) => r.worstMicros).reduce((a, b) => a > b ? a : b);
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Row(
          children: [
            Expanded(
              child: _SectionHeader(
                  'Layout + paint per renderer (${rows.length}) — slowest first'),
            ),
            _liveToggle(),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Each virtualized chunk is its own renderer. Paint = canvas '
            'recording time on the UI thread (excludes GPU raster). '
            'Last 120 samples per renderer.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        if (rows.isEmpty)
          const Text(
              'No timing samples yet — interact with the app, then refresh.',
              style: TextStyle(color: Colors.grey, fontSize: 12))
        else
          ...rows.map((r) => _TimingRow(
                timing: r,
                scaleMicros: scale == 0 ? 1 : scale,
                selected: r.id == _selectedRendererId,
              )),
      ],
    );
  }

  // ── Selection tab ─────────────────────────────────────────────────────────

  Widget _buildSelectionView() {
    final spans = fragmentSpans(
      _fragments,
      selectionStart: _selection.start,
      selectionEnd: _selection.end,
    );
    final selected = spans.where((s) => s.isSelected).toList();
    final hasSelection = _selection.start != null &&
        _selection.end != null &&
        _selection.end! > _selection.start!;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeader('Selection')),
            _liveToggle(),
          ],
        ),
        _PropertyRow(
          name: 'range',
          value: hasSelection
              ? '[${_selection.start}, ${_selection.end})  '
                  '${_selection.end! - _selection.start!} chars, '
                  '${selected.length} fragments'
              : 'none — select text in the app',
        ),
        const SizedBox(height: 8),
        _SectionHeader(
            'Fragment boundaries (${spans.length} text/ruby fragments)'),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'Global character ranges [start, end) — the coordinate space '
            'selection offsets use. Highlighted = inside the selection.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        if (spans.isEmpty)
          const Text('No text fragments.',
              style: TextStyle(color: Colors.grey, fontSize: 12))
        else
          ...spans.take(300).map((s) => _FragmentSpanRow(span: s)),
      ],
    );
  }

  // ── CSS variables tab ─────────────────────────────────────────────────────

  Widget _buildCssVariablesView() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Row(
          children: [
            Expanded(
              child: _SectionHeader(
                  'CSS custom properties (${_cssVariables.length} '
                  'definition sites)'),
            ),
            if (_cssOverrides.isNotEmpty)
              TextButton.icon(
                onPressed: () => _setCssVariable('*', ''),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: Text('Reset ${_cssOverrides.length} override'
                    '${_cssOverrides.length == 1 ? '' : 's'}'),
              ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Each node where a --variable is defined or changes value. '
            'Click ✎ to override a variable live: every HyperViewer in the '
            'app re-resolves its styles. Use sites are not listed — var() '
            'is substituted when styles resolve.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        if (_cssVariables.isEmpty)
          const Text('No custom properties in this document.',
              style: TextStyle(color: Colors.grey, fontSize: 12))
        else
          ..._cssVariables.map((v) => _CssVariableRow(
                variable: v,
                overridden: _cssOverrides.containsKey(v['name']),
                onEdit: () => _editCssVariable(
                    v['name'] as String, v['value'] as String? ?? ''),
                onReset: () => _setCssVariable(v['name'] as String, ''),
                onTapNode: _demoMode || _selectedRendererId == null
                    ? null
                    : () => _loadNodeStyle(
                        _selectedRendererId!, v['nodeId'] as String),
              )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// v2 panels: timeline row, fragment span row, CSS variable row, export dialog
// ─────────────────────────────────────────────────────────────────────────────

class _TimingRow extends StatelessWidget {
  final RendererTiming timing;
  final int scaleMicros;
  final bool selected;

  const _TimingRow({
    required this.timing,
    required this.scaleMicros,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final layoutMax = timing.layout?.maxMicros ?? 0;
    final paintMax = timing.paint?.maxMicros ?? 0;
    String stats(PhaseStats? p) => p == null
        ? '—'
        : 'avg ${formatMicros(p.avgMicros)} · max ${formatMicros(p.maxMicros)}'
            ' · last ${formatMicros(p.lastMicros)} (${p.count})';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? Colors.indigo.shade300 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timing.id,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          // Stacked worst-case bar: layout (indigo) + paint (teal), scaled
          // against the slowest renderer so chunks compare at a glance.
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return Row(
              children: [
                Container(
                    width: w * layoutMax / scaleMicros,
                    height: 8,
                    color: Colors.indigo.shade300),
                Container(
                    width: w * paintMax / scaleMicros,
                    height: 8,
                    color: Colors.teal.shade300),
              ],
            );
          }),
          const SizedBox(height: 4),
          Text('layout  ${stats(timing.layout)}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          Text('paint   ${stats(timing.paint)}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          if (timing.paintHistory.length > 1) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 24,
              child: CustomPaint(
                size: Size.infinite,
                painter: _SparklinePainter(timing.paintHistory),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> values;
  _SparklinePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final max = values.reduce((a, b) => a > b ? a : b);
    if (max == 0) return;
    final barW = size.width / values.length;
    final paint = Paint()..color = Colors.teal.shade200;
    for (var i = 0; i < values.length; i++) {
      final h = size.height * values[i] / max;
      canvas.drawRect(
        Rect.fromLTWH(i * barW, size.height - h, barW * 0.8, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}

class _FragmentSpanRow extends StatelessWidget {
  final FragmentSpan span;
  const _FragmentSpanRow({required this.span});

  @override
  Widget build(BuildContext context) {
    final f = span.fragment;
    final text = (f['text'] as String?) ?? '';
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);
    final highlight = mono.copyWith(backgroundColor: Colors.lightBlue.shade100);
    final from = span.selectedFrom ?? 0;
    final to = span.selectedTo ?? 0;
    final visible = text.length < span.end - span.start
        ? text
        : text.substring(0, span.end - span.start);
    final clampedFrom = from.clamp(0, visible.length);
    final clampedTo = to.clamp(0, visible.length);
    return Container(
      color: span.isSelected ? Colors.lightBlue.shade50 : null,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text('[${span.start}, ${span.end})',
                style: mono.copyWith(color: Colors.grey.shade700)),
          ),
          _TypeBadge(span.isRuby ? 'ruby' : 'text'),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: visible.substring(0, clampedFrom), style: mono),
                  TextSpan(
                      text: visible.substring(clampedFrom, clampedTo),
                      style: highlight),
                  TextSpan(text: visible.substring(clampedTo), style: mono),
                ])),
                if (span.isRuby)
                  Text(
                    'ruby: "${f['rubyText']}"  height: '
                    '${(f['rubyHeight'] as num?)?.toStringAsFixed(1) ?? '—'}'
                    '  at (${(f['offsetX'] as num?)?.toStringAsFixed(1)}, '
                    '${(f['offsetY'] as num?)?.toStringAsFixed(1)})',
                    style:
                        TextStyle(fontSize: 11, color: Colors.purple.shade400),
                  ),
              ],
            ),
          ),
          Text('#${span.index}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _CssVariableRow extends StatelessWidget {
  final Map<String, dynamic> variable;
  final bool overridden;
  final VoidCallback onEdit;
  final VoidCallback onReset;
  final VoidCallback? onTapNode;
  const _CssVariableRow({
    required this.variable,
    required this.overridden,
    required this.onEdit,
    required this.onReset,
    this.onTapNode,
  });

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);
    return InkWell(
      onTap: onTapNode,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(variable['name'] as String? ?? '',
                  style: mono.copyWith(
                      color: Colors.indigo, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      variable['value'] as String? ?? '',
                      style: overridden
                          ? mono.copyWith(
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold)
                          : mono,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (overridden) ...[
                    const SizedBox(width: 4),
                    const _TypeBadge('override'),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 14),
              tooltip: 'Override ${variable['name']}',
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
            ),
            if (overridden)
              IconButton(
                icon: const Icon(Icons.undo, size: 14),
                tooltip: 'Remove override',
                visualDensity: VisualDensity.compact,
                onPressed: onReset,
              ),
            Expanded(
              flex: 3,
              child: Text(
                '<${variable['nodeTag']}> ${variable['nodeId']}',
                style: mono.copyWith(color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owns its [TextEditingController] so it outlives the dialog's closing
/// animation (disposing it right after `showDialog` returns crashes the
/// still-animating TextField).
class _CssVariableEditDialog extends StatefulWidget {
  final String name;
  final String initialValue;
  const _CssVariableEditDialog(
      {required this.name, required this.initialValue});

  @override
  State<_CssVariableEditDialog> createState() => _CssVariableEditDialogState();
}

class _CssVariableEditDialogState extends State<_CssVariableEditDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.name, style: const TextStyle(fontFamily: 'monospace')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: const InputDecoration(
          helperText: 'Applies to every HyperViewer in the app. '
              'Empty = remove override.',
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _SnapshotDialog extends StatelessWidget {
  final String json;
  final String rendererId;
  const _SnapshotDialog({required this.json, required this.rendererId});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('UDT snapshot — $rendererId'),
      content: SizedBox(
        width: 720,
        height: 480,
        child: SingleChildScrollView(
          child: SelectableText(
            json,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      ),
      actions: [
        Text('${(json.length / 1024).toStringAsFixed(1)} KB',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        TextButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await Clipboard.setData(ClipboardData(text: json));
              messenger.showSnackBar(
                  const SnackBar(content: Text('Snapshot copied')));
            } catch (_) {
              // DevTools hosts extensions in an iframe; clipboard access can
              // be denied there. The text above stays selectable.
              messenger.showSnackBar(const SnackBar(
                  content: Text('Clipboard blocked — select the text '
                      'and copy manually')));
            }
          },
          child: const Text('Copy JSON'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Renderer dropdown
// ─────────────────────────────────────────────────────────────────────────────

class _RendererDropdown extends StatelessWidget {
  final List<String> ids;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const _RendererDropdown({
    required this.ids,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: selectedId,
      isDense: true,
      underline: const SizedBox(),
      hint: const Text('Select renderer', style: TextStyle(fontSize: 12)),
      items: ids
          .map((id) => DropdownMenuItem<String>(
                value: id,
                child: Text(id,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UDT node tree widget
// ─────────────────────────────────────────────────────────────────────────────

class _UdtNodeWidget extends StatefulWidget {
  final Map<String, dynamic> node;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _UdtNodeWidget({
    required this.node,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<_UdtNodeWidget> createState() => _UdtNodeWidgetState();
}

class _UdtNodeWidgetState extends State<_UdtNodeWidget> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final nodeId = widget.node['id'] as String? ?? '';
    final tagName = widget.node['tagName'] as String? ?? '';
    final nodeType = widget.node['type'] as String? ?? '';
    final children = widget.node['children'] as List? ?? [];
    final isSelected = widget.selectedId == nodeId;
    final text = widget.node['text'] as String?;
    final truncated = widget.node['childrenTruncated'] as bool? ?? false;

    final hasChildren = children.isNotEmpty;
    final color = _nodeTypeColor(nodeType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => widget.onSelected(nodeId),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.shade100 : null,
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                if (hasChildren)
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: Colors.grey,
                    ),
                  )
                else
                  const SizedBox(width: 16),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  '<$tagName>',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: color,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (text != null) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '"${text.length > 40 ? '${text.substring(0, 40)}…' : text}"',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_expanded && hasChildren)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...children
                    .cast<Map<String, dynamic>>()
                    .map((child) => _UdtNodeWidget(
                          node: child,
                          selectedId: widget.selectedId,
                          onSelected: widget.onSelected,
                        )),
                if (truncated)
                  const Padding(
                    padding: EdgeInsets.only(left: 4, top: 2),
                    child: Text(
                      '… (depth limit reached)',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Color _nodeTypeColor(String type) {
    return switch (type) {
      'document' => Colors.purple,
      'block' => Colors.blue,
      'inline' => Colors.green,
      'text' => Colors.grey,
      'atomic' => Colors.orange,
      'table' || 'tableRow' || 'tableCell' => Colors.teal,
      'ruby' => Colors.pink,
      _ => Colors.grey,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fragment / Line rows
// ─────────────────────────────────────────────────────────────────────────────

class _FragmentRow extends StatelessWidget {
  final Map<String, dynamic> fragment;
  const _FragmentRow({required this.fragment});

  @override
  Widget build(BuildContext context) {
    final type = fragment['type'] as String? ?? '?';
    final text = fragment['text'] as String?;
    final w = (fragment['width'] as num?)?.toStringAsFixed(1) ?? '—';
    final h = (fragment['height'] as num?)?.toStringAsFixed(1) ?? '—';
    final x = (fragment['offsetX'] as num?)?.toStringAsFixed(1) ?? '—';
    final y = (fragment['offsetY'] as num?)?.toStringAsFixed(1) ?? '—';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          _TypeBadge(type),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text != null
                  ? '"${text.length > 30 ? '${text.substring(0, 30)}…' : text}"'
                  : type,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$w×$h @ ($x,$y)',
            style: const TextStyle(
                fontSize: 10, fontFamily: 'monospace', color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  final Map<String, dynamic> line;
  const _LineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final frags = line['fragmentCount'] ?? '?';
    final top = (line['top'] as num?)?.toStringAsFixed(1) ?? '—';
    final h = (line['height'] as num?)?.toStringAsFixed(1) ?? '—';
    final baseline = (line['baseline'] as num?)?.toStringAsFixed(1) ?? '—';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          const _TypeBadge('line'),
          const SizedBox(width: 6),
          Text(
            '$frags fragments',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
          const Spacer(),
          Text(
            'top=$top  h=$h  base=$baseline',
            style: const TextStyle(
                fontSize: 10, fontFamily: 'monospace', color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String label;
  const _TypeBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.blueGrey.shade200),
      ),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 10, fontFamily: 'monospace', color: Colors.blueGrey),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PropertyRow extends StatelessWidget {
  final String name;
  final dynamic value;

  const _PropertyRow({required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    final displayValue = value is Map || value is List
        ? const JsonEncoder.withIndent('  ').convert(value)
        : value.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              name,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.blueGrey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.blue.shade700,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String description;
  const _InfoCard({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(description,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

extension on List<String> {
  String? get firstOrNull => isEmpty ? null : first;
}
