import 'package:flutter/material.dart';
import '../utils/player_name.dart';
import '../services/notification_service.dart';
import '../l10n/strings.dart';
import '../data/sports.dart';
import '../utils/hour_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/booking_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/mock_locations.dart';
import '../utils/level_utils.dart';
import '../widgets/city_selector.dart';
import '../theme/app_theme.dart';

class FindMatchTab extends StatefulWidget {
  const FindMatchTab({super.key});

  @override
  State<FindMatchTab> createState() => _FindMatchTabState();
}

class _FindMatchTabState extends State<FindMatchTab> {
  String _searchQuery = '';
  String _filterCity = 'Toate';
  String _filterLocationId = 'Toate';
  List<String> _selectedSports = [];

  List<PingPongLocation> _allLocations = [];

  @override
  void initState() {
    super.initState();
    _loadFirestoreLocations();
  }

  Future<void> _loadFirestoreLocations() async {
    if (!mounted) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('venues')
          .get();

      final List<PingPongLocation> fetched = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['isVerified'] == false) continue; // sală în așteptarea aprobării
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

      final List<PingPongLocation> merged = [];
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
      final guestUsername = playerDisplayName(userData, email: user.email, fallback: tr('common.unknown_player'));
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

      final String hostUid = (data['hostUid'] ?? '').toString();
      final nArgs = {...NotificationService.matchArgs(data), 'player': guestUsername, 'host': (data['hostUsername'] ?? '').toString()};

      // Gazda vrea să aprobe manual: trimitem cererea, nu intrăm direct la masă.
      if (data['requireApproval'] == true && hostUid.isNotEmpty && hostUid != user.uid) {
        final List<dynamic> already = List<dynamic>.from(data['joinRequestUids'] ?? []);
        if (already.contains(user.uid)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('n.request_already')), backgroundColor: Colors.orangeAccent));
          }
          return;
        }
        await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
          'joinRequestUids': FieldValue.arrayUnion([user.uid]),
        });
        await NotificationService.send(
          toUid: hostUid,
          type: 'join_request',
          titleKey: 'n.join_req_title',
          bodyKey: 'n.join_req_body',
          args: nArgs,
          matchId: matchId,
          extra: {'player': newPlayer, 'fromUsername': guestUsername, 'fromAvatarUrl': guestAvatarUrl ?? ''},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('n.request_sent_snack')), backgroundColor: Colors.green));
        }
        return;
      }

      final result = await BookingService.joinMatch(matchId, newPlayer);
      if (result != JoinResult.joined) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(BookingService.joinMessage(result)), backgroundColor: Colors.orangeAccent),
          );
        }
        return;
      }

      // Gazda și sala află că s-a alăturat cineva (popup + email).
      await NotificationService.send(
        toUid: hostUid,
        type: 'match_join',
        titleKey: 'n.joined_title',
        bodyKey: 'n.joined_body',
        args: nArgs,
        matchId: matchId,
      );

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
          color: AppColors.card,
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Caută oraș, jucător, locație...',
                  prefixIcon: Icon(Icons.search, color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.card2,
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
                      initialValue: _filterLocationId,
                      decoration: const InputDecoration(labelText: 'Locație', contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      items: _locationOptions.map((l) => DropdownMenuItem<String>(value: l['id'], child: Text(l['name'], overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (val) => setState(() => _filterLocationId = val ?? 'Toate'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: sportOptions().map((sport) {
                    final bool isSelected = _selectedSports.contains(sport['id']);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: Text(sport['label']!),
                        selected: isSelected,
                        selectedColor: AppColors.accent,
                        labelStyle: TextStyle(color: isSelected ? AppColors.onAccent : AppColors.text),
                        backgroundColor: AppColors.card2,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedSports.add(sport['id']!);
                            } else {
                              _selectedSports.remove(sport['id']);
                            }
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
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
              if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: AppColors.accent));

              final docs = snapshot.data!.docs;
              
              // Filtrare locala
              final filtered = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                
                if (data['visibility'] == 'private') return false;
                if (data['status'] == 'matched' || data['status'] == 'completed' || data['status'] == 'cancelled') return false;

                // Verificare trecut
                try {
                  final dateStr = data['date'] as String;
                  final startHour = hourValue(data['startHour']);
                  final matchStart = dateAtHour(dateStr, startHour);
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

                // Filtru Sport
                if (_selectedSports.isNotEmpty) {
                  final String? matchSport = data['sport'] as String?;
                  if (matchSport == null || !_selectedSports.contains(matchSport)) {
                    // Meciurile vechi nu au 'sport', deci le consideram 'ping_pong' by default
                    if (!(_selectedSports.contains('ping_pong') && matchSport == null)) {
                      return false;
                    }
                  }
                }

                return true;
              }).toList();

              if (filtered.isEmpty) {
                return Center(child: Text('Nu am găsit meciuri cu aceste filtre.', style: TextStyle(color: AppColors.muted)));
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
                  final bool requestSent = currentUser != null && List<dynamic>.from(data['joinRequestUids'] ?? []).contains(currentUser.uid);
                  
                  return Card(
                    color: AppColors.card,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.card2,
                                backgroundImage: data['hostAvatarUrl'] != null && data['hostAvatarUrl'].toString().isNotEmpty
                                    ? NetworkImage(data['hostAvatarUrl'])
                                    : null,
                                child: data['hostAvatarUrl'] == null || data['hostAvatarUrl'].toString().isEmpty
                                    ? Text(data['hostUsername']?.substring(0, 1).toUpperCase() ?? 'U', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold))
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(data['hostUsername'] ?? 'Unknown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.text)),
                                    Text('Nivel: ${data['hostLevel'] ?? 'Necunoscut'}', style: TextStyle(color: AppColors.accent.withValues(alpha: 0.8), fontSize: 12)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isMatched ? Colors.grey.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isMatched ? AppColors.muted : Colors.green),
                                ),
                                child: Text(isMatched ? 'MATCHED' : 'OPEN', style: TextStyle(color: isMatched ? AppColors.muted : Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                              )
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 16, color: AppColors.muted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${data['locationName']} (${data['city']}) • ${data['sport'] != null ? data['sport'].toString().toUpperCase() : 'PING PONG'}',
                                  style: TextStyle(color: AppColors.text),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 16, color: AppColors.muted),
                              const SizedBox(width: 8),
                              Text('${data['date']}', style: TextStyle(color: AppColors.text)),
                              const SizedBox(width: 16),
                              Icon(Icons.access_time, size: 16, color: AppColors.muted),
                              const SizedBox(width: 8),
                              Text('${formatHour(data['startHour'])} - ${formatHour(data['endHour'])}', style: TextStyle(color: AppColors.text)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Divider(color: AppColors.muted),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(data['paymentMethod'] ?? '', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                  Text(data['paymentSplit'] ?? '', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                  const SizedBox(height: 4),
                                  Text('${joinedUids.length} / $maxPlayers Jucători', style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              ElevatedButton(
                                onPressed: (isMyMatch || isMatched || requestSent) ? null : () => _joinMatch(docId, data),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  disabledBackgroundColor: AppColors.border,
                                  disabledForegroundColor: AppColors.text54,
                                ),
                                child: Text(isMyMatch ? 'Meciul tău' : (isMatched ? 'Rezervat' : (requestSent ? tr('n.request_sent') : (data['requireApproval'] == true ? tr('n.request_join') : 'Joacă cu ei!')))),
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
