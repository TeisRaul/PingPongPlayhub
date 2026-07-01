import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/player_drawer.dart';
import 'package:intl/intl.dart';

class ClientSessionsScreen extends StatefulWidget {
  const ClientSessionsScreen({super.key});

  @override
  State<ClientSessionsScreen> createState() => _ClientSessionsScreenState();
}

class _ClientSessionsScreenState extends State<ClientSessionsScreen> {
  final user = FirebaseAuth.instance.currentUser;
  bool _isLoading = true;
  List<Map<String, dynamic>> _sessions = [];

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  Future<void> _fetchSessions() async {
    if (user == null) return;
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('reservations')
          .where('creatorId', isEqualTo: user!.uid)
          .where('trainerId', isNotEqualTo: null)
          .orderBy('trainerId') // Needed when using inequality
          .get();

      // Because of Firestore compound query limits with inequality, we might need to filter locally
      // if orderBy isn't perfectly matching the requirements, but this should work for now.
      
      if (mounted) {
        setState(() {
          _sessions = querySnapshot.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
          
          // Sort by date manually to be safe
          _sessions.sort((a, b) {
            final t1 = a['timestamp'] as Timestamp?;
            final t2 = b['timestamp'] as Timestamp?;
            if (t1 == null || t2 == null) return 0;
            return t2.compareTo(t1); // descending
          });
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching client sessions: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _requestReschedule(String reservationId, String currentDate, String currentTime) async {
    DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (selectedDate == null) return;

    TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
    );
    if (selectedTime == null) return;

    final DateFormat formatter = DateFormat('dd.MM.yyyy');
    final String requestedDate = formatter.format(selectedDate);
    final String requestedTime = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

    try {
      await FirebaseFirestore.instance.collection('reservations').doc(reservationId).update({
        'status': 'reschedule_requested',
        'requestedDate': requestedDate,
        'requestedTime': requestedTime,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cererea de modificare a fost trimisă antrenorului!'), backgroundColor: Colors.green),
        );
        _fetchSessions(); // refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Nu ești autentificat.')));
    }

    return Scaffold(
      drawer: const PlayerDrawer(activePage: 'client_sessions'),
      appBar: AppBar(
        title: const Text('Sesiuni Antrenor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Programările tale cu Antrenorii',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (_sessions.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Nu ai nicio sesiune cu antrenor programată.',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final b = _sessions[index];
                          final venueName = b['locationName'] ?? 'Sală Necunoscută';
                          final date = b['date'] ?? 'Dată necunoscută';
                          final time = b['time'] ?? 'Oră necunoscută';
                          final status = b['status'] ?? 'confirmed';
                          final resDate = b['requestedDate'];
                          final resTime = b['requestedTime'];

                          return Card(
                            color: const Color(0xFF1E293B),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.sports, color: Color(0xFF00E5FF), size: 28),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(venueName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                            const SizedBox(height: 4),
                                            Text('$date | $time', style: const TextStyle(color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (status == 'reschedule_requested')
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
                                              'Ai propus mutarea pe $resDate la ora $resTime. Se așteaptă răspunsul antrenorului.',
                                              style: const TextStyle(color: Colors.orange, fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else ...[
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.edit_calendar, size: 18),
                                        label: const Text('Solicită Modificare Program'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF00E5FF),
                                          side: const BorderSide(color: Color(0xFF00E5FF)),
                                        ),
                                        onPressed: () => _requestReschedule(b['id'], date, time),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
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
