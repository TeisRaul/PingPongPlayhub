import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';

enum _Period { day, week, month }

/// Raport admin: câte check-in-uri a avut fiecare sală pe zi / săptămână / lună.
/// Check-in = meci cu `checkedIn == true`; ziua se ia din `checkedInAt`.
class AdminCheckinReportScreen extends StatefulWidget {
  const AdminCheckinReportScreen({super.key});

  @override
  State<AdminCheckinReportScreen> createState() => _AdminCheckinReportScreenState();
}

class _VenueStats {
  final String id;
  String name;
  int count = 0;
  double revenue = 0;
  final Map<DateTime, List<Map<String, dynamic>>> byDay = {};
  _VenueStats(this.id, this.name);
}

class _AdminCheckinReportScreenState extends State<AdminCheckinReportScreen> {
  static Color get _cyan => AppColors.accent;
  static Color get _card => AppColors.card;

  _Period _period = _Period.week;
  DateTime _anchor = DateTime.now();
  late Future<List<_VenueStats>> _future;
  final _pctController = TextEditingController(text: '5');

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _pctController.dispose();
    super.dispose();
  }

  (DateTime, DateTime) _range() {
    final a = DateTime(_anchor.year, _anchor.month, _anchor.day);
    switch (_period) {
      case _Period.day:
        return (a, DateTime(a.year, a.month, a.day + 1));
      case _Period.week:
        final start = DateTime(a.year, a.month, a.day - (a.weekday - 1));
        return (start, DateTime(start.year, start.month, start.day + 7));
      case _Period.month:
        return (DateTime(a.year, a.month, 1), DateTime(a.year, a.month + 1, 1));
    }
  }

  String _label() {
    final (s, e) = _range();
    final f = DateFormat('dd.MM.yyyy');
    switch (_period) {
      case _Period.day:
        return f.format(s);
      case _Period.week:
        return '${f.format(s)} – ${f.format(DateTime(e.year, e.month, e.day - 1))}';
      case _Period.month:
        return DateFormat('MMMM yyyy', 'ro').format(s);
    }
  }

  void _shift(int dir) {
    setState(() {
      switch (_period) {
        case _Period.day:
          _anchor = DateTime(_anchor.year, _anchor.month, _anchor.day + dir);
          break;
        case _Period.week:
          _anchor = DateTime(_anchor.year, _anchor.month, _anchor.day + 7 * dir);
          break;
        case _Period.month:
          _anchor = DateTime(_anchor.year, _anchor.month + dir, 1);
          break;
      }
      _future = _load();
    });
  }

  Future<List<_VenueStats>> _load() async {
    final (start, end) = _range();
    final snap = await FirebaseFirestore.instance
        .collection('matches')
        .where('checkedInAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('checkedInAt', isLessThan: Timestamp.fromDate(end))
        .get();

    final Map<String, _VenueStats> venues = {};
    for (final d in snap.docs) {
      final m = d.data();
      if (m['checkedIn'] != true || m['status'] == 'cancelled') continue;
      final ts = m['checkedInAt'];
      if (ts is! Timestamp) continue;
      final id = (m['locationId'] ?? m['locationName'] ?? '?').toString();
      final v = venues.putIfAbsent(id, () => _VenueStats(id, (m['locationName'] ?? id).toString()));
      final t = ts.toDate();
      final day = DateTime(t.year, t.month, t.day);
      v.count++;
      v.revenue += (m['price'] as num?)?.toDouble() ?? 0;
      v.byDay.putIfAbsent(day, () => []).add({...m, 'id': d.id, '_at': t});
    }
    final list = venues.values.toList()..sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  /// Service fee fix (RON) pe fiecare check-in, citit direct din câmp (5 dacă e gol / invalid).
  double get _feePerCheckin {
    final v = double.tryParse(_pctController.text.trim().replaceAll(',', '.'));
    return (v == null || v.isNaN || v < 0) ? 5 : v;
  }

  double _fee(int checkins) => checkins * _feePerCheckin;

  Future<void> _copyCsv(List<_VenueStats> list) async {
    final (s, e) = _range();
    final f = DateFormat('yyyy-MM-dd');
    final b = StringBuffer('Sala,Data,Check-in-uri,Venit (RON)\n');
    for (final v in list) {
      final days = v.byDay.keys.toList()..sort();
      for (final day in days) {
        final items = v.byDay[day]!;
        final name = v.name.replaceAll('"', '""');
        b.writeln('"$name",${f.format(day)},${items.length},${_fee(items.length).toStringAsFixed(2)}');
      }
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('CSV copiat (${f.format(s)} – ${f.format(DateTime(e.year, e.month, e.day - 1))}). Lipește-l în Excel / Google Sheets.'),
      backgroundColor: Colors.green,
    ));
  }

  /// Raport PDF (pe sală, cu defalcare pe zile) — se descarcă pe web / se oferă spre salvare pe mobil.
  Future<void> _exportPdf(List<_VenueStats> list) async {
    try {
      final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/LiberationSans-Regular.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/LiberationSans-Bold.ttf'));
      final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
      final (start, _) = _range();
      final totalCount = list.fold<int>(0, (s, v) => s + v.count);
      final fee = _feePerCheckin;
      final dayFmt = DateFormat('dd.MM.yyyy');
      final timeFmt = DateFormat('HH:mm');
      final periodName = switch (_period) { _Period.day => 'zilnic', _Period.week => 'saptamanal', _Period.month => 'lunar' };
      final fileDate = _period == _Period.month ? DateFormat('yyyy-MM').format(start) : DateFormat('yyyy-MM-dd').format(start);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (ctx) => [
            pw.Text('Raport check-in-uri', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Perioada: ${_label()}'),
            pw.Text('Generat la: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 14),
            pw.Text(
              'Total: $totalCount check-in-uri  •  ${list.length} săli  •  venit ${(totalCount * fee).toStringAsFixed(2)} RON (service fee ${fee.toStringAsFixed(2)} RON / check-in)',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            if (list.isEmpty)
              pw.Text('Niciun check-in în această perioadă.')
            else ...[
              pw.TableHelper.fromTextArray(
                headers: ['Sala', 'Check-in-uri', 'Venit (RON)'],
                data: [
                  for (final v in list) [v.name, '${v.count}', (v.count * fee).toStringAsFixed(2)],
                  ['TOTAL', '$totalCount', (totalCount * fee).toStringAsFixed(2)],
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
                border: pw.TableBorder.all(color: PdfColors.grey400),
              ),
              if (_period != _Period.day) ...[
                pw.SizedBox(height: 18),
                pw.Text('Pe zile', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                for (final v in list) ...[
                  pw.Text(v.name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 3),
                  pw.TableHelper.fromTextArray(
                    headers: ['Data', 'Check-in-uri', 'Venit (RON)'],
                    data: [
                      for (final day in (v.byDay.keys.toList()..sort()))
                        [dayFmt.format(day), '${v.byDay[day]!.length}', (v.byDay[day]!.length * fee).toStringAsFixed(2)],
                    ],
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                    cellStyle: const pw.TextStyle(fontSize: 10),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                  ),
                  pw.SizedBox(height: 12),
                ],
              ] else ...[
                pw.SizedBox(height: 18),
                pw.Text('Check-in-uri din zi', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.TableHelper.fromTextArray(
                  headers: ['Ora', 'Sala', 'Jucător', 'Masa'],
                  data: [
                    for (final v in list)
                      for (final m in (v.byDay.values.expand((x) => x).toList()
                        ..sort((a, b) => (a['_at'] as DateTime).compareTo(b['_at'] as DateTime))))
                        [timeFmt.format(m['_at'] as DateTime), v.name, '${m['hostUsername'] ?? '-'}', '${m['tableId'] ?? '-'}'],
                  ],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  cellStyle: const pw.TextStyle(fontSize: 10),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                ),
              ],
            ],
          ],
        ),
      );

      await Printing.sharePdf(bytes: await doc.save(), filename: 'raport-checkin-$periodName-$fileDate.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare la generarea PDF: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Raport check-in-uri', style: TextStyle(color: AppColors.text, fontSize: 18)),
        backgroundColor: _card,
        iconTheme: IconThemeData(color: _cyan),
      ),
      body: FutureBuilder<List<_VenueStats>>(
        future: _future,
        builder: (context, snap) {
          final list = snap.data ?? const <_VenueStats>[];
          final totalCount = list.fold<int>(0, (s, v) => s + v.count);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<_Period>(
                segments: const [
                  ButtonSegment(value: _Period.day, label: Text('Zi')),
                  ButtonSegment(value: _Period.week, label: Text('Săptămână')),
                  ButtonSegment(value: _Period.month, label: Text('Lună')),
                ],
                selected: {_period},
                onSelectionChanged: (v) => setState(() {
                  _period = v.first;
                  _future = _load();
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(icon: Icon(Icons.chevron_left, color: _cyan), onPressed: () => _shift(-1)),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _anchor,
                          firstDate: DateTime(2023),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) {
                          setState(() {
                            _anchor = d;
                            _future = _load();
                          });
                        }
                      },
                      child: Center(
                        child: Text(_label(), style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  IconButton(icon: Icon(Icons.chevron_right, color: _cyan), onPressed: () => _shift(1)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text('Service fee / check-in:', style: TextStyle(color: AppColors.muted)),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _pctController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: AppColors.text),
                      decoration: const InputDecoration(isDense: true, suffixText: 'RON'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _exportPdf(list),
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: const Text('PDF'),
                  ),
                  TextButton.icon(
                    onPressed: list.isEmpty ? null : () => _copyCsv(list),
                    icon: const Icon(Icons.copy_all, size: 18),
                    label: const Text('Copiază CSV'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (snap.connectionState == ConnectionState.waiting)
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(color: _cyan)),
                )
              else if (snap.hasError)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Eroare: ${snap.error}', style: const TextStyle(color: Colors.redAccent)),
                )
              else ...[
                Card(
                  color: _card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _cyan.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _stat('Check-in-uri', '$totalCount'),
                        _stat('Săli active', '${list.length}'),
                        _stat('Venit (service fee)', '${_fee(totalCount).toStringAsFixed(0)} RON'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Niciun check-in în această perioadă.', style: TextStyle(color: AppColors.muted))),
                  )
                else
                  ...list.map(_venueTile),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(value, style: TextStyle(color: _cyan, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: 11)),
        ],
      );

  Widget _venueTile(_VenueStats v) {
    final days = v.byDay.keys.toList()..sort();
    final df = DateFormat('EEE dd.MM', 'ro');
    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: _cyan,
          collapsedIconColor: AppColors.muted,
          title: Text(v.name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
          subtitle: Text(
            '${v.count} check-in-uri  •  ${_fee(v.count).toStringAsFixed(0)} RON',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          children: [
            for (final day in days) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(df.format(day), style: TextStyle(color: _cyan, fontWeight: FontWeight.bold)),
                    Text('${v.byDay[day]!.length}', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (_period == _Period.day)
                for (final m in (v.byDay[day]!..sort((a, b) => (a['_at'] as DateTime).compareTo(b['_at'] as DateTime))))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 16, 2),
                    child: Text(
                      '${DateFormat('HH:mm').format(m['_at'] as DateTime)}  •  ${m['hostUsername'] ?? '-'}  •  masa ${m['tableId'] ?? '-'}',
                      style: TextStyle(color: AppColors.text70, fontSize: 12),
                    ),
                  ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
