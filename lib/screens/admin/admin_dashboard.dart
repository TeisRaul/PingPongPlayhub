import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_public_location_screen.dart';
import 'admin_venues_list_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _userCount = 0;
  int _venueCount = 0;
  int _matchCount = 0;
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final usersSnap = await FirebaseFirestore.instance.collection('users').count().get();
      final venuesSnap = await FirebaseFirestore.instance.collection('venues').count().get();
      final matchesSnap = await FirebaseFirestore.instance.collection('matches').count().get();

      if (mounted) {
        setState(() {
          _userCount = usersSnap.count ?? 0;
          _venueCount = venuesSnap.count ?? 0;
          _matchCount = matchesSnap.count ?? 0;
          _loadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingStats = false);
      }
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF131A2A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.admin_panel_settings, color: Color(0xFFFF0055), size: 32),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Super Admin',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'Ai control deplin asupra platformei.',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          if (_loadingStats)
            const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          else
            Row(
              children: [
                _buildStatCard('Utilizatori', '$_userCount', Icons.people, const Color(0xFF00E5FF)),
                const SizedBox(width: 12),
                _buildStatCard('Săli', '$_venueCount', Icons.storefront, const Color(0xFF00FF66)),
                const SizedBox(width: 12),
                _buildStatCard('Meciuri', '$_matchCount', Icons.sports_tennis, const Color(0xFFFF0055)),
              ],
            ),
          
          const SizedBox(height: 32),
          const Text(
            'Acțiuni Rapide',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 16),
          
          // Add Public Location Button
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddPublicLocationScreen()),
              );
            },
            icon: const Icon(Icons.park, size: 22),
            label: const Text('Adaugă Locație Publică', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF66),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          
          // Manage Venues Button
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminVenuesListScreen()),
              );
            },
            icon: const Icon(Icons.settings, size: 22),
            label: const Text('Gestiune Săli & Plăți', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
