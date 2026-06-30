import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/player_drawer.dart';
import 'trainer_schedule_screen.dart';

class TrainerDashboard extends StatefulWidget {
  const TrainerDashboard({super.key});

  @override
  State<TrainerDashboard> createState() => _TrainerDashboardState();
}

class _TrainerDashboardState extends State<TrainerDashboard> {
  final user = FirebaseAuth.instance.currentUser;
  bool _isLoading = true;
  List<Map<String, dynamic>> _bookings = [];

  @override
  void initState() {
    super.initState();
    _fetchTrainerBookings();
  }

  Future<void> _fetchTrainerBookings() async {
    if (user == null) return;
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('reservations')
          .where('trainerId', isEqualTo: user!.uid)
          .orderBy('timestamp', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _bookings = querySnapshot.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching trainer bookings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Nu ești autentificat.')));
    }

    return Scaffold(
      drawer: const PlayerDrawer(activePage: 'trainer_dashboard'),
      appBar: AppBar(
        title: const Text('Panou Antrenor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Programările tale',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.schedule, size: 18),
                        label: const Text('Program'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const TrainerScheduleScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_bookings.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Nu ai nicio programare momentan.',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _bookings.length,
                        itemBuilder: (context, index) {
                          final b = _bookings[index];
                          final clientName = b['clientName'] ?? 'Client Necunoscut';
                          final date = b['date'] ?? 'Dată necunoscută';
                          final time = b['time'] ?? 'Oră necunoscută';
                          
                          return Card(
                            color: const Color(0xFF1E293B),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFF131A2A),
                                child: Icon(Icons.person, color: Color(0xFF00E5FF)),
                              ),
                              title: Text(clientName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text('$date | $time', style: const TextStyle(color: Colors.grey)),
                              trailing: const Icon(Icons.calendar_today, color: Color(0xFF00E5FF), size: 20),
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
