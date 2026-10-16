import 'package:flutter/material.dart';
import '../../services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/hour_utils.dart';
import '../check_in_flow.dart';
import '../match_detail_screen.dart';
import '../../theme/app_theme.dart';
import '../../services/card_booking_service.dart';

class AdminMatchesListScreen extends StatefulWidget {
  final String? initialSearchQuery;
  const AdminMatchesListScreen({super.key, this.initialSearchQuery});

  @override
  State<AdminMatchesListScreen> createState() => _AdminMatchesListScreenState();
}

class _AdminMatchesListScreenState extends State<AdminMatchesListScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchQuery != null && widget.initialSearchQuery!.isNotEmpty) {
      _searchQuery = widget.initialSearchQuery!.toLowerCase().trim();
      _searchController.text = widget.initialSearchQuery!;
    }
  }

  Stream<QuerySnapshot> _getMatchesStream() {
    return FirebaseFirestore.instance
        .collection('matches')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Gestiune Meciuri', style: TextStyle(color: AppColors.text, fontSize: 18)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Caută după nume jucător, sală sau dată...',
                hintStyle: TextStyle(color: AppColors.muted),
                prefixIcon: Icon(Icons.search, color: AppColors.muted),
                filled: true,
                fillColor: AppColors.card2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase().trim();
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getMatchesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: AppColors.accent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text('Nu există meciuri.', style: TextStyle(color: AppColors.muted)),
                  );
                }

                final allMatches = snapshot.data!.docs;
                final filteredMatches = allMatches.where((doc) {
                  if (_searchQuery.isEmpty) return true;
                  final data = doc.data() as Map<String, dynamic>;
                  final venueName = (data['locationName'] ?? '').toString().toLowerCase();
                  final date = (data['date'] ?? '').toString().toLowerCase();
                  final host = (data['hostUsername'] ?? '').toString().toLowerCase();

                  // Extract player names
                  final List players = (data['joinedPlayers'] as List?) ?? [];
                  bool matchPlayer = false;
                  for (var p in players) {
                    final pName = (p is Map ? (p['username'] ?? '') : p).toString().toLowerCase();
                    if (pName.contains(_searchQuery)) {
                      matchPlayer = true;
                      break;
                    }
                  }

                  return venueName.contains(_searchQuery) ||
                         host.contains(_searchQuery) ||
                         date.contains(_searchQuery) ||
                         matchPlayer;
                }).toList();

                if (filteredMatches.isEmpty) {
                  return Center(
                    child: Text('Nu am găsit meciuri pentru căutarea ta.', style: TextStyle(color: AppColors.muted)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredMatches.length,
                  itemBuilder: (context, index) {
                    final data = filteredMatches[index].data() as Map<String, dynamic>;
                    
                    final date = data['date'] ?? 'N/A';
                    final time = '${formatHour(data['startHour'])}-${formatHour(data['endHour'])}';
                    final venueName = data['locationName'] ?? 'Sală Necunoscută';
                    final status = data['status'] ?? 'pending';
                    
                    final players = (data['joinedPlayers'] as List?) ?? [];
                    final pCount = players.length;
                    final maxPlayers = data['maxPlayers'] ?? 2;

                    Color statusColor = AppColors.muted;
                    if (status == 'completed') statusColor = Colors.green;
                    if (status == 'cancelled') statusColor = Colors.red;
                    if (status == 'scheduled') statusColor = Colors.amber;

                    return Card(
                      color: AppColors.card,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AppColors.border),
                      ),
                      child: ListTile(
                        title: Text(
                          '$venueName ($date $time)',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('Jucători: $pCount/$maxPlayers', style: TextStyle(color: AppColors.muted)),
                            const SizedBox(height: 4),
                            Text('Status: $status', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        trailing: Icon(Icons.chevron_right, color: AppColors.muted),
                        onTap: () {
                          // Show detail modal or screen
                          _showMatchDetails(context, filteredMatches[index].id, data);
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

  void _showMatchDetails(BuildContext context, String matchId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Detalii Meci', style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('Sală: ${data['locationName'] ?? 'N/A'}', style: TextStyle(color: AppColors.muted, fontSize: 16)),
              Text('Dată: ${data['date'] ?? 'N/A'}, ${formatHour(data['startHour'])}-${formatHour(data['endHour'])}', style: TextStyle(color: AppColors.muted, fontSize: 16)),
              Text('Sport: ${data['sport'] ?? 'N/A'}', style: TextStyle(color: AppColors.muted, fontSize: 16)),
              Text('Check-in: ${data['checkedIn'] == true ? 'efectuat' : 'neefectuat'}', style: TextStyle(color: AppColors.muted, fontSize: 16)),
              Text('Creat de: ${data['hostUsername'] ?? data['hostUid'] ?? 'N/A'}', style: TextStyle(color: AppColors.muted, fontSize: 14)),
              Divider(color: AppColors.muted, height: 30),
              Text('Jucători:', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...(data['joinedPlayers'] as List? ?? []).map((p) {
                final m = p is Map ? p : const {};
                return Text('- ${m['username'] ?? p} (Nivel: ${m['level'] ?? '-'})', style: TextStyle(color: AppColors.muted));
              }),
              
              const SizedBox(height: 32),
              
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      this.context,
                      MaterialPageRoute(
                        builder: (_) => MatchDetailScreen(matchId: matchId, mode: MatchDetailMode.admin),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Deschide pagina meciului'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: BorderSide(color: AppColors.accent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (data['status'] != 'cancelled' && data['status'] != 'completed' && data['checkedIn'] != true) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      CheckInFlow.processCode(this.context, matchId, isAdmin: true);
                    },
                    icon: const Icon(Icons.how_to_reg, size: 18),
                    label: const Text('Check-in (Admin)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.good,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (data['status'] != 'cancelled')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _promptCancelMatch(matchId);
                    },
                    icon: const Icon(Icons.cancel, size: 18),
                    label: const Text('Anulează Meci (Admin)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Închide'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _promptCancelMatch(String matchId) {
    final TextEditingController reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Anulare Meci', style: TextStyle(color: AppColors.text)),
          content: TextField(
            controller: reasonController,
            style: TextStyle(color: AppColors.text),
            decoration: InputDecoration(
              hintText: 'Motivul anulării (ex: Eroare de sistem)...',
              hintStyle: TextStyle(color: AppColors.muted),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('ÎNAPOI', style: TextStyle(color: AppColors.muted)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Introduceți un motiv!'), backgroundColor: Colors.red));
                  return;
                }
                
                try {
                  final mRef = FirebaseFirestore.instance.collection('matches').doc(matchId);
                  final mData = (await mRef.get()).data();
                  if (mData != null && CardBookingService.isCardPaid(mData)) {
                    // Plătită cu cardul: motivul se notează, apoi serverul anulează și returnează banii.
                    await mRef.update({'cancellationReason': reasonController.text.trim()});
                    await CardBookingService.cancel(matchId, 'cancel', silent: true);
                  } else {
                    await mRef.update({
                      'status': 'cancelled',
                      'cancellationReason': reasonController.text.trim(),
                    });
                  }
                  if (mData != null) {
                    // Jucătorii și sala află că meciul a fost anulat de administrator (popup + email).
                    await NotificationService.matchCancelled(matchId, mData, byName: 'Playhub');
                  }
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meci anulat cu succes!'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: Text('ANULEAZĂ MECI', style: TextStyle(color: AppColors.text)),
            ),
          ],
        );
      },
    );
  }
}
