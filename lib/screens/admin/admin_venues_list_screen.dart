import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_venue_detail_screen.dart';
import '../../theme/app_theme.dart';

class AdminVenuesListScreen extends StatefulWidget {
  const AdminVenuesListScreen({super.key});

  @override
  State<AdminVenuesListScreen> createState() => _AdminVenuesListScreenState();
}

class _AdminVenuesListScreenState extends State<AdminVenuesListScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Gestiune Săli', style: TextStyle(color: AppColors.text, fontSize: 18)),
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
                hintText: 'Caută după oraș...',
                hintStyle: TextStyle(color: AppColors.muted),
                prefixIcon: Icon(Icons.location_city, color: AppColors.muted),
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
              stream: FirebaseFirestore.instance.collection('venues').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: AppColors.accent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text('Nicio sală găsită.', style: TextStyle(color: AppColors.muted)),
                  );
                }

          final allVenues = snapshot.data!.docs;
          final venues = allVenues.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final city = (data['city'] ?? '').toString().toLowerCase();
            return _searchQuery.isEmpty || city.contains(_searchQuery);
          }).toList();
          // Sălile care așteaptă aprobarea apar primele.
          venues.sort((a, b) {
            final aPending = (a.data() as Map<String, dynamic>)['isVerified'] == false ? 0 : 1;
            final bPending = (b.data() as Map<String, dynamic>)['isVerified'] == false ? 0 : 1;
            return aPending.compareTo(bPending);
          });

          if (venues.isEmpty) {
            return Center(
              child: Text('Nicio sală găsită pentru acest oraș.', style: TextStyle(color: AppColors.muted)),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: venues.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = venues[index];
              final data = doc.data() as Map<String, dynamic>;
              final venueName = data['venueName'] ?? 'Sală necunoscută';
              final city = data['city'] ?? 'Oraș necunoscut';
              final isPublic = data['isPublic'] ?? false;
              final isPending = data['isVerified'] == false;

              return Card(
                color: AppColors.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isPublic ? AppColors.good : AppColors.accent.withValues(alpha: 0.3)),
                ),
                child: ListTile(
                  leading: Icon(
                    isPublic ? Icons.park : Icons.storefront,
                    color: isPublic ? AppColors.good : AppColors.accent,
                  ),
                  title: Text(venueName, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                  subtitle: Text('$city${isPublic ? " (Public)" : ""}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPending)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orangeAccent),
                          ),
                          child: const Text('În așteptare', style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      if (isPending) const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_ios, color: AppColors.muted, size: 16),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminVenueDetailScreen(venueId: doc.id, venueData: data),
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
