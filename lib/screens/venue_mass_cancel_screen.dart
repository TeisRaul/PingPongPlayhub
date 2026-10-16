import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/sports.dart';
import '../services/venue_tools.dart';
import '../theme/app_theme.dart';
import '../utils/hour_utils.dart';

/// Anulare în masă pentru mentenanță / eveniment privat: sala alege zilele, orele și mesele,
/// vede rezervările afectate, le anulează (cu rambursare pentru cele plătite cu cardul),
/// jucătorii sunt notificați, iar intervalul poate fi blocat pentru rezervări noi.
class VenueMassCancelScreen extends StatefulWidget {
  final String venueId;
  final String venueName;
  const VenueMassCancelScreen({super.key, required this.venueId, required this.venueName});

  @override
  State<VenueMassCancelScreen> createState() => _VenueMassCancelScreenState();
}

class _VenueMassCancelScreenState extends State<VenueMassCancelScreen> {
  final _fmt = DateFormat('yyyy-MM-dd');
  final _reason = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic> _venue = {};
  List<String> _sports = ['ping_pong'];

  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  double _start = 8;
  double _end = 24;
  String? _sport; // null = toate
  bool _allTables = true;
  final Set<int> _tables = {};
  bool _block = true;

  List<Map<String, dynamic>>? _preview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).get();
      _venue = doc.data() ?? {};
      _sports = VenueTools.sports(_venue);
    } catch (e) {
      debugPrint('Eroare la încărcarea sălii: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = d;
        if (_to.isBefore(_from)) _from = _to;
      }
      _preview = null;
    });
  }

  List<Map<String, dynamic>> get _tableChoices =>
      _sport == null ? [] : VenueTools.tablesFor(_venue, _sport!);

  List<int> get _selectedTables => (_allTables || _sport == null) ? <int>[] : (_tables.toList()..sort());

  String? _validate() {
    if (_start >= _end) return 'Ora de final trebuie să fie după ora de început.';
    if (_to.difference(_from).inDays > 60) return 'Poți anula maxim 60 de zile odată.';
    if (_sport != null && !_allTables && _tables.isEmpty) return 'Alege cel puțin o masă.';
    return null;
  }

  Future<void> _showPreview() async {
    final err = _validate();
    if (err != null) {
      _snack(err, Colors.redAccent);
      return;
    }
    setState(() => _busy = true);
    try {
      final list = await VenueTools.affectedMatches(
        venueId: widget.venueId,
        from: _from,
        to: _to,
        startHour: _start,
        endHour: _end,
        sport: _sport,
        tableIds: _selectedTables,
      );
      if (mounted) setState(() => _preview = list);
    } catch (e) {
      _snack('Eroare la căutarea rezervărilor: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndRun() async {
    final list = _preview ?? [];
    final err = _validate();
    if (err != null) {
      _snack(err, Colors.redAccent);
      return;
    }
    final refunds = list.where((m) => (m['paymentMethod'] ?? '').toString().contains('Card') && m['paymentStatus'] == 'confirmed').length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(list.isEmpty ? 'Blochezi intervalul?' : 'Anulezi ${list.length} rezervări?', style: TextStyle(color: AppColors.text)),
        content: Text(
          [
            if (list.isNotEmpty) 'Jucătorii înscriși vor fi notificați${refunds > 0 ? ', iar $refunds plăți cu cardul vor fi rambursate automat pe cardul jucătorilor' : ''}.',
            if (_block) 'Intervalul va fi blocat pentru rezervări noi.',
            'Acțiunea nu poate fi anulată.',
          ].join('\n\n'),
          style: TextStyle(color: AppColors.text70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Înapoi', style: TextStyle(color: AppColors.muted))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(list.isEmpty ? 'Blochează' : 'Anulează tot', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final reason = _reason.text.trim();
      final res = await VenueTools.cancelMatches(matches: list, venueName: widget.venueName, reason: reason, massCancel: true);
      if (_block) {
        final slots = <BlockedSlot>[];
        var day = DateTime(_from.year, _from.month, _from.day);
        final last = DateTime(_to.year, _to.month, _to.day);
        int i = 0;
        while (!day.isAfter(last)) {
          slots.add(BlockedSlot(
            id: '${DateTime.now().microsecondsSinceEpoch}_${i++}',
            date: _fmt.format(day),
            startHour: _start,
            endHour: _end,
            tableIds: _selectedTables,
            sport: _sport,
            reason: reason,
          ));
          day = day.add(const Duration(days: 1));
        }
        await VenueTools.addBlockedSlots(widget.venueId, slots);
      }
      await _load();
      if (!mounted) return;
      setState(() => _preview = null);
      _snack(
        res.cancelled == 0
            ? 'Interval blocat.'
            : '${res.cancelled} rezervări anulate, ${res.notified} notificări trimise${res.refunded > 0 ? ', ${res.refunded} plăți cu cardul rambursate' : ''}.',
        Colors.green,
      );
    } catch (e) {
      _snack('Eroare: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
  }

  Widget _hourDropdown(double value, ValueChanged<double> onChanged) {
    return DropdownButton<double>(
      value: value,
      dropdownColor: AppColors.card,
      style: TextStyle(color: AppColors.text),
      items: [for (double h = 0; h <= 24; h += 0.5) DropdownMenuItem(value: h, child: Text(formatHour(h)))],
      onChanged: (v) => setState(() {
        onChanged(v ?? value);
        _preview = null;
      }),
    );
  }

  Widget _section(String title, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );

  Widget _blockedList() {
    final today = _fmt.format(DateTime.now());
    final slots = VenueTools.parseBlocked(_venue['blockedSlots']).where((b) => b.date.compareTo(today) >= 0).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (slots.isEmpty) return const SizedBox.shrink();
    return _section(
      'Intervale blocate',
      Column(
        children: [
          for (final b in slots)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                '${b.date} · ${formatHour(b.startHour)} - ${formatHour(b.endHour)}',
                style: TextStyle(color: AppColors.text),
              ),
              subtitle: Text(
                '${b.sport == null ? 'Toate sporturile' : sportLabel(b.sport!)} · ${b.allTables ? 'toate mesele' : 'mese: ${b.tableIds.join(', ')}'}${b.reason.isEmpty ? '' : '\n${b.reason}'}',
                style: TextStyle(color: AppColors.text54, fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.lock_open, color: Colors.orangeAccent),
                tooltip: 'Deblochează',
                onPressed: () async {
                  await VenueTools.removeBlockedSlot(widget.venueId, b);
                  await _load();
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = DateFormat('dd.MM.yyyy');
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text('Anulare în masă', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(
                  'Perioada',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.event, size: 18),
                              label: Text('De la ${d.format(_from)}'),
                              onPressed: () => _pickDate(true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.event, size: 18),
                              label: Text('Până la ${d.format(_to)}'),
                              onPressed: () => _pickDate(false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('Între orele ', style: TextStyle(color: AppColors.text70)),
                          _hourDropdown(_start, (v) => _start = v),
                          Text(' și ', style: TextStyle(color: AppColors.text70)),
                          _hourDropdown(_end, (v) => _end = v),
                        ],
                      ),
                    ],
                  ),
                ),
                _section(
                  'Ce se anulează',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Toate sporturile'),
                            selected: _sport == null,
                            onSelected: (_) => setState(() {
                              _sport = null;
                              _tables.clear();
                              _allTables = true;
                              _preview = null;
                            }),
                          ),
                          for (final s in _sports)
                            ChoiceChip(
                              label: Text(sportLabel(s)),
                              selected: _sport == s,
                              onSelected: (_) => setState(() {
                                _sport = s;
                                _tables.clear();
                                _allTables = true;
                                _preview = null;
                              }),
                            ),
                        ],
                      ),
                      if (_sport != null) ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Toate mesele / terenurile', style: TextStyle(color: AppColors.text)),
                          value: _allTables,
                          onChanged: (v) => setState(() {
                            _allTables = v;
                            _preview = null;
                          }),
                        ),
                        if (!_allTables)
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final t in _tableChoices)
                                FilterChip(
                                  label: Text(VenueTools.tableName(t)),
                                  selected: _tables.contains((t['tableId'] as num).toInt()),
                                  onSelected: (v) => setState(() {
                                    final id = (t['tableId'] as num).toInt();
                                    v ? _tables.add(id) : _tables.remove(id);
                                    _preview = null;
                                  }),
                                ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
                _section(
                  'Motiv (apare în notificare)',
                  TextField(
                    controller: _reason,
                    style: TextStyle(color: AppColors.text),
                    maxLength: 140,
                    decoration: const InputDecoration(hintText: 'ex. Mentenanță parchet'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Blochează intervalul pentru rezervări noi', style: TextStyle(color: AppColors.text)),
                  value: _block,
                  onChanged: (v) => setState(() => _block = v),
                ),
                const SizedBox(height: 4),
                ElevatedButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('Vezi rezervările afectate'),
                  onPressed: _busy ? null : _showPreview,
                ),
                if (_preview != null) ...[
                  const SizedBox(height: 14),
                  _section(
                    _preview!.isEmpty ? 'Nu sunt rezervări în acest interval' : '${_preview!.length} rezervări vor fi anulate',
                    Column(
                      children: [
                        for (final m in _preview!)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(Icons.event_busy, color: Colors.redAccent.withValues(alpha: 0.8)),
                            title: Text(
                              '${m['date']} · ${formatHour(m['startHour'])} - ${formatHour(m['endHour'])}',
                              style: TextStyle(color: AppColors.text),
                            ),
                            subtitle: Text(
                              '${m['hostUsername'] ?? '-'} · masa ${m['tableId'] ?? '-'} · ${sportLabel((m['sport'] ?? 'ping_pong').toString())}'
                              '${(m['paymentMethod'] ?? '').toString().contains('Card') && m['paymentStatus'] == 'confirmed' ? ' · plătit cu cardul (se returnează banii)' : ''}',
                              style: TextStyle(color: AppColors.text54, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cancel_schedule_send),
                    label: Text(_preview!.isEmpty ? 'Blochează intervalul' : 'Anulează ${_preview!.length} rezervări'),
                    onPressed: _busy ? null : _confirmAndRun,
                  ),
                ],
                const SizedBox(height: 20),
                _blockedList(),
              ],
            ),
    );
  }
}
