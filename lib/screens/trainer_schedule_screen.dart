import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';

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

  static const Map<String, String> _dayKeys = {
    'Luni': 'day.mon', 'Marți': 'day.tue', 'Miercuri': 'day.wed', 'Joi': 'day.thu',
    'Vineri': 'day.fri', 'Sâmbătă': 'day.sat', 'Duminică': 'day.sun',
  };
  String _dayLabel(String day) => _dayKeys[day] != null ? tr(_dayKeys[day]!) : day;

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
          SnackBar(content: Text(tr('tr.sched_updated')), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('tr.error', {'error': '$e'})), backgroundColor: Colors.red),
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
          backgroundColor: AppColors.card,
          title: Text(tr('tr.sched_day', {'day': _dayLabel(day)}), style: TextStyle(color: AppColors.text)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: AppColors.text),
            decoration: InputDecoration(
              labelText: tr('tr.sched_hint'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('common.cancel'), style: const TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _schedule[day] = controller.text.trim();
                });
                Navigator.pop(context);
              },
              child: Text(tr('common.save')),
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
        title: Text(tr('tr.sched_title'), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSchedule,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _schedule.keys.map((day) {
                return Card(
                  color: AppColors.card2,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(_dayLabel(day), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                    subtitle: Text(_schedule[day] == 'Liber' ? tr('tr.day_off') : _schedule[day]!, style: TextStyle(color: AppColors.accent)),
                    trailing: Icon(Icons.edit, color: AppColors.muted),
                    onTap: () => _editDaySchedule(day),
                  ),
                );
              }).toList(),
            ),
    );
  }
}
