import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/mock_locations.dart';
import '../utils/level_utils.dart';
import '../widgets/city_selector.dart';

class FindMatchTab extends StatefulWidget {
  const FindMatchTab({super.key});

  @override
  State<FindMatchTab> createState() => _FindMatchTabState();
}

class _FindMatchTabState extends State<FindMatchTab> {
  String _searchQuery = '';
  String _filterCity = 'Toate';
  String _filterLocationId = 'Toate';

  List<PingPongLocation> _allLocations = List.from(mockLocations);
  bool _isLoadingLocs = false;

  @override
  void initState() {
    super.initState();
    _loadFirestoreLocations();
  }

  Future<void> _loadFirestoreLocations() async {
    if (!mounted) return;
    setState(() => _isLoadingLocs = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('venues')
          .get();

      final List<PingPongLocation> fetched = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String id = doc.id;
        final String name = data['venueName'] ?? '';
        final String city = data['city'] ?? '';
        final int numTables = data['totalTables'] ?? 4;

        final schedule = data['schedule'] as Map<dynamic, dynamic>?;
        final lvSchedule = schedule?['Luni-Vineri'] as String? ?? '09:00 - 22:00';
        final hoursParts = lvSchedule.split('-');
        int openHour = 9;
        int closeHour = 22;
        if (hoursParts.length == 2) {
          final startStr = hoursParts[0].trim().split(':').first;
          final endStr = hoursParts[1].trim().split(':').first;
          openHour = int.tryParse(startStr) ?? 9;
          closeHour = int.tryParse(endStr) ?? 22;
        }

        fetched.add(PingPongLocation(
          id: id,
          city: city,
          name: name,
          openHour: openHour,
          closeHour: closeHour,
          numTables: numTables,
        ));
      }

      final List<PingPongLocation> merged = List.from(mockLocations);
      for (var loc in fetched) {
        final exists = merged.any((m) =>
            m.id == loc.id || m.name.toLowerCase() == loc.name.toLowerCase());
        if (!exists) {
          merged.add(loc);
        }
      }

      if (mounted) {
        setState(() {
          _allLocations = merged;
        });
      }
    } catch (e) {
      debugPrint('Eroare incarcare sali din Firestore in filtrul de meciuri: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocs = false);
      }
    }
  }

  List<String> get _cityOptions {
    final Set<String> cities = {};
    for (var loc in _allLocations) {
      if (loc.city.isNotEmpty) {
        cities.add(loc.city.trim());
      }
    }
    cities.addAll(romanianCities);
    final sorted = cities.toList()..sort();

    List<String> opts = ['Toate'];
    opts.addAll(sorted);
    return opts;
  }

  List<dynamic> get _locationOptions {
    List<dynamic> opts = [{'id': 'Toate', 'name': 'Toate'}];
    if (_filterCity == 'Toate') {
      opts.addAll(_allLocations.map((l) => {'id': l.id, 'name': l.name}));
    } else {
      opts.addAll(_allLocations
          .where((l) => l.city.trim().toLowerCase() == _filterCity.trim().toLowerCase())
          .map((l) => {'id': l.id, 'name': l.name}));
    }
    return opts;
  }

  Future<void> _joinMatch(String matchId, Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trebuie să fii autentificat!')));
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final guestUsername = userData['username'] ?? 'Jucător necunoscut';
      final guestAvatarUrl = userData['avatarUrl'];
      final guestRating = userData['rating'] ?? 0;
      final guestLevelName = LevelUtils.getLevelDetails(guestRating)['levelName'];

      final newPlayer = {
        'uid': user.uid,
        'username': guestUsername,
        'avatarUrl': guestAvatarUrl,
        'rating': guestRating,
        'level': guestLevelName,
        'role': 'guest'
      };

      List<dynamic> joinedPlayers = List.from(data['joinedPlayers'] ?? []);
      List<dynamic> joinedUids = List.from(data['joinedUids'] ?? []);
      int maxPlayers = data['maxPlayers'] ?? 2;

      joinedPlayers.add(newPlayer);
      joinedUids.add(user.uid);

      String newStatus = (joinedPlayers.length >= maxPlayers) ? 'matched' : 'open';

      await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
        'status': newStatus,
        'joinedPlayers': joinedPlayers,
        'joinedUids': joinedUids,
      });

      // Send join notification to host
      final hostUid = data['hostUid'];
      if (hostUid != null && hostUid != user.uid) {
        final newNotificationRef = FirebaseFirestore.instance.collection('notifications').doc();
        await FirebaseFirestore.instance.collection('notifications').doc(newNotificationRef.id).set({
          'toUid': hostUid,
          'fromUid': user.uid,
          'fromUsername': guestUsername,
          'fromAvatarUrl': guestAvatarUrl ?? '',
          'title': 'Jucător nou la masă',
          'body': '$guestUsername s-a alăturat meciului tău de pe data de ${data['date']}.',
          'type': 'match_join',
          'status': 'pending',
          'matchId': matchId,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Te-ai alăturat cu succes!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filtre
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF131A2A),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Caută oraș, jucător, locație...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CitySelectorField(
                      labelText: 'Selectează orașul',
                      selectedCity: _filterCity,
                      cityOptions: _cityOptions,
                      onCitySelected: (val) {
                        setState(() {
                          _filterCity = val;
                          _filterLocationId = 'Toate'; // reset location
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _filterLocationId,
                      decoration: const InputDecoration(labelText: 'Locație', contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      items: _locationOptions.map((l) => DropdownMenuItem<String>(value: l['id'], child: Text(l['name'], overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (val) => setState(() => _filterLocationId = val ?? 'Toate'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Lista Meciuri
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('matches').orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('A apărut o eroare la încărcare.', style: TextStyle(color: Colors.red)));
              }
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));

              final docs = snapshot.data!.docs;
              
              // Filtrare locala
              final filtered = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                
                if (data['visibility'] == 'private') return false;
                if (data['status'] == 'matched' || data['status'] == 'completed') return false;

                // Verificare trecut
                try {
                  final dateStr = data['date'] as String;
                  final startHour = data['startHour'] as int;
                  final matchStart = DateTime.parse('$dateStr ${startHour.toString().padLeft(2, '0')}:00:00');
                  if (DateTime.now().isAfter(matchStart)) return false;
                } catch (_) {}

                // Filtru Oras
                if (_filterCity != 'Toate' && data['city'] != _filterCity) return false;
                
                // Filtru Locatie
                if (_filterLocationId != 'Toate' && data['locationId'] != _filterLocationId) return false;

                // Search query
                if (_searchQuery.isNotEmpty) {
                  final searchStr = '${data['city']} ${data['hostUsername']} ${data['locationName']}'.toLowerCase();
                  if (!searchStr.contains(_searchQuery)) return false;
                }

                return true;
              }).toList();

              if (filtered.isEmpty) {
                return const Center(child: Text('Nu am găsit meciuri cu aceste filtre.', style: TextStyle(color: Colors.grey)));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final data = filtered[index].data() as Map<String, dynamic>;
                  final docId = filtered[index].id;
                  final currentUser = FirebaseAuth.instance.currentUser;
                  final List<dynamic> joinedUids = data['joinedUids'] ?? [];
                  final int maxPlayers = data['maxPlayers'] ?? 2;
                  final bool isMyMatch = currentUser != null && joinedUids.contains(currentUser.uid);
                  final bool isMatched = data['status'] == 'matched' || joinedUids.length >= maxPlayers;
                  
                  return Card(
                    color: const Color(0xFF131A2A),
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: const Color(0xFF1E293B),
                                backgroundImage: data['hostAvatarUrl'] != null && data['hostAvatarUrl'].toString().isNotEmpty
                                    ? NetworkImage(data['hostAvatarUrl'])
                                    : null,
                                child: data['hostAvatarUrl'] == null || data['hostAvatarUrl'].toString().isEmpty
                                    ? Text(data['hostUsername']?.substring(0, 1).toUpperCase() ?? 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(data['hostUsername'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                                    Text('Nivel: ${data['hostLevel'] ?? 'Necunoscut'}', style: TextStyle(color: const Color(0xFF00E5FF).withOpacity(0.8), fontSize: 12)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isMatched ? Colors.grey.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isMatched ? Colors.grey : Colors.green),
                                ),
                                child: Text(isMatched ? 'MATCHED' : 'OPEN', style: TextStyle(color: isMatched ? Colors.grey : Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                              )
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(child: Text('${data['locationName']} (${data['city']})', style: const TextStyle(color: Colors.white))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Text('${data['date']}', style: const TextStyle(color: Colors.white)),
                              const SizedBox(width: 16),
                              const Icon(Icons.access_time, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Text('${data['startHour']}:00 - ${data['endHour']}:00', style: const TextStyle(color: Colors.white)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(color: Colors.grey),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(data['paymentMethod'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text(data['paymentSplit'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  Text('${joinedUids.length} / $maxPlayers Jucători', style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                                ],
                              ),
                              ElevatedButton(
                                onPressed: (isMyMatch || isMatched) ? null : () => _joinMatch(docId, data),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  disabledBackgroundColor: Colors.grey[800],
                                  disabledForegroundColor: Colors.white54,
                                ),
                                child: Text(isMyMatch ? 'Meciul tău' : (isMatched ? 'Rezervat' : 'Joacă cu ei!')),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
