import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../data/mock_locations.dart';
import 'payment_screen.dart';
import '../utils/level_utils.dart';
import '../widgets/city_selector.dart';

class CreateMatchForFriendsScreen extends StatefulWidget {
  const CreateMatchForFriendsScreen({super.key});

  @override
  State<CreateMatchForFriendsScreen> createState() => _CreateMatchForFriendsScreenState();
}

class _CreateMatchForFriendsScreenState extends State<CreateMatchForFriendsScreen> {
  int _currentStep = 0;
  bool _isLoading = false;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  // Step 1: Locatie
  String? _selectedCity;
  PingPongLocation? _selectedLocation;
  String? _selectedTableType; // null = not chosen, 'indoor' or 'outdoor'
  int _maxPlayers = 2;
  String _matchType = 'Amical'; // Private matches default to Amical

  // Step 2: Data, Ora si Masa
  DateTime _selectedDate = DateTime.now();
  num? _startHour;
  num? _endHour;
  List<num> _selectedHours = [];
  int? _selectedTable;
  List<int> _reservedTables = [];
  bool _isDayBlockedFlag = false;
  String? _overlappingTournament;

  List<Map<String, dynamic>> _venueCustomTables = [];
  Map<String, dynamic>? _venueTrainingConfig;
  Map<String, dynamic>? _venueData;

  String _formatHour(num hour) {
    final int h = hour.toInt();
    final int m = ((hour - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  bool _isTrainingActiveForHour(num hour, Map<String, dynamic> config) {
    if (config['enabled'] == false) return false;
    final int weekday = _selectedDate.weekday; // 1 = Monday, 7 = Sunday
    final List<dynamic> days = config['weekdays'] ?? [];
    if (!days.contains(weekday)) return false;

    final int start = config['startHour'] ?? 17;
    final int end = config['endHour'] ?? 19;
    return hour >= start && hour < end;
  }

  bool _isTableReservedForTraining(Map<String, dynamic> table, Map<String, dynamic>? config) {
    if (table['type'] != 'training' || config == null) return false;
    if (_startHour == null || _endHour == null) return false;
    for (num hour = _startHour!; hour < _endHour!; hour += 0.5) {
      if (_isTrainingActiveForHour(hour, config)) {
        return true;
      }
    }
    return false;
  }

  // Step 3: Invita Prieteni
  final List<String> _invitedFriendUids = [];
  final List<Map<String, dynamic>> _myFriends = [];
  bool _friendsLoading = true;

  // Step 4: Plata
  String _paymentMethod = 'Cash la locație';
  bool _wantsInvoice = false;
  final _invoiceCompanyController = TextEditingController();
  final _invoiceCuiController = TextEditingController();
  final _invoiceRegController = TextEditingController();
  final _invoiceAddressController = TextEditingController();
  final _invoiceEmailController = TextEditingController();

  List<PingPongLocation> _allLocations = List.from(mockLocations);
  bool _isLoadingLocs = false;

  @override
  void dispose() {
    _invoiceCompanyController.dispose();
    _invoiceCuiController.dispose();
    _invoiceRegController.dispose();
    _invoiceAddressController.dispose();
    _invoiceEmailController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadFriends();
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

        final int indoorTables = data['indoorTables'] as int? ?? numTables;
        final int outdoorTables = data['outdoorTables'] as int? ?? 0;
        final bool allowHalfHour = data['allowHalfHour'] as bool? ?? false;

        fetched.add(PingPongLocation(
          id: id,
          city: city,
          name: name,
          openHour: openHour,
          closeHour: closeHour,
          numTables: numTables,
          indoorTables: indoorTables,
          outdoorTables: outdoorTables,
          pricePerHour: (data['pricePerHour'] as num?)?.toDouble() ?? 20.0,
          pricePerHourText: data['pricePerHourText'] as String? ?? '20 RON/oră',
          allowHalfHour: allowHalfHour,
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
      debugPrint('Eroare incarcare sali din Firestore in meci privat: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocs = false);
      }
    }
  }

  Future<void> _loadFriends() async {
    final user = _currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('friendships')
          .where('uids', arrayContains: user.uid)
          .get();

      final List<Map<String, dynamic>> loadedFriends = [];
      for (var doc in snap.docs) {
        final data = doc.data();
        final List<dynamic> uids = data['uids'] ?? [];
        final List<dynamic> usernames = data['usernames'] ?? [];
        final List<dynamic> avatars = data['avatars'] ?? [];

        int otherIdx = uids.indexOf(user.uid) == 0 ? 1 : 0;
        if (uids.length >= 2) {
          final String otherUid = uids[otherIdx];
          final String otherUsername = (usernames.length > otherIdx) ? usernames[otherIdx] : 'Utilizator';
          final String? otherAvatar = (avatars.length > otherIdx) ? avatars[otherIdx] : null;
          loadedFriends.add({
            'uid': otherUid,
            'username': otherUsername,
            'avatarUrl': otherAvatar,
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

  List<num> get _availableHours {
    if (_selectedLocation == null) return [];
    List<num> hours = [];
    final now = DateTime.now();
    bool isToday = _selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day;
    double minHour = now.hour + (now.minute >= 30 ? 1.0 : (now.minute > 0 ? 0.5 : 0.0));

    final double step = _selectedLocation!.allowHalfHour ? 0.5 : 1.0;

    for (double i = _selectedLocation!.openHour.toDouble(); i < _selectedLocation!.closeHour.toDouble(); i += step) {
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

      // 1. Verificăm dacă întreaga zi e blocată și preluăm planul personalizat de mese & configul de antrenament
      bool isDayBlocked = false;
      List<Map<String, dynamic>> customTables = [];
      Map<String, dynamic>? trainingConfig;

      Map<String, dynamic>? venueData;
      try {
        final venueDoc = await FirebaseFirestore.instance
            .collection('venues')
            .doc(_selectedLocation!.id)
            .get();
        if (venueDoc.exists) {
          venueData = venueDoc.data();
        }
      } catch (_) {}

      if (venueData == null) {
        // Fallback la căutare după nume în cazul locațiilor fictive / mock
        final venueQuery = await FirebaseFirestore.instance
            .collection('venues')
            .where('venueName', isEqualTo: _selectedLocation!.name)
            .get();
        if (venueQuery.docs.isNotEmpty) {
          venueData = venueQuery.docs.first.data();
        }
      }

      if (venueData != null) {
        final blockedDates = List<dynamic>.from(venueData['blockedDates'] ?? []);
        if (blockedDates.contains(dateStr)) {
          isDayBlocked = true;
        }
        if (venueData.containsKey('customTables')) {
          customTables = List<Map<String, dynamic>>.from(venueData['customTables'] ?? []);
        }
        if (venueData.containsKey('trainingConfig')) {
          trainingConfig = Map<String, dynamic>.from(venueData['trainingConfig'] ?? {});
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

        if (_startHour! < matchEnd && matchStart < _endHour!) {
          reserved.add(tableId);
        }
      }

      setState(() {
        _reservedTables = reserved;
        _isDayBlockedFlag = isDayBlocked;
        _overlappingTournament = overlappingTournamentTitle;
        _venueCustomTables = customTables;
        _venueTrainingConfig = trainingConfig;
        _venueData = venueData;

        if (_selectedTable != null) {
          bool stillAvailable = !reserved.contains(_selectedTable);
          if (stillAvailable && customTables.isNotEmpty) {
            final tbl = customTables.firstWhere((t) => t['tableId'] == _selectedTable, orElse: () => {});
            if (tbl.isNotEmpty && _isTableReservedForTraining(tbl, trainingConfig)) {
              stillAvailable = false;
            }
          }
          if (!stillAvailable || isDayBlocked || overlappingTournamentTitle != null) {
            _selectedTable = null; // deselect if blocked, reserved or in training
          }
        }
      });
    } catch (e) {
      debugPrint('Eroare verificare: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? _getTableAt(int x, int y, List<Map<String, dynamic>> tables) {
    for (var t in tables) {
      if (t['x'] == x && t['y'] == y) {
        return t;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _invoiceCompanyController.dispose();
    _invoiceCuiController.dispose();
    _invoiceRegController.dispose();
    _invoiceAddressController.dispose();
    _invoiceEmailController.dispose();
    super.dispose();
  }

  // --- Step 4 (Save) ---
  Future<void> _createMatch() async {
    final user = _currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final username = userData['username'] ?? 'Jucător';
      final avatarUrl = userData['avatarUrl'];
      final rating = userData['rating'] ?? 0;
      final levelName = LevelUtils.getLevelDetails(rating)['levelName'];

      final Map<String, dynamic> hostPlayer = {
        'uid': user.uid,
        'username': username,
        'avatarUrl': avatarUrl,
        'rating': rating,
        'level': levelName,
        'role': 'host'
      };

      double totalAmount = 0.0;
      if (_selectedLocation != null && _startHour != null && _endHour != null) {
        if (_venueData != null) {
          totalAmount = LevelUtils.calculateVenueBookingPrice(
            venueData: _venueData!,
            startHour: _startHour!,
            endHour: _endHour!,
          );
        } else {
          totalAmount = LevelUtils.calculateTotalBookingPrice(
            _selectedLocation!.pricePerHourText,
            _startHour!,
            _endHour!,
          );
        }
      }

      // Create the match document
      final matchData = {
        'hostUid': user.uid,
        'hostUsername': username,
        'hostAvatarUrl': avatarUrl,
        'hostRating': rating,
        'hostLevel': levelName,
        'joinedPlayers': [hostPlayer],
        'joinedUids': [user.uid],
        'invitedUids': _invitedFriendUids, // save invited friend list
        'maxPlayers': _maxPlayers,
        'visibility': 'private', // private visibility for play with a friend
        'isFriendly': _matchType == 'Amical',
        'city': _selectedCity,
        'locationId': _selectedLocation!.id,
        'locationName': _selectedLocation!.name,
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'startHour': _startHour,
        'endHour': _endHour,
        'tableId': _selectedTable,
        'tableType': _selectedTableType,
        'paymentMethod': _paymentMethod,
        'paymentSplit': 'Achitat integral',
        'paymentStatus': _paymentMethod.contains('Card') ? 'confirmed' : 'pending',
        'status': 'open',
        'price': totalAmount,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (_wantsInvoice) {
        matchData['invoiceData'] = {
          'companyName': _invoiceCompanyController.text.trim(),
          'cui': _invoiceCuiController.text.trim(),
          'regCom': _invoiceRegController.text.trim(),
          'address': _invoiceAddressController.text.trim(),
          'email': _invoiceEmailController.text.trim(),
        };
      }

      final matchDocRef = await FirebaseFirestore.instance.collection('matches').add(matchData);

      // Dispatch invitations to each invited friend in a batch
      if (_invitedFriendUids.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (var friendUid in _invitedFriendUids) {
          final newNotificationRef = FirebaseFirestore.instance.collection('notifications').doc();
          batch.set(newNotificationRef, {
            'toUid': friendUid,
            'fromUid': user.uid,
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
            if (_selectedTableType == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alege tipul mesei: Indoor sau Outdoor.'), backgroundColor: Colors.redAccent));
              return;
            }
          } else if (_currentStep == 1) {
            if (_startHour == null || _endHour == null || _selectedTable == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alege orele și o masă liberă.'), backgroundColor: Colors.redAccent));
              return;
            }
            // Mesele sunt deja dezactivate în UI dacă există un turneu sau un blocaj,
            // astfel încât utilizatorul nu poate selecta o masă indisponibilă și nu poate continua.
          } else if (_currentStep == 4) {
            // Step 4 is Rezumat/Save
            if (_paymentMethod.contains('Card')) {
              double amount = LevelUtils.calculateTotalBookingPrice(
                _selectedLocation?.pricePerHourText ?? '20 RON/oră',
                _startHour ?? 0,
                _endHour ?? 0,
              );

              final paymentSuccess = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PaymentScreen(
                  amount: amount,
                  venueId: _selectedLocation?.id ?? 'unknown',
                  destinationAccountId: _selectedLocation?.stripeAccountId,
                )),
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
                CitySelectorField(
                  selectedCity: _selectedCity,
                  cityOptions: _cityOptions,
                  onCitySelected: (val) {
                    setState(() {
                      _selectedCity = val;
                      _selectedLocation = null;
                      _selectedTableType = null;
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
                      _selectedTableType = null;
                      _startHour = null;
                      _endHour = null;
                      _selectedHours.clear();
                      _selectedTable = null;
                    });
                  },
                ),
                if (_selectedLocation != null) ...[
                  const SizedBox(height: 20),
                  const Text('Tip Masă', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    'Indoor: ${_selectedLocation!.indoorTables} mese  •  Outdoor: ${_selectedLocation!.outdoorTables} mese',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _selectedLocation!.indoorTables > 0
                              ? () => setState(() { _selectedTableType = 'indoor'; _selectedTable = null; })
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _selectedTableType == 'indoor' ? const Color(0xFF00E5FF).withValues(alpha: 0.2) : _selectedLocation!.indoorTables == 0 ? Colors.grey.withValues(alpha: 0.1) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _selectedTableType == 'indoor' ? const Color(0xFF00E5FF) : _selectedLocation!.indoorTables == 0 ? Colors.grey.withValues(alpha: 0.3) : Colors.grey[700]!, width: _selectedTableType == 'indoor' ? 2 : 1),
                            ),
                            child: Column(children: [
                              Icon(Icons.house_outlined, color: _selectedTableType == 'indoor' ? const Color(0xFF00E5FF) : _selectedLocation!.indoorTables == 0 ? Colors.grey[600] : Colors.white70, size: 28),
                              const SizedBox(height: 6),
                              Text('Indoor', style: TextStyle(fontWeight: FontWeight.bold, color: _selectedTableType == 'indoor' ? const Color(0xFF00E5FF) : _selectedLocation!.indoorTables == 0 ? Colors.grey[600] : Colors.white)),
                              Text('${_selectedLocation!.indoorTables} mese', style: TextStyle(fontSize: 11, color: _selectedLocation!.indoorTables == 0 ? Colors.grey[600] : Colors.grey)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _selectedLocation!.outdoorTables > 0
                              ? () => setState(() { _selectedTableType = 'outdoor'; _selectedTable = null; })
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _selectedTableType == 'outdoor' ? const Color(0xFF00FF66).withValues(alpha: 0.2) : _selectedLocation!.outdoorTables == 0 ? Colors.grey.withValues(alpha: 0.1) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _selectedTableType == 'outdoor' ? const Color(0xFF00FF66) : _selectedLocation!.outdoorTables == 0 ? Colors.grey.withValues(alpha: 0.3) : Colors.grey[700]!, width: _selectedTableType == 'outdoor' ? 2 : 1),
                            ),
                            child: Column(children: [
                              Icon(Icons.park_outlined, color: _selectedTableType == 'outdoor' ? const Color(0xFF00FF66) : _selectedLocation!.outdoorTables == 0 ? Colors.grey[600] : Colors.white70, size: 28),
                              const SizedBox(height: 6),
                              Text('Outdoor', style: TextStyle(fontWeight: FontWeight.bold, color: _selectedTableType == 'outdoor' ? const Color(0xFF00FF66) : _selectedLocation!.outdoorTables == 0 ? Colors.grey[600] : Colors.white)),
                              Text('${_selectedLocation!.outdoorTables} mese', style: TextStyle(fontSize: 11, color: _selectedLocation!.outdoorTables == 0 ? Colors.grey[600] : Colors.grey)),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedTableType == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('⬆ Selectează Indoor sau Outdoor', style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontStyle: FontStyle.italic)),
                    ),
                ],
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
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _matchType,
                  decoration: const InputDecoration(labelText: 'Tip Meci', prefixIcon: Icon(Icons.emoji_events_outlined)),
                  items: const [
                    DropdownMenuItem(value: 'Competitiv', child: Text('Competitiv (Cu puncte)')),
                    DropdownMenuItem(value: 'Amical', child: Text('Amical (Fără puncte)')),
                  ],
                  onChanged: (val) => setState(() => _matchType = val ?? 'Amical'),
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
                            label: Text(_formatHour(h)),
                            selected: isSelected,
                            selectedColor: const Color(0xFF00E5FF),
                            labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white),
                            onSelected: (selected) {
                              setState(() {
                                final double step = (_selectedLocation?.allowHalfHour ?? false) ? 0.5 : 1.0;
                                if (selected) {
                                  if (_selectedHours.isEmpty) {
                                    _selectedHours.add(h);
                                  } else {
                                    if ((h - _selectedHours.first).abs() < step + 0.01 || (h - _selectedHours.last).abs() < step + 0.01) {
                                      _selectedHours.add(h);
                                      _selectedHours.sort();
                                    } else {
                                      _selectedHours = [h];
                                    }
                                  }
                                } else {
                                  if ((h - _selectedHours.first).abs() < 0.01 || (h - _selectedHours.last).abs() < 0.01) {
                                    _selectedHours.remove(h);
                                  } else {
                                    _selectedHours.clear();
                                  }
                                }

                                if (_selectedHours.isNotEmpty) {
                                  _startHour = _selectedHours.first;
                                  _endHour = _selectedHours.last + step;
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
                        Builder(
                          builder: (context) {
                            if (_venueCustomTables.isNotEmpty) {
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF131A2A).withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF1E293B), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF).withValues(alpha: 0.05),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    )
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'PLAN CAMERĂ CLUB',
                                      style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 2),
                                    ),
                                    const SizedBox(height: 12),
                                    // 2D Grid
                                    Table(
                                      defaultColumnWidth: const FixedColumnWidth(82),
                                      children: List.generate(5, (y) {
                                        return TableRow(
                                          children: List.generate(5, (x) {
                                            final table = _getTableAt(x, y, _venueCustomTables);
                                            return _buildGridCell(x, y, table);
                                          }),
                                        );
                                      }),
                                    ),
                                    const SizedBox(height: 16),
                                    // Legends
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _buildLegendItem('Liberă', const Color(0xFF00FF66)),
                                        _buildLegendItem('Selectată', const Color(0xFF00E5FF)),
                                        _buildLegendItem('Ocupată/Antrenament', const Color(0xFFFF0055)),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            } else {
                              // Fallback secvențial clasic
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio: 1.2,
                                ),
                                itemCount: _selectedTableType == 'outdoor'
                                    ? _selectedLocation!.outdoorTables
                                    : _selectedLocation!.indoorTables,
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
                                    onTap: isTableBlocked ? null : () => setState(() => _selectedTable = tableId),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isTableBlocked
                                            ? Colors.red.withOpacity(0.15)
                                            : (isSelected ? const Color(0xFF00E5FF).withOpacity(0.2) : const Color(0xFF1E293B)),
                                        border: Border.all(
                                          color: isTableBlocked ? Colors.redAccent : (isSelected ? const Color(0xFF00E5FF) : Colors.grey[800]!),
                                          width: 1.5,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.table_restaurant, size: 18, color: isTableBlocked ? Colors.redAccent : (isSelected ? const Color(0xFF00E5FF) : Colors.grey)),
                                            const SizedBox(height: 4),
                                            Text('Masa $tableId', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isTableBlocked ? Colors.redAccent : Colors.white)),
                                            const SizedBox(height: 2),
                                            Text(statusText, style: TextStyle(fontSize: 9, color: isTableBlocked ? Colors.redAccent : Colors.grey)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            }
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
                              final avatar = (friend['avatarUrl'] as String?) ?? '';
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
            subtitle: const Text('Metodă plată'),
            isActive: _currentStep >= 3,
            state: _currentStep > 3 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (context) {
                    double totalAmount = 0.0;
                    if (_selectedLocation != null && _startHour != null && _endHour != null) {
                      if (_venueData != null) {
                        totalAmount = LevelUtils.calculateVenueBookingPrice(
                          venueData: _venueData!,
                          startHour: _startHour!,
                          endHour: _endHour!,
                        );
                      } else {
                        totalAmount = LevelUtils.calculateTotalBookingPrice(
                          _selectedLocation!.pricePerHourText,
                          _startHour!,
                          _endHour!,
                        );
                      }
                    }
                    String priceInfo = 'Tarif: ${_selectedLocation?.pricePerHourText ?? "20 RON/oră"}';
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
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Doresc factură pe firmă', style: TextStyle(color: Colors.white, fontSize: 14)),
                  activeColor: const Color(0xFF00E5FF),
                  checkColor: Colors.black,
                  value: _wantsInvoice,
                  onChanged: (val) {
                    setState(() {
                      _wantsInvoice = val ?? false;
                      if (_wantsInvoice && _invoiceEmailController.text.isEmpty) {
                        _invoiceEmailController.text = FirebaseAuth.instance.currentUser?.email ?? '';
                      }
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_wantsInvoice)
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131A2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[800]!),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _invoiceCompanyController,
                          decoration: const InputDecoration(labelText: 'Nume Firmă', isDense: true),
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _invoiceCuiController,
                          decoration: const InputDecoration(labelText: 'CUI / CIF', isDense: true),
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _invoiceRegController,
                          decoration: const InputDecoration(labelText: 'Reg. Comerțului', isDense: true),
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _invoiceAddressController,
                          decoration: const InputDecoration(labelText: 'Adresă Sediu', isDense: true),
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _invoiceEmailController,
                          decoration: const InputDecoration(labelText: 'Email pentru factură', isDense: true),
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // STEP 4: Rezumat
          Step(
            title: const Text('Rezumat Meci'),
            subtitle: const Text('Verifică înainte de a rezerva'),
            isActive: _currentStep >= 4,
            content: Builder(
              builder: (context) {
                double totalAmount = 0.0;
                if (_selectedLocation != null && _startHour != null && _endHour != null) {
                  if (_venueData != null) {
                    totalAmount = LevelUtils.calculateVenueBookingPrice(
                      venueData: _venueData!,
                      startHour: _startHour!,
                      endHour: _endHour!,
                    );
                  } else {
                    totalAmount = LevelUtils.calculateTotalBookingPrice(
                      _selectedLocation!.pricePerHourText,
                      _startHour!,
                      _endHour!,
                    );
                  }
                }
                return Container(
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
                      _summaryRow(Icons.access_time, 'Interval Orar', '${_startHour != null ? _formatHour(_startHour!) : '-'}:${_startHour != null && _startHour! % 1 != 0 ? "30" : "00"} - ${_endHour != null ? _formatHour(_endHour!) : '-'}:${_endHour != null && _endHour! % 1 != 0 ? "30" : "00"}'),
                      _summaryRow(Icons.table_restaurant, 'Masa rezervată', _selectedTable != null ? 'Masa $_selectedTable (${_selectedTableType ?? 'N/A'})' : '-'),
                      _summaryRow(Icons.house_outlined, 'Tip', _selectedTableType == 'indoor' ? '🏠 Indoor' : _selectedTableType == 'outdoor' ? '🌳 Outdoor' : '-'),
                      _summaryRow(Icons.people, 'Invitați', _invitedFriendUids.isEmpty
                          ? 'Niciun prieten selectat'
                          : '${_invitedFriendUids.length} prieteni vor primi invitație'),
                      const Divider(color: Colors.grey),
                      _summaryRow(Icons.emoji_events, 'Tip Meci', _matchType),
                      _summaryRow(Icons.payment, 'Plată', _paymentMethod),
                      _summaryRow(Icons.monetization_on, 'Cost Total', '${totalAmount.toStringAsFixed(0)} lei'),
                    ],
                  ),
                );
              }
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

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildGridCell(int x, int y, Map<String, dynamic>? table) {
    if (table != null) {
      final type = table['type'] ?? 'indoor';
      
      bool isVisible = false;
      if (_selectedTableType == 'outdoor') {
        isVisible = type == 'outdoor';
      } else {
        isVisible = type == 'indoor' || type == 'training';
      }

      final tableId = table['tableId'] as int;
      final tableName = table['name'] ?? 'Masa $tableId';
      final isReserved = _reservedTables.contains(tableId);
      final isTrainingBlocked = _isTableReservedForTraining(table, _venueTrainingConfig);
      final isTableBlocked = isReserved || isTrainingBlocked || _isDayBlockedFlag || _overlappingTournament != null;
      final isSelected = _selectedTable == tableId;

      String statusText = 'Liberă';
      if (_isDayBlockedFlag) {
        statusText = 'Zi închisă';
      } else if (_overlappingTournament != null) {
        statusText = 'Turneu';
      } else if (isReserved) {
        statusText = 'Ocupată';
      } else if (isTrainingBlocked) {
        statusText = 'Antrenament';
      }

      final Color blockedColor = isTrainingBlocked ? Colors.purpleAccent : Colors.redAccent;
      final Color blockedBgColor = isTrainingBlocked ? Colors.purple.withOpacity(0.15) : Colors.red.withOpacity(0.15);
      final Color activeBorderColor = isTableBlocked ? blockedColor : (isSelected ? const Color(0xFF00E5FF) : const Color(0xFF00FF66));
      final Color activeBgColor = isTableBlocked ? blockedBgColor : (isSelected ? const Color(0xFF00E5FF).withOpacity(0.3) : const Color(0xFF00FF66).withOpacity(0.1));
      final Color contentColor = isTableBlocked ? blockedColor : (isSelected ? const Color(0xFF00E5FF) : const Color(0xFF00FF66));

      final IconData tableIcon = type == 'training' 
          ? Icons.school 
          : (type == 'outdoor' ? Icons.wb_sunny : Icons.table_restaurant);

      if (!isVisible) {
        return Container(
          height: 68,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
          ),
          child: Center(
            child: Icon(tableIcon, color: Colors.grey.withOpacity(0.3), size: 16),
          ),
        );
      }

      return GestureDetector(
        onTap: isTableBlocked ? () {
          if (isTrainingBlocked) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$tableName este rezervată automat pentru antrenamentul copiilor.'),
                backgroundColor: Colors.purple,
              ),
            );
          }
        } : () {
          setState(() => _selectedTable = tableId);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 68,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: activeBgColor,
            border: Border.all(
              color: activeBorderColor,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(tableIcon, size: 16, color: contentColor),
                const SizedBox(height: 2),
                Text(tableName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isTableBlocked ? blockedColor : Colors.white), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                Text(statusText, style: TextStyle(fontSize: 9, color: isTableBlocked ? blockedColor : Colors.grey)),
              ],
            ),
          ),
        ),
      );
    } else {
      return Container(
        height: 68,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.transparent),
        ),
      );
    }
  }
}
