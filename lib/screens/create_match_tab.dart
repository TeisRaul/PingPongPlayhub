import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../data/mock_locations.dart';
import 'payment_screen.dart';

class CreateMatchTab extends StatefulWidget {
  const CreateMatchTab({super.key});

  @override
  State<CreateMatchTab> createState() => _CreateMatchTabState();
}

class _CreateMatchTabState extends State<CreateMatchTab> {
  int _currentStep = 0;
  bool _isLoading = false;

  // Step 1: Locatie
  String? _selectedCity;
  PingPongLocation? _selectedLocation;
  int _maxPlayers = 2;
  String _visibility = 'Public';

  // Step 2: Data, Ora si Masa
  DateTime _selectedDate = DateTime.now();
  int? _startHour;
  int? _endHour;
  List<int> _selectedHours = [];
  int? _selectedTable;
  List<int> _reservedTables = [];

  // Step 3: Plata
  String _paymentMethod = 'Cash la locație';
  String _paymentSplit = 'Splituiește nota';

  // --- Step 1 Helpers ---
  List<PingPongLocation> get _filteredLocations {
    if (_selectedCity == null) return [];
    return mockLocations.where((loc) => loc.city == _selectedCity).toList();
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
        if (_selectedTable != null && reserved.contains(_selectedTable)) {
          _selectedTable = null; // deselect if it became reserved
        }
      });
    } catch (e) {
      debugPrint('Eroare la verificarea disponibilitatii: $e');
    } finally {
      setState(() => _isLoading = false);
    }
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
          } else if (_currentStep == 3) {
            if (_paymentMethod.contains('Card')) {
              int hours = (_endHour ?? 0) - (_startHour ?? 0);
              double amount = hours * 30.0; // Presupunem un cost de 30 RON pe oră
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
                      const Text('Alege o masă verde (disponibilă)', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                              final isSelected = _selectedTable == tableId;

                              return GestureDetector(
                                onTap: isReserved ? null : () {
                                  setState(() => _selectedTable = tableId);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: isReserved ? Colors.red.withOpacity(0.2) : (isSelected ? const Color(0xFF00E5FF).withOpacity(0.3) : const Color(0xFF1E293B)),
                                    border: Border.all(
                                      color: isReserved ? Colors.redAccent : (isSelected ? const Color(0xFF00E5FF) : Colors.grey[800]!),
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.table_restaurant, size: 20, color: isReserved ? Colors.redAccent : (isSelected ? const Color(0xFF00E5FF) : Colors.grey)),
                                        const SizedBox(height: 4),
                                        Text('Masa $tableId', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isReserved ? Colors.redAccent : Colors.white)),
                                        Text(isReserved ? 'Ocupată' : 'Liberă', style: TextStyle(fontSize: 10, color: isReserved ? Colors.redAccent : Colors.grey)),
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
            subtitle: const Text('Cash/Card și Detalii Note'),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
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
                  _summaryRow(Icons.payment, 'Plată', _paymentMethod),
                  _summaryRow(Icons.receipt_long, 'Nota', _paymentSplit),
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
