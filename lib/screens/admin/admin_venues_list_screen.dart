import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_venue_detail_screen.dart';

class AdminVenuesListScreen extends StatelessWidget {
  const AdminVenuesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Gestiune Săli', style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('venues').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('Nicio sală găsită.', style: TextStyle(color: Colors.grey)),
            );
          }

          final venues = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: venues.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = venues[index];
              final data = doc.data() as Map<String, dynamic>;
              final venueName = data['venueName'] ?? 'Sală necunoscută';
              final city = data['city'] ?? 'Oraș necunoscut';
              final isPublic = data['isPublic'] ?? false;

              return Card(
                color: const Color(0xFF131A2A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isPublic ? const Color(0xFF00FF66) : const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                ),
                child: ListTile(
                  leading: Icon(
                    isPublic ? Icons.park : Icons.storefront,
                    color: isPublic ? const Color(0xFF00FF66) : const Color(0xFF00E5FF),
                  ),
                  title: Text(venueName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text('$city${isPublic ? " (Public)" : ""}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
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
    );
  }
}
