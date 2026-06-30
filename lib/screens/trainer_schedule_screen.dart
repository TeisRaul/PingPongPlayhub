import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TrainerScheduleScreen extends StatefulWidget {
  const TrainerScheduleScreen({super.key});

  @override
  State<TrainerScheduleScreen> createState() => _TrainerScheduleScreenState();
}

class _TrainerScheduleScreenState extends State<TrainerScheduleScreen> {
  final user = FirebaseAuth.instance.currentUser;
  bool _isLoading = true;
  
  Map<String, String> _schedule = {
    'Luni': '08:00 - 20:00',
    'Marți': '08:00 - 20:00',
    'Miercuri': '08:00 - 20:00',
    'Joi': '08:00 - 20:00',
    'Vineri': '08:00 - 20:00',
    'Sâmbătă': 'Liber',
    'Duminică': 'Liber',
  };

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('trainerSchedule')) {
          setState(() {
            _schedule = Map<String, String>.from(data['trainerSchedule']);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading schedule: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveSchedule() async {
    if (user == null) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
        'trainerSchedule': _schedule,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Program actualizat!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _editDaySchedule(String day) async {
    TextEditingController controller = TextEditingController(text: _schedule[day]);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131A2A),
          title: Text('Program $day', style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Interval orar (ex: 10:00 - 18:00 sau Liber)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anulează', style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _schedule[day] = controller.text.trim();
                });
                Navigator.pop(context);
              },
              child: const Text('Salvează'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Program Antrenor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSchedule,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _schedule.keys.map((day) {
                return Card(
                  color: const Color(0xFF1E293B),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(day, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(_schedule[day]!, style: const TextStyle(color: Color(0xFF00E5FF))),
                    trailing: const Icon(Icons.edit, color: Colors.grey),
                    onTap: () => _editDaySchedule(day),
                  ),
                );
              }).toList(),
            ),
    );
  }
}
