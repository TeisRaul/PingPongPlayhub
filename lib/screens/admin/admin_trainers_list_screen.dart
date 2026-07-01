import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_trainer_detail_screen.dart';

class AdminTrainersListScreen extends StatefulWidget {
  const AdminTrainersListScreen({super.key});

  @override
  State<AdminTrainersListScreen> createState() => _AdminTrainersListScreenState();
}

class _AdminTrainersListScreenState extends State<AdminTrainersListScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Gestiune Antrenori', style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Caută antrenor după nume...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF131A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.toLowerCase().trim();
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').where('isTrainer', isEqualTo: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Niciun antrenor găsit.', style: TextStyle(color: Colors.grey)),
                  );
                }

                final allTrainers = snapshot.data!.docs;
                final trainers = allTrainers.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final firstName = (data['firstName'] ?? '').toString().toLowerCase();
                  final lastName = (data['lastName'] ?? '').toString().toLowerCase();
                  final fullName = '$firstName $lastName';
                  return _searchQuery.isEmpty || fullName.contains(_searchQuery);
                }).toList();

                if (trainers.isEmpty) {
                  return const Center(
                    child: Text('Niciun antrenor găsit cu acest nume.', style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: trainers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = trainers[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final firstName = data['firstName'] ?? 'Nume necunoscut';
                    final lastName = data['lastName'] ?? '';
                    final fullName = '$firstName $lastName';
                    final pricePerMonth = data['trainerPricePerMonth'];
                    final pricePerSession = data['trainerPricePerSession'] ?? data['trainerPrice'];
                    
                    String priceText = '';
                    if (pricePerSession != null) priceText += '$pricePerSession RON / Ședință';
                    if (pricePerMonth != null) priceText += (priceText.isEmpty ? '' : ' | ') + '$pricePerMonth RON / Lună';
                    if (priceText.isEmpty) priceText = 'Fără preț setat';

                    return Card(
                      color: const Color(0xFF131A2A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: const Color(0xFFFFD700).withOpacity(0.3)),
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.sports_kabaddi,
                          color: Color(0xFFFFD700),
                        ),
                        title: Text(fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text(priceText, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminTrainerDetailScreen(trainerId: doc.id, trainerData: data),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
