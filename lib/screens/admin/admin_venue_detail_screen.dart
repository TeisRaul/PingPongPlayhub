import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../venue_signup_screen.dart';
import 'add_public_location_screen.dart';

class AdminVenueDetailScreen extends StatefulWidget {
  final String venueId;
  final Map<String, dynamic> venueData;

  const AdminVenueDetailScreen({
    super.key,
    required this.venueId,
    required this.venueData,
  });

  @override
  State<AdminVenueDetailScreen> createState() => _AdminVenueDetailScreenState();
}

class _AdminVenueDetailScreenState extends State<AdminVenueDetailScreen> {
  late TextEditingController _nameController;
  late TextEditingController _cityController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.venueData['venueName'] ?? '');
    _cityController = TextEditingController(text: widget.venueData['city'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _updateVenueDetails() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).update({
        'venueName': _nameController.text.trim(),
        'city': _cityController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Detalii actualizate!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _manageMatches() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminVenueMatchesScreen(venueId: widget.venueId),
      ),
    );
  }

  Future<void> _deleteVenue() async {
    final bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131A2A),
        title: const Text('Ștergere Sală', style: TextStyle(color: Colors.white)),
        content: const Text('Ești sigur că vrei să ștergi această locație? Acțiunea este ireversibilă.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Șterge', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);
      try {
        await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).delete();
        if (mounted) {
          Navigator.pop(context); // back to venues list
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Locația a fost ștearsă!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Detalii Sală', style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _isLoading ? null : _deleteVenue,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nume Sală',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cityController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Oraș',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF131A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[800]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Detalii Terenuri', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Mese/Terenuri Indoor:', style: TextStyle(color: Colors.grey)),
                      Text('${widget.venueData['indoorTables'] ?? widget.venueData['totalTables'] ?? 0}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Mese/Terenuri Outdoor:', style: TextStyle(color: Colors.grey)),
                      Text('${widget.venueData['outdoorTables'] ?? 0}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _updateVenueDetails,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black))
                  : const Text('Salvează Nume/Oraș', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                if (widget.venueData['isPublic'] == true) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddPublicLocationScreen(
                        isEditMode: true,
                        venueId: widget.venueId,
                        venueData: widget.venueData,
                      ),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VenueSignupScreen(
                        isEditMode: true,
                        venueId: widget.venueId,
                        venueData: widget.venueData,
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.edit_document),
              label: const Text('Editează Sală Complet (Formular)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF131A2A),
                foregroundColor: Colors.amberAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.amberAccent),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(color: Colors.grey),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _manageMatches,
              icon: const Icon(Icons.list_alt),
              label: const Text('Gestionează Meciuri (Plăți)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF131A2A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _deleteVenue,
              icon: const Icon(Icons.delete),
              label: const Text('Șterge Sală', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminVenueMatchesScreen extends StatelessWidget {
  final String venueId;
  const AdminVenueMatchesScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Meciuri Sală', style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('matches')
            .where('locationId', isEqualTo: venueId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('Niciun meci înregistrat la această sală.', style: TextStyle(color: Colors.grey)),
            );
          }

          final matches = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: matches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = matches[index];
              final data = doc.data() as Map<String, dynamic>;
              final date = data['date'] ?? 'Fără dată';
              final startHour = data['startHour'] ?? 0;
              final status = data['status'] ?? 'open';
              final paymentStatus = data['paymentStatus'] ?? 'none';

              return Card(
                color: const Color(0xFF131A2A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text('$date | Ora $startHour:00', style: const TextStyle(color: Colors.white)),
                  subtitle: Text('Status: $status | Plată: $paymentStatus', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: ElevatedButton(
                    onPressed: () {
                      _showMatchAdminOptions(context, doc.id, data);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Administrează'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showMatchAdminOptions(BuildContext context, String matchId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131A2A),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Opțiuni Admin Meci', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
                  'paymentStatus': 'confirmed',
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plată aprobată manual!'), backgroundColor: Colors.green));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66), foregroundColor: Colors.black),
              child: const Text('Aprobă Plată Manual'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
                  'status': 'cancelled',
                  'paymentStatus': 'refunded',
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meci anulat și plată rambursată!'), backgroundColor: Colors.orange));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Anulează Meci (Refund)'),
            ),
          ],
        ),
      ),
    );
  }
}
