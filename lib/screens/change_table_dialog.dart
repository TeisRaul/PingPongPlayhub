import 'package:flutter/material.dart';

import '../services/table_service.dart';
import '../utils/hour_utils.dart';
import '../theme/app_theme.dart';

/// Alege altă masă pentru o rezervare. Arată mesele sălii pe intervalul
/// rezervării: libere, ocupate (și de cine), antrenament și masa curentă.
class ChangeTableDialog extends StatefulWidget {
  final String matchId;
  final Map<String, dynamic> match;

  const ChangeTableDialog({super.key, required this.matchId, required this.match});

  /// Returnează `true` dacă masa a fost schimbată.
  static Future<bool> show(BuildContext context, String matchId, Map<String, dynamic> match) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => ChangeTableDialog(matchId: matchId, match: match),
    );
    return changed == true;
  }

  @override
  State<ChangeTableDialog> createState() => _ChangeTableDialogState();
}

class _ChangeTableDialogState extends State<ChangeTableDialog> {
  static Color get _cyan => AppColors.accent;

  late Future<List<TableOption>> _future;
  TableOption? _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = TableService.optionsForMatch(widget.matchId, widget.match);
  }

  Color _colorFor(TableState s) {
    switch (s) {
      case TableState.free:
        return AppColors.good;
      case TableState.occupied:
        return Colors.redAccent;
      case TableState.training:
        return Colors.purpleAccent;
      case TableState.current:
        return _cyan;
    }
  }

  String _labelFor(TableOption o) {
    switch (o.state) {
      case TableState.free:
        return 'Liberă';
      case TableState.occupied:
        return 'Ocupată${o.detail != null ? '\n${o.detail}' : ''}';
      case TableState.training:
        return 'Antrenament';
      case TableState.current:
        return 'Masa curentă';
    }
  }

  Future<void> _save() async {
    final target = _selected;
    if (target == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ok = await TableService.changeTable(widget.matchId, widget.match, target);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _saving = false;
          _selected = null;
          _error = '${target.name} s-a ocupat între timp. Alege altă masă.';
          _future = TableService.optionsForMatch(widget.matchId, widget.match);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Eroare: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    return AlertDialog(
      scrollable: true,
      backgroundColor: AppColors.card,
      title: Text('Schimbă masa', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Interval: ${m['date']} · ${formatHour(m['startHour'])} - ${formatHour(m['endHour'])}',
              style: TextStyle(color: AppColors.text70),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<TableOption>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(color: _cyan)),
                  );
                }
                if (snapshot.hasError) {
                  return Text('Eroare: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent));
                }
                final options = snapshot.data ?? [];
                if (options.isEmpty) {
                  return Text('Sala nu are mese configurate pentru această rezervare.',
                      style: TextStyle(color: AppColors.muted));
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options.map((o) {
                    final color = _colorFor(o.state);
                    final selectable = o.state == TableState.free;
                    final selected = _selected?.id == o.id;
                    return GestureDetector(
                      onTap: selectable && !_saving ? () => setState(() => _selected = o) : null,
                      child: Container(
                        width: 104,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: selected ? 0.35 : 0.12),
                          border: Border.all(color: color, width: selected ? 2.5 : 1.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Icon(o.type == 'training' ? Icons.school : Icons.table_restaurant, color: color, size: 22),
                            const SizedBox(height: 4),
                            Text(o.name,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(_labelFor(o),
                                textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 10)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text('Anulează', style: TextStyle(color: AppColors.muted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.black),
          onPressed: _selected == null || _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : Text(_selected == null ? 'Alege o masă liberă' : 'Mută pe ${_selected!.name}'),
        ),
      ],
    );
  }
}
