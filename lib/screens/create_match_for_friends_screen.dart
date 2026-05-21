import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../data/mock_locations.dart';
import 'payment_screen.dart';
import '../utils/level_utils.dart';

class CreateMatchForFriendsScreen extends StatefulWidget {
  const CreateMatchForFriendsScreen({super.key});

  @override
  State<CreateMatchForFriendsScreen> createState() => _CreateMatchForFriendsScreenState();
}

class _CreateMatchForFriendsScreenState extends State<CreateMatchForFriendsScreen> {
  int _currentStep = 0;
  bool _isLoading = false;

  final _currentUser = FirebaseAuth.instance.currentUser;

  // Step 1: Locatie
  String? _selectedCity;
  PingPongLocation? _selectedLocation;
  int _maxPlayers = 2;

  // Step 2: Data, Ora si Masa
  DateTime _selectedDate = DateTime.now();
  int? _startHour;
  int? _endHour;
  List<int> _selectedHours = [];
  int? _selectedTable;
  List<int> _reservedTables = [];

  // Step 3: Invita Prieteni
  final List<String> _invitedFriendUids = [];
  final List<Map<String, dynamic>> _myFriends = [];
  bool _friendsLoading = true;

  // Step 4: Plata
  String _paymentMethod = 'Cash la locație';
  String _paymentSplit = 'Splituiește nota';

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    if (_currentUser == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('friendships')
          .where('uids', arrayContains: _currentUser.uid)
          .get();

      final List<Map<String, dynamic>> loadedFriends = [];
      for (var doc in snap.docs) {
        final data = doc.data();
        final List<dynamic> uids = data['uids'] ?? [];
        final List<dynamic> usernames = data['usernames'] ?? [];
        final List<dynamic> avatars = data['avatars'] ?? [];

        int otherIdx = uids.indexOf(_currentUser.uid) == 0 ? 1 : 0;
        if (uids.length >= 2) {
          loadedFriends.add({
            'uid': uids[otherIdx],
            'username': usernames[otherIdx],
            'avatarUrl': avatars[otherIdx],
          });
        }
      }

      setState(() {
        _myFriends.addAll(loadedFriends);
        _friendsLoading = false;
      });
    } catch (e) {
      debugPrint('Eroare la incarcarea prietenilor: $e');
      setState(() => _friendsLoading = false);
    }
  }

  // --- Helpers ---
  List<PingPongLocation> get _filteredLocations {
    if (_selectedCity == null) return [];
    return mockLocations.where((loc) => loc.city == _selectedCity).toList();
  }

  List<int> get _availableHours {
    if (_selectedLocation == null) return [];
    List<int> hours = [];
    final now = DateTime.now();
    bool isToday = _selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day;
    int minHour = (now.minute == 0) ? now.hour : now.hour + 1;

    for (int i = _selectedLocation!.openHour; i < _selectedLocation!.closeHour; i++) {
      if (isToday && i < minHour) continue;
      hours.add(i);
    }
    return hours;
  }

  Future<void> _checkTableAvailability() async {
    if (_selectedLocation == null || _startHour == null || _endHour == null) return;
    setState(() => _isLoading = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final query = await FirebaseFirestore.instance
          .collection('matches')
          .where('locationId', isEqualTo: _selectedLocation!.id)
          .where('date', isEqualTo: dateStr)
          .get();

      List<int> reserved = [];
      for (var doc in query.docs) {
        final data = doc.data();
        final int matchStart = data['startHour'] ?? 0;
        final int matchEnd = data['endHour'] ?? 0;
        final int tableId = data['tableId'] ?? 0;

        if (_startHour! < matchEnd && matchStart < _endHour!) {
          reserved.add(tableId);
        }
      }

      setState(() {
        _reservedTables = reserved;
        if (_selectedTable != null && reserved.contains(_selectedTable)) {
          _selectedTable = null;
        }
      });
    } catch (e) {
      debugPrint('Eroare verificare: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createMatch() async {
    if (_currentUser == null) return;

    setState(() => _isLoading = true);
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUser.uid).get();
      final userData = userDoc.data() ?? {};
      final username = userData['username'] ?? 'Jucător';
      final avatarUrl = userData['avatarUrl'];
      final rating = userData['rating'] ?? 0;
      final levelName = LevelUtils.getLevelDetails(rating)['levelName'];

      final Map<String, dynamic> hostPlayer = {
        'uid': _currentUser.uid,
        'username': username,
        'avatarUrl': avatarUrl,
        'rating': rating,
        'level': levelName,
        'role': 'host'
      };

      // Create the match document
      final matchDocRef = await FirebaseFirestore.instance.collection('matches').add({
        'hostUid': _currentUser.uid,
        'hostUsername': username,
        'hostAvatarUrl': avatarUrl,
        'hostRating': rating,
        'hostLevel': levelName,
        'joinedPlayers': [hostPlayer],
        'joinedUids': [_currentUser.uid],
        'invitedUids': _invitedFriendUids, // save invited friend list
        'maxPlayers': _maxPlayers,
        'visibility': 'private', // private visibility for play with a friend
        'city': _selectedCity,
        'locationId': _selectedLocation!.id,
        'locationName': _selectedLocation!.name,
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'startHour': _startHour,
        'endHour': _endHour,
        'tableId': _selectedTable,
        'paymentMethod': _paymentMethod,
        'paymentSplit': _paymentSplit,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Dispatch invitations to each invited friend in a batch
      if (_invitedFriendUids.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (var friendUid in _invitedFriendUids) {
          final friendData = _myFriends.firstWhere((f) => f['uid'] == friendUid);
          final newNotificationRef = FirebaseFirestore.instance.collection('notifications').doc();
          batch.set(newNotificationRef, {
            'toUid': friendUid,
            'fromUid': _currentUser.uid,
            'fromUsername': username,
            'fromAvatarUrl': avatarUrl,
            'title': 'Invitație la meci',
            'body': '$username te-a invitat la o partidă de Ping Pong la ${_selectedLocation!.name} pe data de ${DateFormat('dd MMM').format(_selectedDate)}.',
            'type': 'match_invite',
            'status': 'pending',
            'matchId': matchDocRef.id,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meci privat creat cu succes și invitațiile au fost trimise!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context); // Go back to Friends Screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Creează Meci Privat'),
        backgroundColor: const Color(0xFF131A2A),
        elevation: 0,
      ),
      body: Stepper(
        type: StepperType.vertical,
        physics: const BouncingScrollPhysics(),
        currentStep: _currentStep,
        onStepContinue: () async {
          if (_currentStep == 0) {
            if (_selectedCity == null || _selectedLocation == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alege orașul și locația.'), backgroundColor: Colors.redAccent));
              return;
            }
          } else if (_currentStep == 1) {
            if (_startHour == null || _endHour == null || _selectedTable == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alege orele și o masă liberă.'), backgroundColor: Colors.redAccent));
              return;
            }
          } else if (_currentStep == 4) {
            // Step 4 is Rezumat/Save
            if (_paymentMethod.contains('Card')) {
              int hours = (_endHour ?? 0) - (_startHour ?? 0);
              double amount = hours * 30.0;
              if (_paymentSplit == 'Splituiește nota') amount = amount / 2;

              final paymentSuccess = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PaymentScreen(amount: amount)),
              );

              if (paymentSuccess == true) {
                _createMatch();
              }
            } else {
              _createMatch();
            }
            return;
          }

          setState(() => _currentStep += 1);
          if (_currentStep == 1) _checkTableAvailability();
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep -= 1);
          }
        },
        controlsBuilder: (context, details) {
          final isLastStep = _currentStep == 4;
          return Padding(
            padding: const EdgeInsets.only(top: 24.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : details.onStepContinue,
                    child: _isLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(isLastStep ? 'TRIMITE INVITAȚIILE' : 'CONTINUĂ'),
                  ),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: details.onStepCancel,
                      child: const Text('ÎNAPOI'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          // STEP 0: Unde joci?
          Step(
            title: const Text('Unde joci?'),
            subtitle: const Text('Oraș, locație și format'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedCity,
                  decoration: const InputDecoration(labelText: 'Oraș', prefixIcon: Icon(Icons.location_city)),
                  items: romanianCities.map((city) => DropdownMenuItem(value: city, child: Text(city))).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedCity = val;
                      _selectedLocation = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PingPongLocation>(
                  value: _selectedLocation,
                  decoration: const InputDecoration(labelText: 'Sală Ping Pong', prefixIcon: Icon(Icons.sports_tennis)),
                  items: _filteredLocations.map((loc) => DropdownMenuItem(value: loc, child: Text(loc.name))).toList(),
                  onChanged: _selectedCity == null ? null : (val) {
                    setState(() {
                      _selectedLocation = val;
                      _startHour = null;
                      _endHour = null;
                      _selectedHours.clear();
                      _selectedTable = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _maxPlayers,
                  decoration: const InputDecoration(labelText: 'Format Meci', prefixIcon: Icon(Icons.people)),
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('1v1 (2 Jucători)')),
                    DropdownMenuItem(value: 4, child: Text('2v2 (4 Jucători)')),
                  ],
                  onChanged: (val) => setState(() => _maxPlayers = val ?? 2),
                ),
              ],
            ),
          ),

          // STEP 1: Când și la ce masă?
          Step(
            title: const Text('Când și la ce masă?'),
            subtitle: const Text('Data, orele și masa'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: _selectedLocation == null
                ? const Text('Te rugăm să alegi o locație la pasul anterior.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Data rezervării', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 30)),
                            );
                            if (date != null) {
                              setState(() {
                                _selectedDate = date;
                                _selectedHours.clear();
                                _startHour = null;
                                _endHour = null;
                                _selectedTable = null;
                              });
                              _checkTableAvailability();
                            }
                          },
                          icon: const Icon(Icons.calendar_month, color: Color(0xFF00E5FF)),
                          label: Text(
                            DateFormat('dd MMM yyyy').format(_selectedDate),
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                            side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.5)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text('Alege orele', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableHours.map((h) {
                          final isSelected = _selectedHours.contains(h);
                          return ChoiceChip(
                            label: Text('$h:00'),
                            selected: isSelected,
                            selectedColor: const Color(0xFF00E5FF),
                            labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  if (_selectedHours.isEmpty) {
                                    _selectedHours.add(h);
                                  } else {
                                    if (h == _selectedHours.first - 1 || h == _selectedHours.last + 1) {
                                      _selectedHours.add(h);
                                      _selectedHours.sort();
                                    } else {
                                      _selectedHours = [h];
                                    }
                                  }
                                } else {
                                  if (h == _selectedHours.first || h == _selectedHours.last) {
                                    _selectedHours.remove(h);
                                  } else {
                                    _selectedHours.clear();
                                  }
                                }

                                if (_selectedHours.isNotEmpty) {
                                  _startHour = _selectedHours.first;
                                  _endHour = _selectedHours.last + 1;
                                } else {
                                  _startHour = null;
                                  _endHour = null;
                                }
                                _selectedTable = null;
                              });
                              if (_selectedHours.isNotEmpty) _checkTableAvailability();
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 32),
                      const Text('Disponibilitate mese', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 12),
                      if (_isLoading) const Center(child: CircularProgressIndicator())
                      else if (_startHour == null || _endHour == null)
                        const Center(child: Text('Selectează intervalul orar mai întâi.', style: TextStyle(color: Colors.grey)))
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.2,
                          ),
                          itemCount: _selectedLocation!.numTables,
                          itemBuilder: (context, index) {
                            final tableId = index + 1;
                            final isReserved = _reservedTables.contains(tableId);
                            final isSelected = _selectedTable == tableId;

                            return GestureDetector(
                              onTap: isReserved ? null : () => setState(() => _selectedTable = tableId),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isReserved
                                      ? Colors.red.withOpacity(0.15)
                                      : (isSelected ? const Color(0xFF00E5FF).withOpacity(0.2) : const Color(0xFF1E293B)),
                                  border: Border.all(
                                    color: isReserved ? Colors.redAccent : (isSelected ? const Color(0xFF00E5FF) : Colors.grey[800]!),
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.table_restaurant, size: 18, color: isReserved ? Colors.redAccent : (isSelected ? const Color(0xFF00E5FF) : Colors.grey)),
                                      const SizedBox(height: 4),
                                      Text('Masa $tableId', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isReserved ? Colors.redAccent : Colors.white)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
          ),

          // STEP 2: Invită Prieteni
          Step(
            title: const Text('Invită Prieteni'),
            subtitle: const Text('Alege pe cine chemi la masă'),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
            content: _friendsLoading
                ? const Center(child: CircularProgressIndicator())
                : _myFriends.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Text('Nu ai niciun prieten în listă pe care să îl poți invita. Poți continua fără invitații.', style: TextStyle(color: Colors.grey)),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Bifează prietenii pe care vrei să îi inviți:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          const SizedBox(height: 12),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _myFriends.length,
                            itemBuilder: (context, idx) {
                              final friend = _myFriends[idx];
                              final uid = friend['uid'] as String;
                              final name = friend['username'] as String;
                              final avatar = friend['avatarUrl'] as String;
                              final isSelected = _invitedFriendUids.contains(uid);

                              return CheckboxListTile(
                                activeColor: const Color(0xFF00E5FF),
                                checkColor: Colors.black,
                                title: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: const Color(0xFF1E293B),
                                      backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                      child: avatar.isEmpty
                                          ? Text(name.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold))
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(name, style: const TextStyle(color: Colors.white)),
                                  ],
                                ),
                                value: isSelected,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _invitedFriendUids.add(uid);
                                    } else {
                                      _invitedFriendUids.remove(uid);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ],
                      ),
          ),

          // STEP 3: Detalii Plată
          Step(
            title: const Text('Cum dorești să plătești?'),
            subtitle: const Text('Metodă plată și împărțire'),
            isActive: _currentStep >= 3,
            state: _currentStep > 3 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Metoda de plată', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                RadioListTile(
                  title: const Text('Cash la locație'),
                  activeColor: const Color(0xFF00E5FF),
                  value: 'Cash la locație',
                  groupValue: _paymentMethod,
                  onChanged: (val) => setState(() => _paymentMethod = val.toString()),
                ),
                RadioListTile(
                  title: const Text('Card în aplicație (Salvat ca preferință)'),
                  activeColor: const Color(0xFF00E5FF),
                  value: 'Card în aplicație',
                  groupValue: _paymentMethod,
                  onChanged: (val) => setState(() => _paymentMethod = val.toString()),
                ),
                const Divider(),
                const Text('Împărțirea notei', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                RadioListTile(
                  title: const Text('Splituiește nota'),
                  activeColor: const Color(0xFF00E5FF),
                  value: 'Splituiește nota',
                  groupValue: _paymentSplit,
                  onChanged: (val) => setState(() => _paymentSplit = val.toString()),
                ),
                RadioListTile(
                  title: const Text('Achită host-ul integral'),
                  activeColor: const Color(0xFF00E5FF),
                  value: 'Achită host-ul integral',
                  groupValue: _paymentSplit,
                  onChanged: (val) => setState(() => _paymentSplit = val.toString()),
                ),
              ],
            ),
          ),

          // STEP 4: Rezumat
          Step(
            title: const Text('Rezumat Meci'),
            subtitle: const Text('Verifică înainte de a rezerva'),
            isActive: _currentStep >= 4,
            content: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF131A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow(Icons.location_on, 'Locație', '${_selectedLocation?.name ?? '-'} (${_selectedCity ?? '-'})'),
                  _summaryRow(Icons.calendar_today, 'Data', DateFormat('dd MMM yyyy').format(_selectedDate)),
                  _summaryRow(Icons.access_time, 'Interval Orar', '${_startHour ?? '-'}:00 - ${_endHour ?? '-'}:00'),
                  _summaryRow(Icons.table_restaurant, 'Masa rezervată', _selectedTable != null ? 'Masa $_selectedTable' : '-'),
                  _summaryRow(Icons.people, 'Invitați', _invitedFriendUids.isEmpty
                      ? 'Niciun prieten selectat'
                      : '${_invitedFriendUids.length} prieteni vor primi invitație'),
                  const Divider(color: Colors.grey),
                  _summaryRow(Icons.payment, 'Plată', _paymentMethod),
                  _summaryRow(Icons.receipt_long, 'Nota de plată', _paymentSplit),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF00E5FF), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
