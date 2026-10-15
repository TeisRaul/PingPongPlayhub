import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_trainer_detail_screen.dart';
import '../../theme/app_theme.dart';

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
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Gestiune Antrenori', style: TextStyle(color: AppColors.text, fontSize: 18)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Caută antrenor după nume...',
                hintStyle: TextStyle(color: AppColors.muted),
                prefixIcon: Icon(Icons.search, color: AppColors.muted),
                filled: true,
                fillColor: AppColors.card,
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
                  return Center(child: CircularProgressIndicator(color: AppColors.accent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text('Niciun antrenor găsit.', style: TextStyle(color: AppColors.muted)),
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
                  return Center(
                    child: Text('Niciun antrenor găsit cu acest nume.', style: TextStyle(color: AppColors.muted)),
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
                      color: AppColors.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AppColors.gold.withOpacity(0.3)),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.sports_kabaddi,
                          color: AppColors.gold,
                        ),
                        title: Text(fullName, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                        subtitle: Text(priceText, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        trailing: Icon(Icons.arrow_forward_ios, color: AppColors.muted, size: 16),
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
