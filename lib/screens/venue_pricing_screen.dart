import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/hour_utils.dart';
import '../utils/price_rules.dart';

/// Ecranul sălii pentru prețuri pe interval și reduceri (happy hour, weekend, preț fix pe oră etc.).
class VenuePricingScreen extends StatefulWidget {
  final String venueId;
  const VenuePricingScreen({super.key, required this.venueId});

  @override
  State<VenuePricingScreen> createState() => _VenuePricingScreenState();
}

class _VenuePricingScreenState extends State<VenuePricingScreen> {
  static const _dayNames = ['Lu', 'Ma', 'Mi', 'Jo', 'Vi', 'Sâ', 'Du'];

  bool _loading = true;
  List<VenuePriceRule> _rules = [];
  Map<String, dynamic> _venue = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).get();
      _venue = doc.data() ?? {};
      _rules = VenuePriceRule.parseList(_venue['priceRules']);
    } catch (e) {
      debugPrint('Eroare la încărcarea prețurilor: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    try {
      await FirebaseFirestore.instance
          .collection('venues')
          .doc(widget.venueId)
          .update({'priceRules': _rules.map((r) => r.toMap()).toList()});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la salvare: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  String get _baseInfo {
    final type = _venue['priceType'] ?? 'flat';
    if (type == 'dynamic') {
      final lim = (_venue['dynamicHourLimit'] as num?)?.toInt() ?? 17;
      final b = ((_venue['dynamicPriceHalfBefore'] as num?)?.toDouble() ?? 15) * 2;
      final a = ((_venue['dynamicPriceHalfAfter'] as num?)?.toDouble() ?? 20) * 2;
      return 'Tarif de bază: ${b.toStringAsFixed(0)} RON/oră înainte de $lim:00, ${a.toStringAsFixed(0)} RON/oră după';
    }
    final f = ((_venue['flatPriceHalf'] as num?)?.toDouble() ?? 15) * 2;
    return 'Tarif de bază: ${f.toStringAsFixed(0)} RON/oră';
  }

  String _describe(VenuePriceRule r) {
    final days = r.days.isEmpty || r.days.length == 7 ? 'Zilnic' : r.days.map((d) => _dayNames[d - 1]).join(', ');
    final hours = '${formatHour(r.startHour)} - ${formatHour(r.endHour)}';
    final what = r.isFixed ? '${r.value.toStringAsFixed(0)} RON/oră' : '-${r.value.toStringAsFixed(0)}%';
    final period = (r.validFrom != null || r.validTo != null) ? '\n${r.validFrom ?? '...'} → ${r.validTo ?? '...'}' : '';
    return '$days · $hours · $what$period';
  }

  Future<void> _addRule() async {
    final rule = await showDialog<VenuePriceRule>(context: context, builder: (_) => const _RuleDialog());
    if (rule == null) return;
    setState(() => _rules.insert(0, rule));
    await _save();
  }

  Future<void> _delete(VenuePriceRule r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Ștergi regula?', style: TextStyle(color: AppColors.text)),
        content: Text(r.name, style: TextStyle(color: AppColors.text70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Înapoi', style: TextStyle(color: AppColors.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Șterge', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _rules.removeWhere((x) => x.id == r.id));
    await _save();
  }

  Future<void> _toggle(VenuePriceRule r, bool v) async {
    final i = _rules.indexWhere((x) => x.id == r.id);
    if (i < 0) return;
    setState(() => _rules[i] = r.copyWith(active: v));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text('Prețuri și reduceri', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        onPressed: _addRule,
        icon: const Icon(Icons.add),
        label: const Text('Regulă nouă'),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_baseInfo, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        'Regulile de mai jos înlocuiesc sau reduc tariful de bază pe zilele și orele alese. '
                        'Dacă mai multe reguli se potrivesc, se aplică prima din listă. '
                        'Jucătorii văd prețul final la rezervare.',
                        style: TextStyle(color: AppColors.text54, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Nu ai nicio regulă. Adaugă una, de exemplu „Happy hour” luni-vineri 10:00-16:00, -20%.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                  ),
                for (final r in _rules)
                  Card(
                    color: AppColors.card,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: r.active ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border),
                    ),
                    child: ListTile(
                      leading: Icon(r.isFixed ? Icons.sell_outlined : Icons.percent, color: r.active ? AppColors.accent : AppColors.muted),
                      title: Text(r.name.isEmpty ? 'Regulă' : r.name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                      subtitle: Text(_describe(r), style: TextStyle(color: AppColors.text54, fontSize: 12.5)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(value: r.active, onChanged: (v) => _toggle(r, v)),
                          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _delete(r)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog();

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  static const _dayNames = ['Lu', 'Ma', 'Mi', 'Jo', 'Vi', 'Sâ', 'Du'];
  final _name = TextEditingController();
  final _value = TextEditingController();
  String _mode = 'percent';
  final Set<int> _days = {1, 2, 3, 4, 5};
  double _start = 10;
  double _end = 16;
  DateTime? _from;
  DateTime? _to;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  Widget _hourDropdown(double value, ValueChanged<double> onChanged) {
    return DropdownButton<double>(
      value: value,
      dropdownColor: AppColors.card,
      style: TextStyle(color: AppColors.text),
      items: [
        for (double h = 0; h <= 24; h += 0.5) DropdownMenuItem(value: h, child: Text(formatHour(h))),
      ],
      onChanged: (v) => onChanged(v ?? value),
    );
  }

  void _submit() {
    final v = double.tryParse(_value.text.trim().replaceAll(',', '.'));
    if (v == null || v < 0) {
      setState(() => _error = 'Introdu o valoare validă.');
      return;
    }
    if (_mode == 'percent' && v > 100) {
      setState(() => _error = 'Reducerea nu poate depăși 100%.');
      return;
    }
    if (_start >= _end) {
      setState(() => _error = 'Ora de final trebuie să fie după ora de început.');
      return;
    }
    if (_from != null && _to != null && _to!.isBefore(_from!)) {
      setState(() => _error = 'Perioada este inversată.');
      return;
    }
    final days = _days.toList()..sort();
    Navigator.pop(
      context,
      VenuePriceRule(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim().isEmpty ? (_mode == 'percent' ? 'Reducere' : 'Tarif special') : _name.text.trim(),
        mode: _mode,
        days: days.length == 7 ? <int>[] : days,
        startHour: _start,
        endHour: _end,
        value: v,
        validFrom: _from == null ? null : _ymd(_from!),
        validTo: _to == null ? null : _ymd(_to!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Regulă de preț', style: TextStyle(color: AppColors.text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              style: TextStyle(color: AppColors.text),
              decoration: const InputDecoration(labelText: 'Nume (ex. Happy hour)'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'percent', label: Text('Reducere %')),
                ButtonSegment(value: 'fixed', label: Text('Tarif fix')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(labelText: _mode == 'percent' ? 'Reducere (%)' : 'Preț (RON / oră)'),
            ),
            const SizedBox(height: 12),
            Text('Zile', style: TextStyle(color: AppColors.text70, fontSize: 12)),
            Wrap(
              spacing: 6,
              children: [
                for (int i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(_dayNames[i]),
                    selected: _days.contains(i + 1),
                    onSelected: (v) => setState(() => v ? _days.add(i + 1) : _days.remove(i + 1)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('De la ', style: TextStyle(color: AppColors.text70)),
                _hourDropdown(_start, (v) => setState(() => _start = v)),
                Text('  până la ', style: TextStyle(color: AppColors.text70)),
                _hourDropdown(_end, (v) => setState(() => _end = v)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Perioadă (opțional)', style: TextStyle(color: AppColors.text70, fontSize: 12)),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => _pickDate(true),
                    child: Text(_from == null ? 'De la data' : _ymd(_from!), style: TextStyle(color: AppColors.accent)),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => _pickDate(false),
                    child: Text(_to == null ? 'Până la data' : _ymd(_to!), style: TextStyle(color: AppColors.accent)),
                  ),
                ),
              ],
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Renunță', style: TextStyle(color: AppColors.muted))),
        TextButton(onPressed: _submit, child: Text('Adaugă', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold))),
      ],
    );
  }
}
