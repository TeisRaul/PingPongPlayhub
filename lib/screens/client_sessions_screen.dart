import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/strings.dart';
import '../services/trainer_service.dart';
import '../widgets/player_drawer.dart';
import '../widgets/review_dialog.dart';
import '../theme/app_theme.dart';

class ClientSessionsScreen extends StatefulWidget {
  const ClientSessionsScreen({super.key});

  @override
  State<ClientSessionsScreen> createState() => _ClientSessionsScreenState();
}

class _ClientSessionsScreenState extends State<ClientSessionsScreen> {
  final user = FirebaseAuth.instance.currentUser;

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _requestReschedule(Map<String, dynamic> b) async {
    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (selectedDate == null || !mounted) return;

    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
    );
    if (selectedTime == null) return;

    try {
      await TrainerService.requestReschedule(b, selectedDate, selectedTime.hour);
      _snack(tr('tr.reschedule_snack'), Colors.green);
    } catch (e) {
      _snack(tr('tr.error', {'error': '$e'}), Colors.red);
    }
  }

  Future<void> _cancel(Map<String, dynamic> b) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(tr('tr.cancel_confirm_title'), style: TextStyle(color: AppColors.text)),
        content: Text(tr('tr.cancel_confirm_body'), style: TextStyle(color: AppColors.text70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.back'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('tr.cancel_session')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await TrainerService.cancelByClient(b);
      _snack(tr('tr.cancelled_snack'), Colors.orange);
    } catch (e) {
      _snack(tr('tr.error', {'error': '$e'}), Colors.red);
    }
  }

  bool _isPast(Map<String, dynamic> b) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final today = '${now.year}-${two(now.month)}-${two(now.day)}';
    final date = (b['date'] ?? '').toString();
    return date.isNotEmpty && date.compareTo(today) < 0;
  }

  bool _canReview(Map<String, dynamic> b) =>
      (b['status'] ?? '') == TrainerStatus.confirmed && _isPast(b) && b['reviewed'] != true;

  Future<void> _review(Map<String, dynamic> b) async {
    final ok = await showReviewDialog(
      context,
      title: tr('rev.trainer_title', {'name': (b['trainerName'] ?? '').toString()}),
      onSubmit: (rating, comment) => TrainerService.reviewTrainer(b, rating, comment),
    );
    if (ok) _snack(tr('rev.thanks'), Colors.green);
  }

  (String, Color) _statusChip(String status) {
    switch (status) {
      case TrainerStatus.pending:
        return (tr('tr.st_pending'), Colors.amber);
      case TrainerStatus.confirmed:
        return (tr('tr.st_confirmed'), Colors.greenAccent);
      case TrainerStatus.declined:
        return (tr('tr.st_declined'), Colors.redAccent);
      case TrainerStatus.cancelled:
        return (tr('tr.st_cancelled'), AppColors.muted);
      case TrainerStatus.rescheduleRequested:
        return (tr('tr.st_reschedule'), Colors.orangeAccent);
      default:
        return (status, AppColors.muted);
    }
  }

  Widget _card(Map<String, dynamic> b) {
    final String venueName = (b['locationName'] ?? '').toString().isEmpty ? tr('tr.unknown_venue') : b['locationName'];
    final String trainerName = (b['trainerName'] ?? '').toString();
    final String date = (b['date'] ?? '-').toString();
    final String time = (b['time'] ?? '-').toString();
    final String status = (b['status'] ?? TrainerStatus.pending).toString();
    final (String label, Color color) = _statusChip(status);

    return Card(
      color: AppColors.card2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sports, color: AppColors.accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(venueName, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                      if (trainerName.isNotEmpty)
                        Text(tr('tr.with_trainer', {'name': trainerName}), style: TextStyle(color: AppColors.accent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('$date | $time', style: TextStyle(color: AppColors.muted)),
                      if (TrainerService.detailsLine(b) != null)
                        Text(TrainerService.detailsLine(b)!, style: TextStyle(color: AppColors.accent, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color),
              ),
              child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            if (status == TrainerStatus.rescheduleRequested) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pending_actions, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('tr.reschedule_sent', {'date': '${b['requestedDate']}', 'time': '${b['requestedTime']}'}),
                        style: const TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_canReview(b)) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.star_rate_rounded, size: 18),
                  label: Text(tr('rev.rate_trainer')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: BorderSide(color: AppColors.gold),
                  ),
                  onPressed: () => _review(b),
                ),
              ),
            ],
            if (status == TrainerStatus.confirmed && !_isPast(b)) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_calendar, size: 18),
                  label: Text(tr('tr.request_change')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: BorderSide(color: AppColors.accent),
                  ),
                  onPressed: () => _requestReschedule(b),
                ),
              ),
            ],
            if (status == TrainerStatus.pending || (status == TrainerStatus.confirmed && !_isPast(b))) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: Text(status == TrainerStatus.pending ? tr('tr.cancel_request') : tr('tr.cancel_session')),
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  onPressed: () => _cancel(b),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(body: Center(child: Text(tr('tr.not_logged'))));
    }

    return Scaffold(
      drawer: const PlayerDrawer(activePage: 'client_sessions'),
      appBar: AppBar(
        title: Text(tr('tr.sessions_title'), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('tr.sessions_heading'),
              style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                // Fără filtru „trainerId != null” și fără orderBy: nu cere index compus; filtrăm local.
                stream: FirebaseFirestore.instance
                    .collection('reservations')
                    .where('creatorId', isEqualTo: user!.uid)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text(tr('tr.error', {'error': '${snap.error}'}), style: const TextStyle(color: Colors.redAccent)));
                  }
                  if (!snap.hasData) {
                    return Center(child: CircularProgressIndicator(color: AppColors.accent));
                  }
                  final list = snap.data!.docs
                      .map((d) => {...d.data(), 'id': d.id})
                      .where((m) => (m['trainerId'] ?? '').toString().isNotEmpty)
                      .toList();
                  list.sort((a, b) {
                    final Timestamp? t1 = a['timestamp'] as Timestamp?;
                    final Timestamp? t2 = b['timestamp'] as Timestamp?;
                    if (t1 == null || t2 == null) return 0;
                    return t2.compareTo(t1);
                  });
                  if (list.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          tr('tr.sessions_empty'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted, fontSize: 16),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) => _card(list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
