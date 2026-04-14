import 'package:flutter/material.dart';

import 'chord_models.dart';
import 'chord_result_bottom_sheet.dart';
import 'chord_symbol.dart';
import 'chord_transpose_local.dart';
import 'offline_chord_builder.dart';

/// 和弦字典：完全离线查构成音与常见把位。
class ChordLookupScreen extends StatefulWidget {
  const ChordLookupScreen({super.key});

  @override
  State<ChordLookupScreen> createState() => _ChordLookupScreenState();
}

class _ChordLookupScreenState extends State<ChordLookupScreen> {
  String _selRoot = 'C';
  String _selQual = '';
  String _selBass = '';
  String _selectedKey = 'C';

  String _displaySymbol = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _refreshDisplaySymbol();
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

  /// 在帧结束后弹出底部结果层，避免在 build 过程中直接 `showModalBottomSheet`。
  void _scheduleShowResultSheet(
    ChordExplainMultiPayload payload,
    String? disclaimer,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showChordResultBottomSheet(
        context: context,
        payload: payload,
        disclaimer: disclaimer,
      );
    });
  }

  void _fetchOffline() {
    final sym = _displaySymbol.trim();
    if (sym.isEmpty) {
      setState(() {
        _errorText = '请先选择和弦';
      });
      return;
    }
    final payload = buildOfflineChordPayload(displaySymbol: sym);
    setState(() {
      _errorText = payload == null ? '无法从符号解析和弦（请检查根音与性质）' : null;
    });
    if (payload != null) {
      final d = payload.disclaimer.trim();
      _scheduleShowResultSheet(payload, d.isNotEmpty ? d : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('和弦字典'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '无需网络：点「查询和弦指法」即可查看构成音与常见把位。',
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
                    'C 调记谱：${_builtSymbol.isEmpty ? '—' : _builtSymbol} · 查看调：$_selectedKey',
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
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('chord_lookup_offline'),
            onPressed: _fetchOffline,
            child: const Text('查询和弦指法'),
          ),
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
