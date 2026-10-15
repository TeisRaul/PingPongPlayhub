import 'package:cloud_firestore/cloud_firestore.dart';
import '../l10n/strings.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/checkin_service.dart';
import '../utils/hour_utils.dart';
import 'change_table_dialog.dart';
import 'check_in_flow.dart';
import '../theme/app_theme.dart';

enum MatchDetailMode { player, venue, admin }

/// Pagina unui meci, deschisă direct din dashboard.
/// - jucător: biletul (QR + cod scurt) și starea check-in-ului;
/// - sală / admin: check-in, schimbare de masă, plată cash, No-Show.
class MatchDetailScreen extends StatelessWidget {
  final String matchId;
  final MatchDetailMode mode;

  const MatchDetailScreen({super.key, required this.matchId, required this.mode});

  static Color get _cyan => AppColors.accent;
  static Color get _card => AppColors.card;

  bool get _isStaff => mode != MatchDetailMode.player;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: _card,
        iconTheme: IconThemeData(color: _cyan),
        title: Text('Detalii meci', style: TextStyle(color: AppColors.text, fontSize: 18)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('matches').doc(matchId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Eroare: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
            );
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: _cyan));
          }
          final doc = snapshot.data!;
          if (!doc.exists) {
            return Center(
              child: Text('Acest meci nu mai există.', style: TextStyle(color: AppColors.muted)),
            );
          }
          return _buildBody(context, doc.data() ?? <String, dynamic>{});
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> data) {
    final status = (data['status'] ?? 'open').toString();
    final cancelled = status == 'cancelled';
    final finished = status == 'completed';
    final checkedIn = data['checkedIn'] == true;
    final waiting = data['waiting'] == true;
    final players = (data['joinedPlayers'] as List?) ?? [];
    final payment = (data['paymentMethod'] ?? 'Cash la locație').toString();
    final isPaid = payment.contains('Card') || data['paymentStatus'] == 'confirmed';
    final price = (data['price'] as num?)?.toDouble() ?? 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _checkInBadge(data, cancelled: cancelled, checkedIn: checkedIn, waiting: waiting),
        const SizedBox(height: 16),
        _section([
          Text(
            (data['locationName'] ?? 'Sală').toString(),
            style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _row(Icons.calendar_month, '${data['date'] ?? ''}  |  ${formatHour(data['startHour'])} - ${formatHour(data['endHour'])}'),
          _row(Icons.table_restaurant, 'Masa ${data['tableId'] ?? '-'}', color: _cyan, bold: true),
          _row(Icons.sports_tennis, (data['sport'] ?? '-').toString()),
          _row(Icons.person_outline, 'Gazdă: ${data['hostUsername'] ?? '-'}'),
        ]),
        const SizedBox(height: 12),
        _section([
          Text('Jucători', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (players.isEmpty) Text('-', style: TextStyle(color: AppColors.muted)),
          for (final p in players)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• ${p is Map ? (p['username'] ?? 'Jucător') : p}${p is Map && p['level'] != null ? '  (${p['level']})' : ''}',
                style: TextStyle(color: AppColors.text70),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        _section([
          _row(Icons.payments_outlined, '$payment · ${price.toStringAsFixed(0)} RON'),
          _row(
            isPaid ? Icons.check_circle : Icons.hourglass_empty,
            isPaid ? 'Plată confirmată' : 'De încasat la locație',
            color: isPaid ? Colors.green : Colors.orangeAccent,
          ),
        ]),
        const SizedBox(height: 16),
        if (!cancelled && !finished)
          ...(_isStaff ? _staffActions(context, data, checkedIn, isPaid) : _playerTicket(data, checkedIn)),
      ],
    );
  }

  Widget _checkInBadge(Map<String, dynamic> data,
      {required bool cancelled, required bool checkedIn, required bool waiting}) {
    String text;
    Color color;
    IconData icon;
    if (cancelled) {
      text = tr('mm.cancelled');
      color = Colors.redAccent;
      icon = Icons.cancel;
    } else if (checkedIn) {
      final ts = data['checkedInAt'];
      final at = ts is Timestamp ? ' la ${DateFormat('HH:mm').format(ts.toDate())}' : '';
      final late = (data['lateMinutes'] as num?)?.toInt() ?? 0;
      text = 'Check-in efectuat$at${late > 0 ? ' (întârziere $late min)' : ''}';
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (waiting) {
      text = 'La așteptarea mesei';
      color = Colors.orange;
      icon = Icons.hourglass_top;
    } else {
      text = 'Check-in nefăcut';
      color = AppColors.muted;
      icon = Icons.radio_button_unchecked;
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  List<Widget> _playerTicket(Map<String, dynamic> data, bool checkedIn) {
    if (checkedIn) return const [];
    return [
      _section([
        Text('Bilet check-in',
            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('Arată acest cod la recepția sălii.',
            style: TextStyle(color: AppColors.muted, fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 14),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(12)),
            child: SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(data: matchId, version: QrVersions.auto, size: 200.0),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('Cod bilet',
            style: TextStyle(color: AppColors.muted, fontSize: 12), textAlign: TextAlign.center),
        Center(
          child: SelectableText(
            CheckInService.formatShortCode(CheckInService.shortCode(matchId)),
            style: TextStyle(color: AppColors.text, fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 4),
          ),
        ),
        Text('Nu merge scanarea? Spune acest cod sălii.',
            style: TextStyle(color: AppColors.muted, fontSize: 12), textAlign: TextAlign.center),
      ]),
    ];
  }

  List<Widget> _staffActions(BuildContext context, Map<String, dynamic> data, bool checkedIn, bool isPaid) {
    final venueId = FirebaseAuth.instance.currentUser?.uid;
    final admin = mode == MatchDetailMode.admin;
    return [
      if (!checkedIn)
        ElevatedButton.icon(
          onPressed: () => CheckInFlow.processCode(context, matchId, venueId: venueId, isAdmin: admin),
          icon: const Icon(Icons.how_to_reg),
          label: const Text('Check-in', style: TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _cyan,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      if (data['tableId'] != null) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => ChangeTableDialog.show(context, matchId, data),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Schimbă masa'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _cyan,
            side: BorderSide(color: _cyan),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
      if (!isPaid) ...[
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () => _confirmCash(context),
          icon: const Icon(Icons.payments),
          label: const Text('Confirmă plata cash'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.good,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
      if (!checkedIn) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _confirmNoShow(context, data),
          icon: const Icon(Icons.person_off),
          label: const Text('No-Show'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
            side: const BorderSide(color: Colors.orange),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    ];
  }

  Future<void> _confirmCash(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('matches').doc(matchId).update({'paymentStatus': 'confirmed'});
      messenger.showSnackBar(const SnackBar(content: Text('Plată cash confirmată.'), backgroundColor: Colors.green));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _confirmNoShow(BuildContext context, Map<String, dynamic> data) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Marchezi No-Show?', style: TextStyle(color: AppColors.text)),
        content: Text(
          'Rezervarea se anulează, masa se eliberează, iar gazda pierde 5 puncte de încredere.',
          style: TextStyle(color: AppColors.text70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Renunță', style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black),
            child: const Text('Marchează No-Show'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CheckInService.markNoShow(matchId, (data['hostUid'] ?? '').toString());
      messenger.showSnackBar(const SnackBar(content: Text('Marcat No-Show. Masa e liberă.'), backgroundColor: Colors.orange));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _section(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _row(IconData icon, String text, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color ?? AppColors.text70, fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 18 : 14),
            ),
          ),
        ],
      ),
    );
  }
}
