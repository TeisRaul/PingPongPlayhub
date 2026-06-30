import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/invoice_service.dart';
import '../data/mock_locations.dart';
import 'payment_screen.dart';
import '../utils/level_utils.dart';
import '../widgets/city_selector.dart';

class CreateMatchTab extends StatefulWidget {
  final String? preselectedCity;
  final String? preselectedVenueId;

  const CreateMatchTab({
    super.key,
    this.preselectedCity,
    this.preselectedVenueId,
  });

  @override
  State<CreateMatchTab> createState() => _CreateMatchTabState();
}

class _CreateMatchTabState extends State<CreateMatchTab> {
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isLoadingLocs = false;

  // Step 1: Locatie
  String _selectedSport = 'ping_pong';
  String? _selectedCity;
  PingPongLocation? _selectedLocation;
  String? _selectedTableType; // null = not chosen, 'indoor' or 'outdoor'
  int _maxPlayers = 2;
  String _visibility = 'Public';
  String _matchType = 'Competitiv';
  Map<String, int> _selectedExtraServices = {};
  
  // Bar Inventory
  List<Map<String, dynamic>> _barInventory = [];
  Map<String, int> _selectedBarItems = {};

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

  // Step 3: Plata
  String _paymentMethod = 'Cash la locație';
  bool _wantsInvoice = false;
  final _invoiceCompanyController = TextEditingController();
  final _invoiceCuiController = TextEditingController();
  final _invoiceRegController = TextEditingController();
  final _invoiceAddressController = TextEditingController();
  final _invoiceEmailController = TextEditingController();

  List<PingPongLocation> _allLocations = List.from(mockLocations);

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
    if (widget.preselectedCity != null) {
      _selectedCity = widget.preselectedCity;
    }
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
        final String? stripeAccountId = data['stripeAccountId'];
        final bool offersSubscription = data['offersSubscription'] as bool? ?? false;
        final double subscriptionPrice = (data['subscriptionPrice'] as num?)?.toDouble() ?? 150.0;
        
        List<Map<String, dynamic>> extraServices = [];
        if (data['extraServices'] != null) {
          extraServices = List<Map<String, dynamic>>.from(
            (data['extraServices'] as List<dynamic>).map((e) => Map<String, dynamic>.from(e))
          );
        }

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
          stripeAccountId: stripeAccountId,
          offersSubscription: offersSubscription,
          subscriptionPrice: subscriptionPrice,
          extraServices: extraServices,
          isPublic: data['isPublic'] as bool? ?? false,
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
          if (widget.preselectedVenueId != null) {
            final found = merged.any((l) => l.id == widget.preselectedVenueId);
            if (found) {
              _selectedLocation = merged.firstWhere((l) => l.id == widget.preselectedVenueId);
              _selectedCity = _selectedLocation?.city;
            }
          }
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

  Future<void> _loadBarInventory(String venueId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('venues')
          .doc(venueId)
          .collection('inventory')
          .where('isActive', isEqualTo: true)
          .get();
      if (mounted) {
        setState(() {
          _barInventory = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        });
      }
    } catch (e) {
      debugPrint('Eroare incarcare inventar bar: $e');
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
        .where((loc) => loc.city.trim().toLowerCase() == _selectedCity!.trim().toLowerCase() && loc.supportedSports.contains(_selectedSport) && !loc.isPublic)
        .toList();
  }

  // --- Step 2 Helpers ---
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

        if (_venueData != null && _selectedLocation?.isPublic != true) {
          if (_venueData!.containsKey('layouts')) {
            final layouts = _venueData!['layouts'] as Map<String, dynamic>;
            if (layouts.containsKey(_selectedSport)) {
              customTables = List<Map<String, dynamic>>.from(layouts[_selectedSport] ?? []);
            }
          } else if (venueData.containsKey('customTables') && _selectedSport == 'ping_pong') {
            customTables = List<Map<String, dynamic>>.from(venueData['customTables'] ?? []);
          }
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

        // Verifica suprapunere: [start, end)
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

  int _getIndoorCount() {
    if (_venueData != null && _venueData!.containsKey('resourcesPerSport')) {
      final rps = _venueData!['resourcesPerSport'] as Map<String, dynamic>;
      if (rps.containsKey(_selectedSport)) {
        return rps[_selectedSport]['indoor'] as int? ?? 0;
      }
    }
    return _selectedLocation?.indoorTables ?? 0;
  }

  int _getOutdoorCount() {
    if (_venueData != null && _venueData!.containsKey('resourcesPerSport')) {
      final rps = _venueData!['resourcesPerSport'] as Map<String, dynamic>;
      if (rps.containsKey(_selectedSport)) {
        return rps[_selectedSport]['outdoor'] as int? ?? 0;
      }
    }
    return _selectedLocation?.outdoorTables ?? 0;
  }

  Map<String, dynamic>? _getTableAt(int x, int y, List<Map<String, dynamic>> tables) {
    for (var t in tables) {
      if (t['x'] == x && t['y'] == y) {
        return t;
      }
    }
    return null;
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
        for (var service in _selectedLocation!.extraServices) {
          int count = _selectedExtraServices[service['name']] ?? 0;
          if (count > 0) {
            totalAmount += count * (service['price'] as num).toDouble();
          }
        }
        
        for (var item in _barInventory) {
          int count = _selectedBarItems[item['id']] ?? 0;
          if (count > 0) {
             totalAmount += count * (item['price'] as num).toDouble();
          }
        }
      }

      List<Map<String, dynamic>> finalBarOrder = [];
      for (var item in _barInventory) {
        int count = _selectedBarItems[item['id']] ?? 0;
        if (count > 0) {
           finalBarOrder.add({
             'id': item['id'],
             'name': item['name'],
             'price': item['price'],
             'quantity': count,
           });
        }
      }

      final matchData = {
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
        'sport': _selectedSport,
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
        'extraServices': _selectedExtraServices,
        'barOrderItems': finalBarOrder,
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

      final docRef = await FirebaseFirestore.instance.collection('matches').add(matchData);

      if (_wantsInvoice && mounted) {
        try {
          await InvoiceService.generateAndShareInvoice(
            matchId: docRef.id,
            amount: totalAmount,
            venueName: _selectedLocation!.name,
            date: DateFormat('yyyy-MM-dd').format(_selectedDate),
            time: '${_startHour!.toString().padLeft(2, '0')}:00 - ${_endHour!.toString().padLeft(2, '0')}:00',
            companyName: _invoiceCompanyController.text.trim(),
            cui: _invoiceCuiController.text.trim(),
            regCom: _invoiceRegController.text.trim(),
            address: _invoiceAddressController.text.trim(),
            email: _invoiceEmailController.text.trim(),
          );
        } catch (e) {
          debugPrint('Eroare generare factură: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meci creat cu succes!'), backgroundColor: Colors.green),
        );
        // Reset form
        setState(() {
          _currentStep = 0;
          _selectedCity = null;
          _selectedLocation = null;
          _selectedTableType = null;
          _startHour = null;
          _endHour = null;
          _selectedHours.clear();
          _selectedTable = null;
          _maxPlayers = 2;
          _visibility = 'Public';
          _matchType = 'Competitiv';
          _selectedExtraServices.clear();
          _wantsInvoice = false;
          _invoiceCompanyController.clear();
          _invoiceCuiController.clear();
          _invoiceRegController.clear();
          _invoiceAddressController.clear();
          _invoiceEmailController.clear();
          _barInventory.clear();
          _selectedBarItems.clear();
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

  Widget _buildInventoryRow(Map<String, dynamic> item) {
    final String id = item['id'];
    final String name = item['name'] ?? '';
    final String category = item['category'] ?? '';
    final double price = (item['price'] as num).toDouble();
    final int count = _selectedBarItems[id] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                category == 'Echipament' ? Icons.sports_tennis :
                category == 'Mâncare' ? Icons.restaurant :
                category == 'Apă' ? Icons.water_drop :
                category == 'Cafea' ? Icons.local_cafe :
                category == 'Snack' ? Icons.fastfood : Icons.local_drink,
                color: const Color(0xFF00E5FF),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('$price RON', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.grey),
                onPressed: count > 0
                    ? () => setState(() => _selectedBarItems[id] = count - 1)
                    : null,
              ),
              Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00E5FF)),
                onPressed: () => setState(() => _selectedBarItems[id] = count + 1),
              ),
            ],
          ),
        ],
      ),
    );
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
            if (_selectedTableType == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alege tipul mesei: Indoor sau Outdoor.'), backgroundColor: Colors.redAccent));
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
             // Step Bar Inventory
             // Mergem la pasul 3 (Plata)
          } else if (_currentStep == 3) {
            if (_paymentMethod.contains('Card')) {
              double amount = LevelUtils.calculateTotalBookingPrice(
                _selectedLocation!.pricePerHourText,
                _startHour!,
                _endHour!,
              );
              
              for (var service in _selectedLocation!.extraServices) {
                int count = _selectedExtraServices[service['name']] ?? 0;
                if (count > 0) {
                  amount += count * (service['price'] as num).toDouble();
                }
              }
              
              for (var item in _barInventory) {
                int count = _selectedBarItems[item['id']] ?? 0;
                if (count > 0) {
                   amount += count * (item['price'] as num).toDouble();
                }
              }

              final paymentSuccess = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PaymentScreen(
                  amount: amount,
                  venueId: _selectedLocation!.id,
                  destinationAccountId: _selectedLocation!.stripeAccountId,
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

          if (_currentStep < 4) {
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
            subtitle: const Text('Sport, Oraș și Locație'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSportSelector(),
                const SizedBox(height: 16),
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
                  initialValue: _selectedLocation,
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
                      _selectedExtraServices.clear();
                      _barInventory.clear();
                      _selectedBarItems.clear();
                    });
                    if (val != null) _loadBarInventory(val.id);
                  },
                ),
                if (_selectedLocation != null) ...[
                  if (_selectedLocation!.offersSubscription) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Color(0xFF00E5FF)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Abonament disponibil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                Text('Joacă nelimitat pentru ${_selectedLocation!.subscriptionPrice} RON/lună.', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sistemul de plăți recurente (abonamente) va fi integrat curând.')));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E5FF),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Cumpără'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_selectedLocation!.extraServices.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Servicii Extra (Opțional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    ..._selectedLocation!.extraServices.map((service) {
                      final String name = service['name'] ?? '';
                      final double price = (service['price'] as num).toDouble();
                      final int count = _selectedExtraServices[name] ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[800]!),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.add_circle_outline, color: Colors.orangeAccent),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    Text('$price RON / buc', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  ],
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.grey),
                                  onPressed: count > 0
                                      ? () => setState(() => _selectedExtraServices[name] = count - 1)
                                      : null,
                                ),
                                Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00E5FF)),
                                  onPressed: () => setState(() => _selectedExtraServices[name] = count + 1),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
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
                          onTap: _getIndoorCount() > 0
                              ? () => setState(() {
                                    _selectedTableType = 'indoor';
                                    _selectedTable = null;
                                  })
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _selectedTableType == 'indoor'
                                  ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
                                  : _getIndoorCount() == 0
                                      ? Colors.grey.withValues(alpha: 0.1)
                                      : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _selectedTableType == 'indoor'
                                    ? const Color(0xFF00E5FF)
                                    : _getIndoorCount() == 0
                                        ? Colors.grey.withValues(alpha: 0.3)
                                        : Colors.grey[700]!,
                                width: _selectedTableType == 'indoor' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.house_outlined,
                                  color: _selectedTableType == 'indoor'
                                      ? const Color(0xFF00E5FF)
                                      : _getIndoorCount() == 0
                                          ? Colors.grey[600]
                                          : Colors.white70,
                                  size: 28,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Indoor',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTableType == 'indoor'
                                        ? const Color(0xFF00E5FF)
                                        : _getIndoorCount() == 0
                                            ? Colors.grey[600]
                                            : Colors.white,
                                  ),
                                ),
                                Text(
                                  '${_getIndoorCount()} mese',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _getIndoorCount() == 0
                                        ? Colors.grey[600]
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _getOutdoorCount() > 0
                              ? () => setState(() {
                                    _selectedTableType = 'outdoor';
                                    _selectedTable = null;
                                  })
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _selectedTableType == 'outdoor'
                                  ? const Color(0xFF00FF66).withValues(alpha: 0.2)
                                  : _getOutdoorCount() == 0
                                      ? Colors.grey.withValues(alpha: 0.1)
                                      : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _selectedTableType == 'outdoor'
                                    ? const Color(0xFF00FF66)
                                    : _getOutdoorCount() == 0
                                        ? Colors.grey.withValues(alpha: 0.3)
                                        : Colors.grey[700]!,
                                width: _selectedTableType == 'outdoor' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.park_outlined,
                                  color: _selectedTableType == 'outdoor'
                                      ? const Color(0xFF00FF66)
                                      : _getOutdoorCount() == 0
                                          ? Colors.grey[600]
                                          : Colors.white70,
                                  size: 28,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Outdoor',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTableType == 'outdoor'
                                        ? const Color(0xFF00FF66)
                                        : _getOutdoorCount() == 0
                                            ? Colors.grey[600]
                                            : Colors.white,
                                  ),
                                ),
                                Text(
                                  '${_getOutdoorCount()} mese',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _getOutdoorCount() == 0
                                        ? Colors.grey[600]
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedTableType == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        '⬆ Selectează Indoor sau Outdoor',
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                const Text('Setări Meci', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _maxPlayers,
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
                        initialValue: _visibility,
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
                  initialValue: _matchType,
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
                            side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.5)),
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
                          child: Builder(
                            builder: (context) {
                              if (_venueCustomTables.isNotEmpty) {
                                return Column(
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
                                );
                              } else {
                                // Fallback secvențial clasic
                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 1.2,
                                  ),
                                  itemCount: _selectedTableType == 'outdoor'
                                      ? _getOutdoorCount()
                                      : _getIndoorCount(),
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
                                          color: isTableBlocked ? Colors.red.withValues(alpha: 0.15) : (isSelected ? const Color(0xFF00E5FF).withValues(alpha: 0.3) : const Color(0xFF1E293B)),
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
                                );
                              }
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          Step(
            title: const Text('Echipamente & Bar (Opțional)'),
            subtitle: const Text('Închiriază palete sau comandă băuturi la masă'),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
            content: _barInventory.isEmpty
                ? const Text('Această sală nu are momentan un meniu configurat.', style: TextStyle(color: Colors.grey))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_barInventory.any((item) => item['category'] == 'Echipament')) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('Echipamente (Închiriere)', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        ..._barInventory.where((item) => item['category'] == 'Echipament').map((item) => _buildInventoryRow(item)).toList(),
                        const SizedBox(height: 16),
                      ],
                      if (_barInventory.any((item) => item['category'] != 'Echipament')) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('Băuturi & Snack-uri', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        ..._barInventory.where((item) => item['category'] != 'Echipament').map((item) => _buildInventoryRow(item)).toList(),
                      ],
                    ],
                  ),
          ),
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
                    String priceInfo = 'Tarif pe oră: ${_selectedLocation?.pricePerHourText ?? "20 RON/oră"}';
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
                      
                      for (var item in _barInventory) {
                        int count = _selectedBarItems[item['id']] ?? 0;
                        if (count > 0) {
                           totalAmount += count * (item['price'] as num).toDouble();
                        }
                      }
                      for (var service in _selectedLocation!.extraServices) {
                        int count = _selectedExtraServices[service['name']] ?? 0;
                        if (count > 0) {
                          totalAmount += count * (service['price'] as num).toDouble();
                        }
                      }
                    }
                    return Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
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
          Step(
            title: const Text('Rezumat'),
            subtitle: const Text('Verifică înainte de creare'),
            isActive: _currentStep >= 4,
            content: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF131A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow(Icons.location_on, 'Locație', '${_selectedLocation?.name ?? '-'} (${_selectedCity ?? '-'})'),
                  _summaryRow(Icons.calendar_today, 'Data', DateFormat('dd MMM yyyy').format(_selectedDate)),
                  _summaryRow(Icons.access_time, 'Interval Orare', '${_startHour ?? '-'}:00 - ${_endHour ?? '-'}:00 (${((_endHour ?? 0) - (_startHour ?? 0))} ore)'),
                  _summaryRow(Icons.table_restaurant, 'Masa', _selectedTable != null ? 'Masa $_selectedTable (${_selectedTableType ?? 'N/A'})' : '-'),
                  _summaryRow(Icons.house_outlined, 'Tip', _selectedTableType == 'indoor' ? '🏠 Indoor' : _selectedTableType == 'outdoor' ? '🌳 Outdoor' : '-'),
                  Builder(builder: (context) {
                    List<String> barDesc = [];
                    for (var item in _barInventory) {
                      int count = _selectedBarItems[item['id']] ?? 0;
                      if (count > 0) {
                         barDesc.add('${item['name']} x$count');
                      }
                    }
                    if (barDesc.isEmpty) return const SizedBox.shrink();
                    return _summaryRow(Icons.local_cafe, 'Consumație Bar', barDesc.join('\n'));
                  }),
                  const Divider(color: Colors.grey),
                  _summaryRow(Icons.emoji_events, 'Tip Meci', _matchType),
                  _summaryRow(Icons.payment, 'Plată', _paymentMethod),
                  _summaryRow(
                    Icons.monetization_on,
                    'Cost Total',
                    '${_selectedLocation != null && _startHour != null && _endHour != null
                        ? (_venueData != null
                            ? LevelUtils.calculateVenueBookingPrice(
                                venueData: _venueData!,
                                startHour: _startHour!,
                                endHour: _endHour!,
                              )
                            : LevelUtils.calculateTotalBookingPrice(
                                _selectedLocation!.pricePerHourText,
                                _startHour!,
                                _endHour!,
                              )).toStringAsFixed(0)
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
          Icon(icon, color: const Color(0xFF00E5FF), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSportSelector() {
    final sports = [
      {'id': 'ping_pong', 'label': 'Ping Pong'},
      {'id': 'padel', 'label': 'Padel'},
      {'id': 'tenis', 'label': 'Tenis'},
      {'id': 'fotbal', 'label': 'Fotbal'},
      {'id': 'handbal', 'label': 'Handbal'},
      {'id': 'baschet', 'label': 'Baschet'},
    ];
    return Container(
      width: double.infinity,
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: sports.map((s) {
            final isSelected = _selectedSport == s['id'];
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(s['label']!),
                selected: isSelected,
                selectedColor: const Color(0xFF00E5FF),
                labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white),
                backgroundColor: const Color(0xFF1E293B),
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _selectedSport = s['id']!;
                      _selectedLocation = null;
                      _selectedTableType = null;
                      _selectedExtraServices.clear();
                    });
                  }
                },
              ),
            );
          }).toList(),
        ),
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
      final Color blockedBgColor = isTrainingBlocked ? Colors.purple.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15);
      final Color activeBorderColor = isTableBlocked ? blockedColor : (isSelected ? const Color(0xFF00E5FF) : const Color(0xFF00FF66));
      final Color activeBgColor = isTableBlocked ? blockedBgColor : (isSelected ? const Color(0xFF00E5FF).withValues(alpha: 0.3) : const Color(0xFF00FF66).withValues(alpha: 0.1));
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
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
          ),
          child: Center(
            child: Icon(tableIcon, color: Colors.grey.withValues(alpha: 0.3), size: 16),
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
