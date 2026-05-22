import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../data/mock_locations.dart';
import 'payment_screen.dart';
import '../utils/level_utils.dart';
import '../widgets/city_selector.dart';

class CreateMatchTab extends StatefulWidget {
  const CreateMatchTab({super.key});

  @override
  State<CreateMatchTab> createState() => _CreateMatchTabState();
}

class _CreateMatchTabState extends State<CreateMatchTab> {
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isLoadingLocs = false;

  // Step 1: Locatie
  String? _selectedCity;
  PingPongLocation? _selectedLocation;
  int _maxPlayers = 2;
  String _visibility = 'Public';
  String _matchType = 'Competitiv';

  // Step 2: Data, Ora si Masa
  DateTime _selectedDate = DateTime.now();
  int? _startHour;
  int? _endHour;
  List<int> _selectedHours = [];
  int? _selectedTable;
  List<int> _reservedTables = [];
  bool _isDayBlockedFlag = false;
  String? _overlappingTournament;

  // Step 3: Plata
  String _paymentMethod = 'Cash la locație';

  List<PingPongLocation> _allLocations = List.from(mockLocations);

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
          pricePerHour: (data['pricePerHour'] as num?)?.toDouble() ?? 20.0,
          pricePerHourText: data['pricePerHourText'] as String? ?? '20 RON/oră',
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
      debugPrint('Eroare incarcare sali din Firestore: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocs = false);
      }
    }
  }

  // --- Step 1 Helpers ---
  List<String> get _cityOptions {
    final Set<String> cities = {};
    for (var loc in _allLocations) {
      if (loc.city.isNotEmpty) {
        cities.add(loc.city.trim());
      }
    }
    cities.addAll(romanianCities);
    final sorted = cities.toList()..sort();
    return sorted;
  }

  List<PingPongLocation> get _filteredLocations {
    if (_selectedCity == null) return [];
    return _allLocations
        .where((loc) => loc.city.trim().toLowerCase() == _selectedCity!.trim().toLowerCase())
        .toList();
  }

  // --- Step 2 Helpers ---
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
      
      // 1. Verificăm dacă întreaga zi e blocată
      bool isDayBlocked = false;
      final venueQuery = await FirebaseFirestore.instance
          .collection('venues')
          .where('venueName', isEqualTo: _selectedLocation!.name)
          .get();

      if (venueQuery.docs.isNotEmpty) {
        final data = venueQuery.docs.first.data();
        final blockedDates = List<dynamic>.from(data['blockedDates'] ?? []);
        if (blockedDates.contains(dateStr)) {
          isDayBlocked = true;
        }
      }

      // 2. Verificăm turneele active care se suprapun
      String? overlappingTournamentTitle;
      final tourQuery = await FirebaseFirestore.instance
          .collection('tournaments')
          .where('venueName', isEqualTo: _selectedLocation!.name)
          .where('date', isEqualTo: dateStr)
          .get();

      for (var doc in tourQuery.docs) {
        final data = doc.data();
        final String status = data['status'] ?? 'open';
        if (status != 'open' && status != 'active') continue;

        final String tourTime = data['time'] ?? '';
        final String tourEndTime = data['endTime'] ?? '';
        final String tourTitle = data['title'] ?? 'Turneu';

        final int tourStart = _parseTimeStr(tourTime, 0);
        final int tourEnd = _parseTimeStr(tourEndTime, tourStart + 3);

        if (_startHour! < tourEnd && tourStart < _endHour!) {
          overlappingTournamentTitle = tourTitle;
          break;
        }
      }

      // 3. Verificăm meciurile deja rezervate
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

        // Verifica suprapunere: [start, end)
        if (_startHour! < matchEnd && matchStart < _endHour!) {
          reserved.add(tableId);
        }
      }

      setState(() {
        _reservedTables = reserved;
        _isDayBlockedFlag = isDayBlocked;
        _overlappingTournament = overlappingTournamentTitle;
        if (_selectedTable != null && (reserved.contains(_selectedTable) || isDayBlocked || overlappingTournamentTitle != null)) {
          _selectedTable = null; // deselect if it became reserved or blocked
        }
      });
    } catch (e) {
      debugPrint('Eroare la verificarea disponibilitatii: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _getBlockedReason() async {
    if (_selectedLocation == null) return null;
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // 1. Check if the venue has manually blocked the entire day
      final venueQuery = await FirebaseFirestore.instance
          .collection('venues')
          .where('venueName', isEqualTo: _selectedLocation!.name)
          .get();

      if (venueQuery.docs.isNotEmpty) {
        final data = venueQuery.docs.first.data();
        final blockedDates = List<dynamic>.from(data['blockedDates'] ?? []);
        if (blockedDates.contains(dateStr)) {
          return 'day';
        }
      }

      // 2. Check if there is an overlapping active tournament
      if (_startHour != null && _endHour != null) {
        final tourQuery = await FirebaseFirestore.instance
            .collection('tournaments')
            .where('venueName', isEqualTo: _selectedLocation!.name)
            .where('date', isEqualTo: dateStr)
            .get();

        for (var doc in tourQuery.docs) {
          final data = doc.data();
          final String status = data['status'] ?? 'open';
          if (status != 'open' && status != 'active') continue;

          final String tourTime = data['time'] ?? '';
          final String tourEndTime = data['endTime'] ?? '';
          final String tourTitle = data['title'] ?? 'Turneu';

          final int tourStart = _parseTimeStr(tourTime, 0);
          final int tourEnd = _parseTimeStr(tourEndTime, tourStart + 3); // Fallback: 3 hours for legacy tournaments

          // Verify time span overlap: matchStart < tourEnd && tourStart < matchEnd
          if (_startHour! < tourEnd && tourStart < _endHour!) {
            final String timeDisplay = tourEndTime.isNotEmpty ? '$tourTime - $tourEndTime' : '$tourTime (aprox. 3 ore)';
            return 'tournament|$tourTitle|$timeDisplay';
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking blocked reason: $e');
    }
    return null;
  }

  int _parseTimeStr(String timeStr, int fallbackHour) {
    if (timeStr.isEmpty) return fallbackHour;
    try {
      final parts = timeStr.split(':');
      if (parts.isNotEmpty) {
        return int.parse(parts[0]);
      }
    } catch (e) {
      debugPrint('Error parsing time string $timeStr: $e');
    }
    return fallbackHour;
  }

  // --- Step 4 (Save) ---
  Future<void> _createMatch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = userDoc.data() ?? {};
      final username = data['username'] ?? 'Jucător necunoscut';
      final avatarUrl = data['avatarUrl'];
      final rating = data['rating'] ?? 0;
      
      // Calculăm level-ul curent pentru a-l salva pe meci
      final int pointsPerLevel = 250;
      final int levelIndex = (rating < 0 ? 0 : rating) ~/ pointsPerLevel;
      final List<String> tiers = ['Iron', 'Bronze', 'Silver', 'Gold', 'Platinum'];
      final List<String> subLevels = ['I', 'II', 'III', 'IV'];
      
      String levelName = 'Diamond';
      if (levelIndex < tiers.length * subLevels.length) {
        int tierIndex = levelIndex ~/ subLevels.length;
        int subLevelIndex = levelIndex % subLevels.length;
        levelName = '${tiers[tierIndex]} ${subLevels[subLevelIndex]}';
      }

      final Map<String, dynamic> hostData = {
        'uid': user.uid,
        'username': username,
        'avatarUrl': avatarUrl,
        'rating': rating,
        'level': levelName,
        'role': 'host'
      };

      await FirebaseFirestore.instance.collection('matches').add({
        'hostUid': user.uid,
        'hostUsername': username,
        'hostAvatarUrl': avatarUrl,
        'hostRating': rating,
        'hostLevel': levelName,
        'joinedPlayers': [hostData],
        'joinedUids': [user.uid],
        'maxPlayers': _maxPlayers,
        'visibility': _visibility.toLowerCase(),
        'isFriendly': _matchType == 'Amical',
        'city': _selectedCity,
        'locationId': _selectedLocation!.id,
        'locationName': _selectedLocation!.name,
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'startHour': _startHour,
        'endHour': _endHour,
        'tableId': _selectedTable,
        'paymentMethod': _paymentMethod,
        'paymentSplit': 'Achitat integral',
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meci creat cu succes!'), backgroundColor: Colors.green),
        );
        // Reset form
        setState(() {
          _currentStep = 0;
          _selectedCity = null;
          _selectedLocation = null;
          _startHour = null;
          _endHour = null;
          _selectedHours.clear();
          _selectedTable = null;
          _maxPlayers = 2;
          _visibility = 'Public';
          _matchType = 'Competitiv';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la creare: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alege intervalul orar și o masă liberă.'), backgroundColor: Colors.redAccent));
              return;
            }
            // Mesele sunt deja dezactivate în UI dacă există un turneu sau un blocaj,
            // astfel încât utilizatorul nu poate selecta o masă indisponibilă și nu poate continua.
          } else if (_currentStep == 2) {
            if (_paymentMethod.contains('Card')) {
              double amount = LevelUtils.calculateTotalBookingPrice(
                _selectedLocation!.pricePerHourText,
                _startHour!,
                _endHour!,
              );

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

          if (_currentStep < 3) {
            setState(() => _currentStep += 1);
            if (_currentStep == 1) _checkTableAvailability();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep -= 1);
          }
        },
        controlsBuilder: (context, details) {
          final isLastStep = _currentStep == 3;
          return Padding(
            padding: const EdgeInsets.only(top: 24.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : details.onStepContinue,
                    child: _isLoading 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(isLastStep ? 'CONFIRMĂ REZERVAREA' : 'CONTINUĂ'),
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
          Step(
            title: const Text('Unde joci?'),
            subtitle: const Text('Oraș și Locație'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CitySelectorField(
                  selectedCity: _selectedCity,
                  cityOptions: _cityOptions,
                  onCitySelected: (val) {
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
                const SizedBox(height: 24),
                const Text('Setări Meci', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _maxPlayers,
                        decoration: const InputDecoration(labelText: 'Format', prefixIcon: Icon(Icons.people)),
                        items: const [
                          DropdownMenuItem(value: 2, child: Text('1v1 (2 Jucători)')),
                          DropdownMenuItem(value: 4, child: Text('2v2 (4 Jucători)')),
                        ],
                        onChanged: (val) => setState(() => _maxPlayers = val ?? 2),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _visibility,
                        decoration: const InputDecoration(labelText: 'Vizibilitate', prefixIcon: Icon(Icons.visibility)),
                        items: const [
                          DropdownMenuItem(value: 'Public', child: Text('Public')),
                          DropdownMenuItem(value: 'Privat', child: Text('Privat')),
                        ],
                        onChanged: (val) => setState(() => _visibility = val ?? 'Public'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _matchType,
                  decoration: const InputDecoration(labelText: 'Tip Meci', prefixIcon: Icon(Icons.emoji_events_outlined)),
                  items: const [
                    DropdownMenuItem(value: 'Competitiv', child: Text('Competitiv (Cu puncte)')),
                    DropdownMenuItem(value: 'Amical', child: Text('Amical (Fără puncte)')),
                  ],
                  onChanged: (val) => setState(() => _matchType = val ?? 'Competitiv'),
                ),
              ],
            ),
          ),
          Step(
            title: const Text('Când și la ce masă?'),
            subtitle: const Text('Data, Orele și Harta Meselor'),
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
                            alignment: Alignment.centerLeft,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text('Alege intervalul orar (poți selecta mai multe ore consecutive)', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                      const Text('Planul Meselor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                      const Text('Alege o masă liberă (disponibilă)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 16),
                      if (_isLoading) const Center(child: CircularProgressIndicator())
                      else if (_startHour == null || _endHour == null)
                        const Center(child: Text('Alege intervalul orar mai întâi', style: TextStyle(color: Colors.grey)))
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131A2A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[800]!),
                          ),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.2,
                            ),
                            itemCount: _selectedLocation!.numTables,
                            itemBuilder: (context, index) {
                              final tableId = index + 1;
                              final isReserved = _reservedTables.contains(tableId);
                              final isTableBlocked = isReserved || _isDayBlockedFlag || _overlappingTournament != null;
                              final isSelected = _selectedTable == tableId;

                              String statusText = 'Liberă';
                              if (_isDayBlockedFlag) {
                                statusText = 'Zi închisă';
                              } else if (_overlappingTournament != null) {
                                statusText = 'Turneu';
                              } else if (isReserved) {
                                statusText = 'Ocupată';
                              }

                              return GestureDetector(
                                onTap: isTableBlocked ? null : () {
                                  setState(() => _selectedTable = tableId);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: isTableBlocked ? Colors.red.withOpacity(0.15) : (isSelected ? const Color(0xFF00E5FF).withOpacity(0.3) : const Color(0xFF1E293B)),
                                    border: Border.all(
                                      color: isTableBlocked ? Colors.redAccent : (isSelected ? const Color(0xFF00E5FF) : Colors.grey[800]!),
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.table_restaurant, size: 20, color: isTableBlocked ? Colors.redAccent : (isSelected ? const Color(0xFF00E5FF) : Colors.grey)),
                                        const SizedBox(height: 4),
                                        Text('Masa $tableId', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isTableBlocked ? Colors.redAccent : Colors.white)),
                                        Text(statusText, style: TextStyle(fontSize: 10, color: isTableBlocked ? Colors.redAccent : Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          Step(
            title: const Text('Cum dorești să plătești?'),
            subtitle: const Text('Metodă plată'),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (context) {
                    double totalAmount = 0.0;
                    String priceInfo = 'Tarif pe oră: ${_selectedLocation?.pricePerHourText ?? "20 RON/oră"}';
                    if (_selectedLocation != null && _startHour != null && _endHour != null) {
                      totalAmount = LevelUtils.calculateTotalBookingPrice(
                        _selectedLocation!.pricePerHourText,
                        _startHour!,
                        _endHour!,
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFF00E5FF), size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$priceInfo\nTotal de plată: ${totalAmount.toStringAsFixed(0)} lei (achitat integral de Host)',
                              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                ),
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
              ],
            ),
          ),
          Step(
            title: const Text('Rezumat'),
            subtitle: const Text('Verifică înainte de creare'),
            isActive: _currentStep >= 3,
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
                  _summaryRow(Icons.access_time, 'Interval Orare', '${_startHour ?? '-'}:00 - ${_endHour ?? '-'}:00 (${((_endHour ?? 0) - (_startHour ?? 0))} ore)'),
                  _summaryRow(Icons.table_restaurant, 'Masa', _selectedTable != null ? 'Masa $_selectedTable' : '-'),
                  const Divider(color: Colors.grey),
                  _summaryRow(Icons.emoji_events, 'Tip Meci', _matchType),
                  _summaryRow(Icons.payment, 'Plată', _paymentMethod),
                  _summaryRow(
                    Icons.monetization_on,
                    'Cost Total',
                    '${_selectedLocation != null && _startHour != null && _endHour != null
                        ? LevelUtils.calculateTotalBookingPrice(
                            _selectedLocation!.pricePerHourText,
                            _startHour!,
                            _endHour!,
                          ).toStringAsFixed(0)
                        : ((_endHour ?? 0) - (_startHour ?? 0)) * 20} RON',
                  ),
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
          Icon(icon, color: const Color(0xFF00E5FF), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
