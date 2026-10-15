import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/strings.dart';
import '../services/trainer_service.dart';
import '../widgets/player_drawer.dart';
import 'trainer_schedule_screen.dart';
import '../theme/app_theme.dart';

class TrainerDashboard extends StatefulWidget {
  const TrainerDashboard({super.key});

  @override
  State<TrainerDashboard> createState() => _TrainerDashboardState();
}

class _TrainerDashboardState extends State<TrainerDashboard> {
  final user = FirebaseAuth.instance.currentUser;

  // Ordinea în listă: cereri noi, mutări cerute, confirmate, restul.
  int _rank(String status) {
    switch (status) {
      case TrainerStatus.pending:
        return 0;
      case TrainerStatus.rescheduleRequested:
        return 1;
      case TrainerStatus.confirmed:
        return 2;
      default:
        return 3;
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  String _errorText(Object e) =>
      e.toString().contains('overlap') ? tr('tr.err_overlap') : tr('tr.error', {'error': '$e'});

  Future<void> _respond(Map<String, dynamic> b, bool accept) async {
    try {
      await TrainerService.respond(b, accept: accept);
      _snack(accept ? tr('tr.accepted_snack') : tr('tr.declined_snack'), accept ? Colors.green : Colors.orange);
    } catch (e) {
      _snack(_errorText(e), Colors.red);
    }
  }

  Future<void> _answerReschedule(Map<String, dynamic> b, bool approve) async {
    try {
      await TrainerService.answerReschedule(b, approve: approve);
      _snack(approve ? tr('tr.resched_approved') : tr('tr.resched_rejected'), approve ? Colors.green : Colors.orange);
    } catch (e) {
      _snack(_errorText(e), Colors.red);
    }
  }

  (String, Color) _statusChip(String status) {
    switch (status) {
      case TrainerStatus.pending:
        return (tr('tr.st_pending_trainer'), Colors.amber);
      case TrainerStatus.confirmed:
        return (tr('tr.st_confirmed'), Colors.greenAccent);
      case TrainerStatus.declined:
        return (tr('tr.st_declined_by_you'), Colors.redAccent);
      case TrainerStatus.cancelled:
        return (tr('tr.st_cancelled'), AppColors.muted);
      case TrainerStatus.rescheduleRequested:
        return (tr('tr.st_reschedule'), Colors.orangeAccent);
      default:
        return (status, AppColors.muted);
    }
  }

  Widget _card(Map<String, dynamic> b) {
    final String clientName = (b['clientName'] ?? '').toString().isEmpty ? tr('tr.unknown_client') : b['clientName'];
    final String date = (b['date'] ?? '-').toString();
    final String time = (b['time'] ?? '-').toString();
    final String status = (b['status'] ?? TrainerStatus.confirmed).toString();
    final (String label, Color color) = _statusChip(status);
    final String venue = (b['locationName'] ?? '').toString();

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
                CircleAvatar(
                  backgroundColor: AppColors.card,
                  child: Icon(Icons.person, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(clientName, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('$date | $time', style: TextStyle(color: AppColors.muted)),
                      if (TrainerService.detailsLine(b) != null)
                        Text(TrainerService.detailsLine(b)!, style: TextStyle(color: AppColors.accent, fontSize: 12)),
                      if (venue.isNotEmpty) Text(venue, style: TextStyle(color: AppColors.muted, fontSize: 12)),
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
            if (status == TrainerStatus.pending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      onPressed: () => _respond(b, true),
                      child: Text(tr('tr.accept')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      onPressed: () => _respond(b, false),
                      child: Text(tr('tr.decline')),
                    ),
                  ),
                ],
              ),
            ],
            if (status == TrainerStatus.rescheduleRequested) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orangeAccent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr('tr.reschedule_ask', {'date': '${b['requestedDate']}', 'time': '${b['requestedTime']}'}),
                      style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            onPressed: () => _answerReschedule(b, true),
                            child: Text(tr('tr.approve')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                            ),
                            onPressed: () => _answerReschedule(b, false),
                            child: Text(tr('tr.reject')),
                          ),
                        ),
                      ],
                    ),
                  ],
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
      drawer: const PlayerDrawer(activePage: 'trainer_dashboard'),
      appBar: AppBar(
        title: Text(tr('tr.panel_title'), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    tr('tr.your_bookings'),
                    style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(tr('tr.schedule_btn')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TrainerScheduleScreen()));
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('reservations')
                    .where('trainerId', isEqualTo: user!.uid)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text(tr('tr.error', {'error': '${snap.error}'}), style: const TextStyle(color: Colors.redAccent)));
                  }
                  if (!snap.hasData) {
                    return Center(child: CircularProgressIndicator(color: AppColors.accent));
                  }
                  final list = snap.data!.docs.map((d) => {...d.data(), 'id': d.id}).toList();
                  list.sort((a, b) {
                    final int r = _rank('${a['status']}').compareTo(_rank('${b['status']}'));
                    if (r != 0) return r;
                    final Timestamp? t1 = a['timestamp'] as Timestamp?;
                    final Timestamp? t2 = b['timestamp'] as Timestamp?;
                    if (t1 == null || t2 == null) return 0;
                    return t2.compareTo(t1);
                  });
                  if (list.isEmpty) {
                    return Center(
                      child: Text(tr('tr.no_bookings'), style: TextStyle(color: AppColors.muted, fontSize: 16)),
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
