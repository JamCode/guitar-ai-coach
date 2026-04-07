import 'dart:async';

import 'package:flutter/material.dart';

import '../settings/api_base_url_store.dart';
import '../settings/api_settings_screen.dart';
import 'chord_api_repository.dart';
import 'chord_models.dart';
import 'chord_remote_repository.dart';
import 'chord_symbol.dart';
import 'chord_transpose_local.dart';
import 'offline_chord_builder.dart';

/// 和弦字典：**默认完全离线**查构成音与常见把位；可选联网拉取多套 AI 按法。
class ChordLookupScreen extends StatefulWidget {
  const ChordLookupScreen({super.key, this.repository});

  /// 测试注入；为 `null` 时使用默认 [ChordApiRepository]（仅联网按钮使用）。
  final ChordRemoteRepository? repository;

  @override
  State<ChordLookupScreen> createState() => _ChordLookupScreenState();
}

class _ChordLookupScreenState extends State<ChordLookupScreen> {
  late final ChordRemoteRepository _repo;
  var _ownsApiRepo = false;

  String _selRoot = 'C';
  String _selQual = '';
  String _selBass = '';
  String _selectedKey = 'C';
  String _selectedLevel = '中级';

  String _displaySymbol = '';
  var _hasApiBase = false;

  bool _loadingOnline = false;
  bool _recalibrating = false;
  String? _errorText;
  ChordExplainMultiPayload? _result;
  String? _disclaimer;
  var _lastResultFromOnline = false;

  @override
  void initState() {
    super.initState();
    if (widget.repository != null) {
      _repo = widget.repository!;
    } else {
      _repo = ChordApiRepository();
      _ownsApiRepo = true;
    }
    _refreshDisplaySymbol();
    unawaited(_refreshApiFlag());
  }

  Future<void> _refreshApiFlag() async {
    final u = await ApiBaseUrlStore().load();
    if (!mounted) return;
    setState(() => _hasApiBase = u.isNotEmpty);
  }

  @override
  void dispose() {
    final r = _repo;
    if (_ownsApiRepo && r is ChordApiRepository) {
      r.close();
    }
    super.dispose();
  }

  String get _builtSymbol => buildChordSymbol(
        root: _selRoot,
        qualId: _selQual,
        bassId: _selBass,
      );

  void _refreshDisplaySymbol() {
    final sym = _builtSymbol.trim();
    if (sym.isEmpty) {
      setState(() => _displaySymbol = '');
      return;
    }
    if (ChordSelectCatalog.referenceKey == _selectedKey) {
      setState(() => _displaySymbol = sym);
      return;
    }
    final t = ChordTransposeLocal.transposeChordSymbol(
      sym,
      ChordSelectCatalog.referenceKey,
      _selectedKey,
    );
    setState(() => _displaySymbol = t);
  }

  void _fetchOffline() {
    final sym = _displaySymbol.trim();
    if (sym.isEmpty) {
      setState(() {
        _errorText = '请先选择和弦';
        _result = null;
        _disclaimer = null;
        _lastResultFromOnline = false;
      });
      return;
    }
    final payload = buildOfflineChordPayload(displaySymbol: sym);
    setState(() {
      _errorText = payload == null ? '无法从符号解析和弦（请检查根音与性质）' : null;
      _result = payload;
      _disclaimer = payload?.disclaimer;
      _lastResultFromOnline = false;
      _loadingOnline = false;
      _recalibrating = false;
    });
  }

  Future<void> _fetchOnline({required bool force}) async {
    final sym = _displaySymbol.trim();
    if (sym.isEmpty) {
      setState(() {
        _errorText = '请先选择和弦';
        _result = null;
        _disclaimer = null;
      });
      return;
    }
    setState(() {
      _errorText = null;
      if (force) {
        _recalibrating = true;
      } else {
        _loadingOnline = true;
      }
    });
    try {
      final data = await _repo.explainMulti(
        symbol: sym,
        key: _selectedKey,
        level: _selectedLevel,
        forceRefresh: force,
      );
      if (!mounted) return;
      setState(() {
        _result = data;
        _disclaimer = data.disclaimer.isNotEmpty ? data.disclaimer : null;
        _loadingOnline = false;
        _recalibrating = false;
        _lastResultFromOnline = true;
      });
    } on ChordApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.message;
        _loadingOnline = false;
        _recalibrating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = '$e';
        _loadingOnline = false;
        _recalibrating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('和弦字典'),
        actions: [
          IconButton(
            tooltip: 'API 设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const ApiSettingsScreen(),
                ),
              );
              await _refreshApiFlag();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '无需网络：先点「离线查和弦」看构成音与常见把位。'
            ' 若已配置 API，可用联网查询获取更多按法。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前和弦', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    _displaySymbol.isEmpty ? '—' : _displaySymbol,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'C 调记谱：${_builtSymbol.isEmpty ? '—' : _builtSymbol} · 查看调：$_selectedKey · 难度（仅联网）：$_selectedLevel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _LabeledDropdown<String>(
            label: '根音',
            value: _selRoot,
            items: ChordSelectCatalog.keys,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selRoot = v);
              _refreshDisplaySymbol();
            },
          ),
          _LabeledDropdown<String>(
            label: '和弦性质',
            value: _selQual,
            itemLabels: {
              for (final o in ChordSelectCatalog.qualOptions) o.id: o.label,
            },
            items: ChordSelectCatalog.qualOptions.map((e) => e.id).toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selQual = v);
              _refreshDisplaySymbol();
            },
          ),
          _LabeledDropdown<String>(
            label: '低音 / 转位',
            value: _selBass,
            itemLabels: {
              for (final o in ChordSelectCatalog.bassOptions) o.id: o.label,
            },
            items: ChordSelectCatalog.bassOptions.map((e) => e.id).toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selBass = v);
              _refreshDisplaySymbol();
            },
          ),
          _LabeledDropdown<String>(
            label: '目标调（变调预览）',
            value: _selectedKey,
            items: ChordSelectCatalog.keys,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedKey = v);
              _refreshDisplaySymbol();
            },
          ),
          _LabeledDropdown<String>(
            label: '难度（仅联网查询）',
            value: _selectedLevel,
            items: ChordSelectCatalog.levels,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedLevel = v);
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('chord_lookup_offline'),
            onPressed: _loadingOnline || _recalibrating ? null : _fetchOffline,
            child: const Text('离线查和弦'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('chord_lookup_online'),
            onPressed: (!_hasApiBase || _loadingOnline || _recalibrating)
                ? null
                : () => unawaited(_fetchOnline(force: false)),
            child: Text(_loadingOnline ? '联网加载中…' : '联网查询更多按法'),
          ),
          if (_lastResultFromOnline && _result != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('chord_lookup_recalibrate'),
              onPressed: _loadingOnline || _recalibrating
                  ? null
                  : () => unawaited(_fetchOnline(force: true)),
              child: Text(_recalibrating ? '重新生成中…' : '联网重新生成按法'),
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _errorText!,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ),
          ],
          if (_result != null) _ResultSection(payload: _result!, disclaimer: _disclaimer),
        ],
      ),
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.itemLabels,
  });

  final String label;
  final T value;
  final List<T> items;
  final void Function(T?) onChanged;
  final Map<T, String>? itemLabels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          InputDecorator(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                isDense: true,
                items: [
                  for (final i in items)
                    DropdownMenuItem(
                      value: i,
                      child: Text(itemLabels?[i] ?? '$i'),
                    ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({
    required this.payload,
    required this.disclaimer,
  });

  final ChordExplainMultiPayload payload;
  final String? disclaimer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = payload.chordSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('和弦说明', style: theme.textTheme.titleMedium),
        if (s.notesLetters.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('构成音：${s.notesLetters.join(' · ')}'),
        ],
        if (s.notesExplainZh.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(s.notesExplainZh),
        ],
        const SizedBox(height: 16),
        Text('按法参考', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (var i = 0; i < payload.voicings.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    payload.voicings[i].labelZh,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '起算品格：${payload.voicings[i].explain.baseFret}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '6→1 弦：${formatFretsLine(payload.voicings[i].explain.frets)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (payload.voicings[i].explain.barre != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '横按：${payload.voicings[i].explain.barre!.fret} 品 '
                      '（弦 ${payload.voicings[i].explain.barre!.fromString}–${payload.voicings[i].explain.barre!.toString_}）',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (payload.voicings[i].explain.voicingExplainZh.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(payload.voicings[i].explain.voicingExplainZh),
                  ],
                ],
              ),
            ),
          ),
        if (disclaimer != null && disclaimer!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            disclaimer!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
