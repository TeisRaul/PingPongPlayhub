import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';
import '../utils/hour_utils.dart';

enum _Period { days7, days30, thisMonth, lastMonth, thisYear, all }

/// Raport de venituri pentru sală: totaluri pe perioadă, grupare pe zi sau lună, export CSV.
class VenueFinancesScreen extends StatefulWidget {
  final String venueId;

  const VenueFinancesScreen({super.key, required this.venueId});

  @override
  State<VenueFinancesScreen> createState() => _VenueFinancesScreenState();
}

class _Booking {
  final String date; // yyyy-MM-dd
  final double startHour;
  final double endHour;
  final int table;
  final String sport;
  final String host;
  final String method;
  final String paymentStatus;
  final String status;
  final double price;
  final double refunded;
  final double discount;
  final String voucher;

  const _Booking({
    required this.date,
    required this.startHour,
    required this.endHour,
    required this.table,
    required this.sport,
    required this.host,
    required this.method,
    required this.paymentStatus,
    required this.status,
    required this.price,
    required this.refunded,
    required this.discount,
    required this.voucher,
  });

  bool get cancelled => status == 'cancelled';
  bool get isCard => method.contains('Card');
  bool get isCash => method.contains('Cash');

  /// Încasat efectiv: rezervare activă și plată confirmată.
  double get cardIncome => (!cancelled && isCard && paymentStatus == 'confirmed') ? price : 0;
  double get cashIncome => (!cancelled && isCash && paymentStatus == 'confirmed') ? price : 0;
  double get refundAmount => (cancelled && paymentStatus == 'refunded') ? refunded : 0;
  double get discountGiven => cancelled ? 0 : discount;
}

class _Bucket {
  final String label;
  int bookings = 0;
  int cancelled = 0;
  double cash = 0;
  double card = 0;
  double refunded = 0;
  double discounts = 0;

  _Bucket(this.label);

  double get total => cash + card;
}

class _VenueFinancesScreenState extends State<VenueFinancesScreen> {
  bool _isLoading = true;
  List<_Booking> _all = [];
  _Period _period = _Period.thisMonth;
  bool _byMonth = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('matches')
          .where('locationId', isEqualTo: widget.venueId)
          .get();
      _all = snap.docs.map((d) {
        final m = d.data();
        return _Booking(
          date: (m['date'] ?? '').toString(),
          startHour: hourValue(m['startHour']),
          endHour: hourValue(m['endHour']),
          table: (m['tableId'] as num?)?.toInt() ?? 0,
          sport: (m['sport'] ?? 'ping_pong').toString(),
          host: (m['hostUsername'] ?? '').toString(),
          method: (m['paymentMethod'] ?? '').toString(),
          paymentStatus: (m['paymentStatus'] ?? '').toString(),
          status: (m['status'] ?? 'open').toString(),
          price: (m['price'] as num?)?.toDouble() ?? 0,
          refunded: (m['refundedAmount'] as num?)?.toDouble() ?? 0,
          discount: (m['voucherDiscount'] as num?)?.toDouble() ?? 0,
          voucher: (m['voucherCode'] ?? '').toString(),
        );
      }).where((b) => b.date.isNotEmpty).toList();
    } catch (e) {
      debugPrint('Eroare la incarcarea finantelor: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// Limitele perioadei ca șiruri yyyy-MM-dd (inclusiv), sau null pentru „tot".
  (String, String)? get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case _Period.days7:
        return (_ymd(today.subtract(const Duration(days: 6))), _ymd(today));
      case _Period.days30:
        return (_ymd(today.subtract(const Duration(days: 29))), _ymd(today));
      case _Period.thisMonth:
        return (_ymd(DateTime(now.year, now.month, 1)), _ymd(DateTime(now.year, now.month + 1, 0)));
      case _Period.lastMonth:
        return (_ymd(DateTime(now.year, now.month - 1, 1)), _ymd(DateTime(now.year, now.month, 0)));
      case _Period.thisYear:
        return (_ymd(DateTime(now.year, 1, 1)), _ymd(DateTime(now.year, 12, 31)));
      case _Period.all:
        return null;
    }
  }

  List<_Booking> get _inRange {
    final r = _range;
    if (r == null) return _all;
    return _all.where((b) => b.date.compareTo(r.$1) >= 0 && b.date.compareTo(r.$2) <= 0).toList();
  }

  String _bucketLabel(String date) {
    if (_byMonth) return date.length >= 7 ? date.substring(0, 7) : date;
    final p = date.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : date;
  }

  /// Grupare pe zi sau lună, în ordine cronologică.
  List<_Bucket> _buckets(List<_Booking> list) {
    final sorted = [...list]..sort((a, b) => a.date.compareTo(b.date));
    final map = <String, _Bucket>{};
    for (final b in sorted) {
      final key = _byMonth ? (b.date.length >= 7 ? b.date.substring(0, 7) : b.date) : b.date;
      final bucket = map.putIfAbsent(key, () => _Bucket(_bucketLabel(b.date)));
      bucket.bookings += b.cancelled ? 0 : 1;
      bucket.cancelled += b.cancelled ? 1 : 0;
      bucket.cash += b.cashIncome;
      bucket.card += b.cardIncome;
      bucket.refunded += b.refundAmount;
      bucket.discounts += b.discountGiven;
    }
    return map.values.toList();
  }

  // ---------- CSV ----------

  static String _num(double v) => v.toStringAsFixed(2).replaceAll('.', ','); // zecimale cu virgulă (Excel RO)

  static String _cell(Object? v) {
    final s = (v ?? '').toString();
    if (s.contains(';') || s.contains('"') || s.contains('\n')) return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  String _summaryCsv(List<_Bucket> buckets) {
    final b = StringBuffer('﻿');
    b.writeln(['Perioadă', 'Rezervări', 'Anulate', 'Cash (RON)', 'Card (RON)', 'Total încasat (RON)', 'Returnat (RON)', 'Reduceri acordate (RON)'].join(';'));
    for (final k in buckets) {
      b.writeln([k.label, k.bookings, k.cancelled, _num(k.cash), _num(k.card), _num(k.total), _num(k.refunded), _num(k.discounts)].map(_cell).join(';'));
    }
    return b.toString();
  }

  String _detailCsv(List<_Booking> list) {
    final sorted = [...list]..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : a.startHour.compareTo(b.startHour);
      });
    final b = StringBuffer('﻿');
    b.writeln(['Data', 'Ora început', 'Ora sfârșit', 'Masă', 'Sport', 'Jucător', 'Metodă plată', 'Stare plată', 'Stare rezervare', 'Preț (RON)', 'Returnat (RON)', 'Reducere (RON)', 'Cod voucher'].join(';'));
    for (final r in sorted) {
      b.writeln([
        r.date,
        formatHour(r.startHour),
        formatHour(r.endHour),
        r.table,
        r.sport,
        r.host,
        r.method,
        r.paymentStatus,
        r.status,
        _num(r.price),
        _num(r.refundAmount),
        _num(r.discountGiven),
        r.voucher,
      ].map(_cell).join(';'));
    }
    return b.toString();
  }

  Future<void> _export(bool detailed) async {
    final list = _inRange;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nu există rezervări în perioada aleasă.')));
      return;
    }
    final csv = detailed ? _detailCsv(list) : _summaryCsv(_buckets(list));
    final name = '${detailed ? 'rezervari' : (_byMonth ? 'venituri_lunar' : 'venituri_zilnic')}_${_ymd(DateTime.now())}.csv';
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = Uint8List.fromList(utf8.encode(csv));
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'text/csv', name: name)],
        fileNameOverrides: [name],
        subject: name,
      );
    } catch (_) {
      // Dacă partajarea nu e disponibilă (ex. browser), copiem conținutul.
      await Clipboard.setData(ClipboardData(text: csv));
      messenger.showSnackBar(const SnackBar(content: Text('CSV copiat în clipboard. Lipește-l într-un fișier .csv sau în Excel.')));
    }
  }

  // ---------- UI ----------

  static const Map<_Period, String> _periodLabels = {
    _Period.days7: 'Ultimele 7 zile',
    _Period.days30: 'Ultimele 30 de zile',
    _Period.thisMonth: 'Luna aceasta',
    _Period.lastMonth: 'Luna trecută',
    _Period.thisYear: 'Anul acesta',
    _Period.all: 'Tot',
  };

  String _ron(double v) => '${v.toStringAsFixed(2)} RON';

  @override
  Widget build(BuildContext context) {
    final list = _inRange;
    final buckets = _buckets(list);
    double cash = 0, card = 0, refunded = 0, discounts = 0;
    int active = 0, cancelled = 0;
    for (final b in list) {
      cash += b.cashIncome;
      card += b.cardIncome;
      refunded += b.refundAmount;
      discounts += b.discountGiven;
      if (b.cancelled) {
        cancelled++;
      } else {
        active++;
      }
    }
    final total = cash + card;
    final maxBucket = buckets.fold<double>(0, (m, k) => k.total > m ? k.total : m);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Panou Financiar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.card,
        elevation: 0,
        actions: [
          IconButton(icon: Icon(Icons.refresh, color: AppColors.accent), onPressed: _load),
          PopupMenuButton<bool>(
            icon: Icon(Icons.file_download_outlined, color: AppColors.accent),
            tooltip: 'Export CSV',
            color: AppColors.card,
            onSelected: _export,
            itemBuilder: (_) => [
              PopupMenuItem(value: false, child: Text('Export sumar (${_byMonth ? 'pe lună' : 'pe zi'})', style: TextStyle(color: AppColors.text))),
              PopupMenuItem(value: true, child: Text('Export rezervări (detaliat)', style: TextStyle(color: AppColors.text))),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.accent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final p in _Period.values)
                        ChoiceChip(
                          label: Text(_periodLabels[p]!),
                          selected: _period == p,
                          onSelected: (_) => setState(() => _period = p),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Pe zile')),
                      ButtonSegment(value: true, label: Text('Pe luni')),
                    ],
                    selected: {_byMonth},
                    onSelectionChanged: (s) => setState(() => _byMonth = s.first),
                  ),
                  const SizedBox(height: 16),
                  _buildFinanceCard(title: 'Total încasat', amount: total, icon: Icons.account_balance_wallet_outlined, color: AppColors.accent, big: true),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _smallCard('Cash', _ron(cash), Icons.money, AppColors.good)),
                      const SizedBox(width: 12),
                      Expanded(child: _smallCard('Card', _ron(card), Icons.credit_card, AppColors.accent)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _smallCard('Returnat', _ron(refunded), Icons.assignment_return, AppColors.bad)),
                      const SizedBox(width: 12),
                      Expanded(child: _smallCard('Reduceri acordate', _ron(discounts), Icons.confirmation_number_outlined, AppColors.gold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card2.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.text12),
                    ),
                    child: Column(
                      children: [
                        _statRow('Rezervări active', '$active'),
                        _statRow('Rezervări anulate', '$cancelled'),
                        _statRow('Încasare medie / rezervare', active == 0 ? '-' : _ron(total / active)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _byMonth ? 'Pe luni' : 'Pe zile',
                    style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (buckets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Nu există rezervări în perioada aleasă.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                    ),
                  for (final k in buckets.reversed)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(k.label, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold))),
                              Text(_ron(k.total), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxBucket == 0 ? 0 : k.total / maxBucket,
                              minHeight: 6,
                              backgroundColor: AppColors.text10,
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${k.bookings} rezervări'
                            '${k.cancelled > 0 ? ' · ${k.cancelled} anulate' : ''}'
                            ' · cash ${k.cash.toStringAsFixed(0)} · card ${k.card.toStringAsFixed(0)}'
                            '${k.refunded > 0 ? ' · returnat ${k.refunded.toStringAsFixed(0)}' : ''}'
                            '${k.discounts > 0 ? ' · reduceri ${k.discounts.toStringAsFixed(0)}' : ''}',
                            style: TextStyle(color: AppColors.text54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Se numără doar plățile confirmate. Plățile cash apar după ce marchezi plata la sală. Exportul CSV folosește „;” ca separator și virgulă la zecimale, ca să se deschidă corect în Excel în limba română.',
                    style: TextStyle(color: AppColors.text38, fontSize: 11.5),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: AppColors.text70, fontSize: 14)),
            Text(value, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _smallCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 6), Flexible(child: Text(title, style: TextStyle(color: AppColors.text70, fontSize: 12.5)))]),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildFinanceCard({required String title, required double amount, required IconData icon, required Color color, bool big = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 10, spreadRadius: 2)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: AppColors.text70, fontSize: 14)),
                const SizedBox(height: 4),
                Text('${amount.toStringAsFixed(2)} RON', style: TextStyle(color: color, fontSize: big ? 28 : 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
