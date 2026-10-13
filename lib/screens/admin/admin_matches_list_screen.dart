import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/hour_utils.dart';
import '../check_in_flow.dart';
import '../match_detail_screen.dart';

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
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Gestiune Meciuri', style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Caută după nume jucător, sală sau dată...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E293B),
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
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Nu există meciuri.', style: TextStyle(color: Colors.grey)),
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
                  return const Center(
                    child: Text('Nu am găsit meciuri pentru căutarea ta.', style: TextStyle(color: Colors.grey)),
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

                    Color statusColor = Colors.grey;
                    if (status == 'completed') statusColor = Colors.green;
                    if (status == 'cancelled') statusColor = Colors.red;
                    if (status == 'scheduled') statusColor = Colors.amber;

                    return Card(
                      color: const Color(0xFF131A2A),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[800]!),
                      ),
                      child: ListTile(
                        title: Text(
                          '$venueName ($date $time)',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('Jucători: $pCount/$maxPlayers', style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text('Status: $status', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
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
      backgroundColor: const Color(0xFF131A2A),
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
              const Text('Detalii Meci', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('Sală: ${data['locationName'] ?? 'N/A'}', style: const TextStyle(color: Colors.grey, fontSize: 16)),
              Text('Dată: ${data['date'] ?? 'N/A'}, ${formatHour(data['startHour'])}-${formatHour(data['endHour'])}', style: const TextStyle(color: Colors.grey, fontSize: 16)),
              Text('Sport: ${data['sport'] ?? 'N/A'}', style: const TextStyle(color: Colors.grey, fontSize: 16)),
              Text('Check-in: ${data['checkedIn'] == true ? 'efectuat' : 'neefectuat'}', style: const TextStyle(color: Colors.grey, fontSize: 16)),
              Text('Creat de: ${data['hostUsername'] ?? data['hostUid'] ?? 'N/A'}', style: const TextStyle(color: Colors.grey, fontSize: 14)),
              const Divider(color: Colors.grey, height: 30),
              const Text('Jucători:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...(data['joinedPlayers'] as List? ?? []).map((p) {
                final m = p is Map ? p : const {};
                return Text('- ${m['username'] ?? p} (Nivel: ${m['level'] ?? '-'})', style: const TextStyle(color: Colors.grey));
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
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF00E5FF)),
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
                      backgroundColor: const Color(0xFF00FF66),
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
                    backgroundColor: const Color(0xFF00E5FF),
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
          backgroundColor: const Color(0xFF131A2A),
          title: const Text('Anulare Meci', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: reasonController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Motivul anulării (ex: Eroare de sistem)...',
              hintStyle: TextStyle(color: Colors.grey),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ÎNAPOI', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Introduceți un motiv!'), backgroundColor: Colors.red));
                  return;
                }
                
                try {
                  await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
                    'status': 'cancelled',
                    'cancellationReason': reasonController.text.trim(),
                  });
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meci anulat cu succes!'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('ANULEAZĂ MECI', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
