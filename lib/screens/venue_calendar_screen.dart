import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/sports.dart';
import '../services/venue_tools.dart';
import '../theme/app_theme.dart';
import '../utils/hour_utils.dart';

/// Calendarul zilei pentru sală: mese pe rânduri, ore pe coloane.
/// Rezervările se pot muta cu drag & drop (apăsare lungă) pe altă masă sau altă oră;
/// jucătorii sunt anunțați automat, iar mutările care se suprapun sau cad într-un interval blocat sunt refuzate.
class VenueCalendarScreen extends StatefulWidget {
  final String venueId;
  final String venueName;
  const VenueCalendarScreen({super.key, required this.venueId, required this.venueName});

  @override
  State<VenueCalendarScreen> createState() => _VenueCalendarScreenState();
}

class _VenueCalendarScreenState extends State<VenueCalendarScreen> {
  static const double _cellW = 76;
  static const double _cellH = 64;
  static const double _labelW = 96;

  final _fmt = DateFormat('yyyy-MM-dd');

  bool _loading = true;
  Map<String, dynamic> _venue = {};
  List<String> _sports = ['ping_pong'];
  String _sport = 'ping_pong';
  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _matches = [];
  int _firstHour = 8;
  int _lastHour = 23; // ultima oră de început afișată

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).get();
      _venue = doc.data() ?? {};
      _sports = VenueTools.sports(_venue);
      _sport = _sports.first;
    } catch (e) {
      debugPrint('Eroare la încărcarea sălii: $e');
    }
    await _loadDay();
  }

  Future<void> _loadDay() async {
    if (mounted) setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('matches')
          .where('locationId', isEqualTo: widget.venueId)
          .where('date', isEqualTo: _fmt.format(_date))
          .get();
      _matches = snap.docs.map((d) {
        final m = d.data();
        m['docId'] = d.id;
        return m;
      }).where((m) => m['status'] != 'cancelled').toList();
      // Extinde intervalul orar dacă există rezervări în afara lui.
      int lo = 8, hi = 23;
      for (final m in _matches) {
        lo = lo < hourValue(m['startHour']).floor() ? lo : hourValue(m['startHour']).floor();
        final e = hourValue(m['endHour']).ceil() - 1;
        hi = hi > e ? hi : e;
      }
      _firstHour = lo.clamp(0, 23).toInt();
      _lastHour = hi.clamp(_firstHour, 23).toInt();
    } catch (e) {
      debugPrint('Eroare la încărcarea zilei: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reloadVenue() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).get();
      _venue = doc.data() ?? _venue;
    } catch (_) {}
  }

  void _shiftDay(int d) {
    setState(() => _date = _date.add(Duration(days: d)));
    _loadDay();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (d != null) {
      setState(() => _date = d);
      _loadDay();
    }
  }

  List<Map<String, dynamic>> get _sportMatches =>
      _matches.where((m) => (m['sport'] ?? 'ping_pong') == _sport).toList();

  Color _matchColor(Map<String, dynamic> m) {
    final paid = m['paymentStatus'] == 'confirmed' || m['paymentStatus'] == 'paid' || m['paymentSplit'] == 'Achitat integral';
    if (m['status'] == 'open' && !paid) return Colors.orange;
    return paid ? Colors.green : AppColors.accent;
  }

  Future<void> _onDrop(Map<String, dynamic> match, int tableId, int hour) async {
    final dur = hourValue(match['endHour']) - hourValue(match['startHour']);
    final newStart = hour.toDouble();
    final newEnd = newStart + dur;
    if (newEnd > 24) {
      _snack('Rezervarea nu încape până la miezul nopții.', Colors.redAccent);
      return;
    }
    final sameSpot = ((match['tableId'] as num?)?.toInt() ?? 0) == tableId && hourValue(match['startHour']) == newStart;
    if (sameSpot) return;

    final tables = VenueTools.tablesFor(_venue, _sport);
    final tName = VenueTools.tableName(tables.firstWhere((t) => (t['tableId'] as num).toInt() == tableId, orElse: () => {'tableId': tableId}));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Muți rezervarea?', style: TextStyle(color: AppColors.text)),
        content: Text(
          '${match['hostUsername'] ?? 'Rezervare'}\n'
          '${formatHour(match['startHour'])} - ${formatHour(match['endHour'])}, masa ${match['tableId']}\n'
          '→ ${formatHour(newStart)} - ${formatHour(newEnd)}, $tName\n\n'
          'Jucătorii vor fi notificați.',
          style: TextStyle(color: AppColors.text70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Renunță', style: TextStyle(color: AppColors.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Mută', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      await _reloadVenue();
      final res = await VenueTools.moveMatch(
        match: match,
        newTableId: tableId,
        newStart: newStart,
        newEnd: newEnd,
        venueName: widget.venueName,
        venueData: _venue,
        dayMatches: _matches,
      );
      if (res == 'conflict') {
        _snack('Locul este deja ocupat de altă rezervare.', Colors.redAccent);
      } else if (res == 'blocked') {
        _snack('Intervalul este blocat (mentenanță sau eveniment).', Colors.redAccent);
      } else {
        _snack('Rezervarea a fost mutată, jucătorii au fost anunțați.', Colors.green);
      }
    } catch (e) {
      _snack('Eroare la mutare: $e', Colors.redAccent);
    }
    await _loadDay();
  }

  /// Poate cădea rezervarea [m] pe masa [tableId] la ora [hour]? Folosit pentru evidențierea țintei.
  bool _canDrop(Map<String, dynamic> m, int tableId, int hour) {
    final dur = hourValue(m['endHour']) - hourValue(m['startHour']);
    final s = hour.toDouble();
    final e = s + dur;
    if (e > 24) return false;
    for (final o in _sportMatches) {
      if (o['docId'] == m['docId']) continue;
      if (((o['tableId'] as num?)?.toInt() ?? 0) != tableId) continue;
      if (s < hourValue(o['endHour']) && hourValue(o['startHour']) < e) return false;
    }
    final b = VenueTools.blockFor(_venue, _fmt.format(_date), s, e, sport: _sport);
    return !(b.allTables || b.tables.contains(tableId));
  }

  void _showDetails(Map<String, dynamic> m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m['hostUsername']?.toString() ?? 'Rezervare', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${m['date']} · ${formatHour(m['startHour'])} - ${formatHour(m['endHour'])} · masa ${m['tableId'] ?? '-'}', style: TextStyle(color: AppColors.text70)),
            Text('Plată: ${m['paymentMethod'] ?? '-'} (${m['paymentStatus'] ?? '-'})', style: TextStyle(color: AppColors.text70)),
            Text('Preț: ${((m['price'] as num?) ?? 0).toStringAsFixed(0)} RON', style: TextStyle(color: AppColors.text70)),
            Text('Jucători: ${List<dynamic>.from(m['joinedUids'] ?? const []).length}', style: TextStyle(color: AppColors.text70)),
            const SizedBox(height: 14),
            Text('Ține apăsat pe rezervare și trage-o pe alt loc ca să o muți.', style: TextStyle(color: AppColors.text54, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                icon: const Icon(Icons.event_busy),
                label: const Text('Anulează rezervarea'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _cancelOne(m);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelOne(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Anulezi rezervarea?', style: TextStyle(color: AppColors.text)),
        content: Text('Jucătorii vor fi notificați.', style: TextStyle(color: AppColors.text70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Înapoi', style: TextStyle(color: AppColors.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Anulează', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await VenueTools.cancelMatches(matches: [m], venueName: widget.venueName, reason: '');
      _snack('Rezervarea a fost anulată.', Colors.orange);
    } catch (e) {
      _snack('Eroare la anulare: $e', Colors.redAccent);
    }
    await _loadDay();
  }

  void _snack(String msg, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
  }

  Widget _bookingBlock(Map<String, dynamic> m, {bool feedback = false}) {
    final s = hourValue(m['startHour']);
    final e = hourValue(m['endHour']);
    final w = (e - s) * _cellW - 4;
    final color = _matchColor(m);
    return Container(
      width: w < 20 ? 20 : w,
      height: _cellH - 8,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: feedback ? 0.9 : 0.75),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.5),
        boxShadow: feedback ? const [BoxShadow(color: Colors.black38, blurRadius: 8)] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            (m['hostUsername'] ?? 'Rezervare').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(
            '${formatHour(s)}-${formatHour(e)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _tableRow(Map<String, dynamic> t) {
    final tableId = (t['tableId'] as num).toInt();
    final hours = _lastHour - _firstHour + 1;
    final rowMatches = _sportMatches.where((m) => ((m['tableId'] as num?)?.toInt() ?? 0) == tableId).toList();
    final blocks = VenueTools.parseBlocked(_venue['blockedSlots']).where((b) {
      if (b.date != _fmt.format(_date)) return false;
      if (b.sport != null && b.sport != _sport) return false;
      if (!(b.startHour < _lastHour + 1 && b.endHour > _firstHour)) return false;
      return b.allTables || b.tableIds.contains(tableId);
    }).toList();

    return SizedBox(
      height: _cellH,
      width: hours * _cellW,
      child: Stack(
        children: [
          Row(
            children: [
              for (int h = _firstHour; h <= _lastHour; h++)
                DragTarget<Map<String, dynamic>>(
                  onWillAcceptWithDetails: (d) => _canDrop(d.data, tableId, h),
                  onAcceptWithDetails: (d) => _onDrop(d.data, tableId, h),
                  builder: (ctx, candidate, rejected) {
                    Color? bg;
                    if (candidate.isNotEmpty) bg = Colors.green.withValues(alpha: 0.25);
                    if (rejected.isNotEmpty) bg = Colors.red.withValues(alpha: 0.25);
                    return Container(
                      width: _cellW,
                      height: _cellH,
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border(
                          right: BorderSide(color: AppColors.border),
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          for (final b in blocks)
            Positioned(
              left: (b.startHour.clamp(_firstHour.toDouble(), _lastHour + 1.0).toDouble() - _firstHour) * _cellW + 2,
              top: 4,
              child: IgnorePointer(
                child: Container(
                  width: (b.endHour.clamp(_firstHour.toDouble(), _lastHour + 1.0).toDouble() -
                          b.startHour.clamp(_firstHour.toDouble(), _lastHour + 1.0).toDouble()) *
                          _cellW -
                      4,
                  height: _cellH - 8,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: Text(
                    b.reason.isEmpty ? 'Blocat' : b.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.text70, fontSize: 11),
                  ),
                ),
              ),
            ),
          for (final m in rowMatches)
            Positioned(
              left: (hourValue(m['startHour']) - _firstHour) * _cellW + 2,
              top: 4,
              child: LongPressDraggable<Map<String, dynamic>>(
                data: m,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: Material(color: Colors.transparent, child: _bookingBlock(m, feedback: true)),
                childWhenDragging: Opacity(opacity: 0.25, child: _bookingBlock(m)),
                child: GestureDetector(onTap: () => _showDetails(m), child: _bookingBlock(m)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tables = VenueTools.tablesFor(_venue, _sport);
    final hours = _lastHour - _firstHour + 1;
    final dayLabel = DateFormat('EEE, dd.MM.yyyy').format(_date);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text('Calendar', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Reîncarcă', onPressed: () async {
            await _reloadVenue();
            await _loadDay();
          }),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.card,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(icon: Icon(Icons.chevron_left, color: AppColors.accent), onPressed: () => _shiftDay(-1)),
                    TextButton.icon(
                      onPressed: _pickDate,
                      icon: Icon(Icons.calendar_today, size: 18, color: AppColors.accent),
                      label: Text(dayLabel, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(icon: Icon(Icons.chevron_right, color: AppColors.accent), onPressed: () => _shiftDay(1)),
                  ],
                ),
                if (_sports.length > 1)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final s in _sports)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(sportLabel(s)),
                              selected: _sport == s,
                              onSelected: (_) => setState(() => _sport = s),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: AppColors.accent))
                : tables.isEmpty
                    ? Center(child: Text('Nu există mese configurate pentru acest sport.', style: TextStyle(color: AppColors.muted)))
                    : SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Coloana cu numele meselor
                              Column(
                                children: [
                                  SizedBox(width: _labelW, height: 32),
                                  for (final t in tables)
                                    Container(
                                      width: _labelW,
                                      height: _cellH,
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.card,
                                        border: Border(bottom: BorderSide(color: AppColors.border), right: BorderSide(color: AppColors.border)),
                                      ),
                                      child: Text(VenueTools.tableName(t), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 32,
                                    width: hours * _cellW,
                                    child: Row(
                                      children: [
                                        for (int h = _firstHour; h <= _lastHour; h++)
                                          SizedBox(
                                            width: _cellW,
                                            child: Center(child: Text('${h.toString().padLeft(2, '0')}:00', style: TextStyle(color: AppColors.text54, fontSize: 12))),
                                          ),
                                      ],
                                    ),
                                  ),
                                  for (final t in tables) _tableRow(t),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
          ),
          Container(
            color: AppColors.card,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              'Ține apăsat pe o rezervare și trage-o pe alt loc. Atinge-o pentru detalii.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
