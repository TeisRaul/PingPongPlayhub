import 'package:flutter/material.dart';
import '../services/venue_tools.dart';
import '../data/sports.dart';
import '../data/sport_specs.dart';
import '../widgets/sport_specs_card.dart';
import '../l10n/strings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/booking_service.dart';
import '../services/billing_service.dart';
import '../utils/player_name.dart';
import '../services/trainer_service.dart';
import '../services/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/invoice_service.dart';
import '../data/mock_locations.dart';
import '../utils/hour_utils.dart';
import 'payment_screen.dart';
import '../utils/level_utils.dart';
import '../widgets/city_selector.dart';
import '../theme/app_theme.dart';
import '../widgets/rating_badge.dart';
import '../widgets/venue_filter_bar.dart';
import '../utils/venue_filters.dart';
import '../services/location_service.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import '../widgets/voucher_field.dart';
import '../services/voucher_service.dart';

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

  // Step 1: Locatie
  String _selectedSport = 'ping_pong';
  String? _selectedCity;
  PingPongLocation? _selectedLocation;
  String? _selectedTableType; // null = not chosen, 'indoor' or 'outdoor'
  int _maxPlayers = 2;
  String _visibility = 'Public';
  String _matchType = 'Competitiv';
  bool _requireApproval = true; // gazda aprobă manual cine se alătură
  bool _rulesAccepted = false; // a acceptat regulile sălii (dacă are)
  Map<String, int> _selectedExtraServices = {};
  
  // Bar Inventory
  List<Map<String, dynamic>> _barInventory = [];
  bool _needsTrainer = false;
  List<TrainerInfo> _trainers = [];
  TrainerInfo? _selectedTrainer;
  String _trainerPlan = 'session'; // 'session' = doar această ședință, 'month' = abonament lunar
  int _trainerPersons = 1; // câte persoane au nevoie de antrenor (inclusiv gazda)
  bool _trainerLock = true; // lobby închis: nimeni altcineva nu se poate alătura
  final Set<String> _trainerFriendUids = {}; // prieteni adăugați direct în lobby
  List<Map<String, dynamic>> _myFriends = [];
  bool _friendsLoaded = false;
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
  bool _recurring = false; // repetă rezervarea în fiecare săptămână
  VoucherResult? _voucher; // cod de reducere aplicat (previzualizare)
  VenueFilters _venueFilters = VenueFilters(); // filtre și sortare pentru lista de săli
  LatLng? _userPos; // locația utilizatorului (doar după ce a cerut sortarea după distanță)
  VoucherResult? _redeemedVoucher; // folosire rezervată pe server în timpul confirmării
  bool _bookingCreated = false;
  int _recurringWeeks = 4;
  final _invoiceCompanyController = TextEditingController();
  final _invoiceCuiController = TextEditingController();
  final _invoiceRegController = TextEditingController();
  final _invoiceAddressController = TextEditingController();
  final _invoiceEmailController = TextEditingController();

  List<PingPongLocation> _allLocations = [];

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
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('venues')
          .get();

      final bool subscriptionRequired = await BillingService.subscriptionRequired();
      final List<PingPongLocation> fetched = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['isVerified'] == false) continue; // sală în așteptarea aprobării
        if (!BillingService.venueVisible(data, subscriptionRequired)) continue; // fără abonament activ
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

        final List<String> supportedSports = List<String>.from(data['supportedSports'] ?? ['ping_pong']);

        final Map<String, dynamic> sportSpecs = {};
        final rawSpecs = data['sportSpecs'];
        if (rawSpecs is Map) {
          rawSpecs.forEach((k, v) {
            if (v is Map) sportSpecs[k.toString()] = Map<String, dynamic>.from(v);
          });
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
          supportedSports: supportedSports,
          sportSpecs: sportSpecs,
          venueRules: (data['venueRules'] ?? '').toString(),
          rating: (data['rating'] as num?)?.toDouble(),
          ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
          latitude: (data['latitude'] as num?)?.toDouble(),
          longitude: (data['longitude'] as num?)?.toDouble(),
          schedule: {
            if (schedule != null)
              for (final e in schedule.entries) e.key.toString(): e.value.toString(),
          },
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


  Map<String, dynamic>? get _currentSpecs => _selectedLocation?.sportSpecs[_selectedSport] as Map<String, dynamic>?;

  List<int> get _playerOptions => SportSpecs.playerOptions(_selectedSport, _currentSpecs);

  bool get _venueHasRules =>
      _selectedLocation != null && SportSpecs.hasRules(_selectedSport, _currentSpecs, _selectedLocation!.venueRules);

  // --- Antrenor (opțional) ---
  Widget _venueItem(PingPongLocation loc) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(loc.name, overflow: TextOverflow.ellipsis)),
        if (venueDistanceLabel(loc, _userPos) != null) ...[
          const SizedBox(width: 8),
          Text(venueDistanceLabel(loc, _userPos)!, style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
        const SizedBox(width: 10),
        RatingBadge(rating: loc.rating, count: loc.ratingCount),
      ],
    );
  }

  Future<void> _loadTrainers(String venueId) async {
    try {
      final list = await TrainerService.trainersForVenue(venueId);
      if (mounted) setState(() => _trainers = list);
    } catch (e) {
      debugPrint('Eroare incarcare antrenori: $e');
    }
  }

  Future<void> _loadFriends() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || _friendsLoaded) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('friendships')
          .where('uids', arrayContains: me.uid)
          .get();
      final List<Map<String, dynamic>> list = [];
      for (final doc in snap.docs) {
        final d = doc.data();
        final List<dynamic> uids = d['uids'] ?? [];
        final List<dynamic> names = d['usernames'] ?? [];
        final List<dynamic> avatars = d['avatars'] ?? [];
        if (uids.length < 2) continue;
        final int i = uids.indexOf(me.uid) == 0 ? 1 : 0;
        list.add({
          'uid': uids[i].toString(),
          'username': (names.length > i ? names[i] : '').toString(),
          'avatarUrl': avatars.length > i ? avatars[i] : null,
        });
      }
      list.sort((a, b) => (a['username'] as String).toLowerCase().compareTo((b['username'] as String).toLowerCase()));
      if (mounted) {
        setState(() {
          _myFriends = list;
          _friendsLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Eroare incarcare prieteni: $e');
    }
  }

  void _pickTrainer(TrainerInfo t) {
    setState(() {
      _selectedTrainer = t;
      // Planul implicit: ce a setat antrenorul (doar ședință / doar lunar / ambele → ședință).
      if (t.pricePerSession == null && t.pricePerMonth != null) {
        _trainerPlan = 'month';
      } else if (t.pricePerMonth == null) {
        _trainerPlan = 'session';
      } else if (_trainerPlan != 'session' && _trainerPlan != 'month') {
        _trainerPlan = 'session';
      }
    });
  }

  void _trimFriends() {
    final int max = _trainerPersons - 1;
    while (_trainerFriendUids.length > max) {
      _trainerFriendUids.remove(_trainerFriendUids.last);
    }
  }

  String _levelNameFor(num rating) {
    const int pointsPerLevel = 250;
    final int levelIndex = (rating < 0 ? 0 : rating).toInt() ~/ pointsPerLevel;
    const List<String> tiers = ['Iron', 'Bronze', 'Silver', 'Gold', 'Platinum'];
    const List<String> subLevels = ['I', 'II', 'III', 'IV'];
    if (levelIndex < tiers.length * subLevels.length) {
      return '${tiers[levelIndex ~/ subLevels.length]} ${subLevels[levelIndex % subLevels.length]}';
    }
    return 'Diamond';
  }

  List<Widget> _buildTrainerOptions() {
    final TrainerInfo t = _selectedTrainer!;
    final List<String> plans = [
      if (t.pricePerSession != null || t.pricePerMonth == null) 'session',
      if (t.pricePerMonth != null) 'month',
    ];
    final int freeSlots = _trainerPersons - 1 - _trainerFriendUids.length;
    String planLabel(String p) {
      if (p == 'month') {
        return '${tr('tr.plan_month')} (${tr('tr.price_month', {'price': t.pricePerMonth!.toStringAsFixed(0)})})';
      }
      return t.pricePerSession != null
          ? '${tr('tr.plan_session')} (${tr('tr.price_session', {'price': t.pricePerSession!.toStringAsFixed(0)})})'
          : tr('tr.plan_session');
    }

    return [
      Divider(color: AppColors.text12),
      Text(tr('tr.plan_title'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: plans
            .map((p) => ChoiceChip(
                  label: Text(planLabel(p)),
                  selected: _trainerPlan == p,
                  onSelected: (_) => setState(() => _trainerPlan = p),
                ))
            .toList(),
      ),
      const SizedBox(height: 12),
      Text(tr('tr.persons_title'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(height: 6),
      DropdownButtonFormField<int>(
        initialValue: _trainerPersons,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.groups)),
        items: [
          for (int i = 1; i <= 6; i++)
            DropdownMenuItem(value: i, child: Text(i == 1 ? tr('tr.persons_one') : tr('tr.persons_many', {'n': '$i'}))),
        ],
        onChanged: (v) => setState(() {
          _trainerPersons = v ?? 1;
          _trimFriends();
        }),
      ),
      if (_trainerPersons > 1) ...[
        const SizedBox(height: 12),
        Text(tr('tr.friends_title'), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        if (!_friendsLoaded)
          const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()))
        else if (_myFriends.isEmpty)
          Text(tr('tr.friends_none'), style: TextStyle(color: AppColors.muted, fontSize: 12))
        else ...[
          Text(tr('tr.friends_hint', {'n': '$freeSlots'}), style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ..._myFriends.map((f) {
            final String uid = f['uid'] as String;
            final bool checked = _trainerFriendUids.contains(uid);
            final String name = (f['username'] as String).isEmpty ? tr('common.unknown_player') : f['username'] as String;
            return CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.accent,
              checkColor: Colors.black,
              title: Text(name, style: TextStyle(color: AppColors.text)),
              value: checked,
              onChanged: (checked || freeSlots > 0)
                  ? (v) => setState(() {
                        if (v == true) {
                          _trainerFriendUids.add(uid);
                        } else {
                          _trainerFriendUids.remove(uid);
                        }
                      })
                  : null,
            );
          }),
        ],
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('tr.lock_title'), style: TextStyle(color: AppColors.text, fontSize: 14)),
        subtitle: Text(tr('tr.lock_sub'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
        value: _trainerLock,
        onChanged: (v) => setState(() => _trainerLock = v),
      ),
    ];
  }

  bool _trainerAvailable(TrainerInfo t) {
    if (_startHour == null || _endHour == null) return true;
    return TrainerService.worksAt(t.data, _selectedDate, _startHour!.toInt(), _endHour!.toInt());
  }

  String _trainerPriceText(TrainerInfo t) {
    final parts = <String>[];
    if (t.pricePerSession != null) parts.add(tr('tr.price_session', {'price': t.pricePerSession!.toStringAsFixed(0)}));
    if (t.pricePerMonth != null) parts.add(tr('tr.price_month', {'price': t.pricePerMonth!.toStringAsFixed(0)}));
    return parts.isEmpty ? tr('tr.price_unset') : parts.join('  |  ');
  }

  Widget _buildTrainerSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(tr('tr.section'), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('tr.need'), style: TextStyle(color: AppColors.text, fontSize: 14)),
            subtitle: Text(
              _trainers.isEmpty ? tr('tr.none_venue') : tr('tr.note'),
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            value: _needsTrainer,
            onChanged: _trainers.isEmpty
                ? null
                : (v) {
                    setState(() {
                      _needsTrainer = v;
                      if (!v) {
                        _selectedTrainer = null;
                        _trainerPersons = 1;
                        _trainerFriendUids.clear();
                      }
                    });
                    if (v) _loadFriends();
                  },
          ),
          if (_needsTrainer) ...[
            Text(tr('tr.pick'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            ..._trainers.map((t) {
              final bool ok = _trainerAvailable(t);
              final bool selected = _selectedTrainer?.id == t.id;
              return Card(
                color: selected ? AppColors.accent.withValues(alpha: 0.15) : AppColors.card,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: selected ? AppColors.accent : AppColors.text12),
                ),
                child: ListTile(
                  enabled: ok,
                  onTap: ok ? () => _pickTrainer(t) : null,
                  leading: Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: ok ? AppColors.accent : AppColors.muted,
                  ),
                  title: Text(
                    t.name.isEmpty ? tr('tr.unknown') : t.name,
                    style: TextStyle(color: ok ? AppColors.text : AppColors.muted, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    ok ? _trainerPriceText(t) : tr('tr.unavailable'),
                    style: TextStyle(color: ok ? AppColors.accent : Colors.orangeAccent, fontSize: 12),
                  ),
                  trailing: RatingBadge(
                    rating: (t.data['trainerRating'] as num?)?.toDouble(),
                    count: (t.data['trainerRatingCount'] as num?)?.toInt() ?? 0,
                  ),
                ),
              );
            }),
            if (_selectedTrainer != null) ..._buildTrainerOptions(),
          ],
        ],
      ),
    );
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

  Future<bool> _requestUserLocation() async {
    final p = await LocationService.current();
    if (mounted) setState(() => _userPos = p);
    return p != null;
  }

  List<PingPongLocation> get _filteredLocations {
    if (_selectedCity == null) return [];
    final base = _allLocations
        .where((loc) => loc.city.trim().toLowerCase() == _selectedCity!.trim().toLowerCase() && loc.supportedSports.contains(_selectedSport) && !loc.isPublic)
        .toList();
    final result = applyVenueFilters(base, _venueFilters, _userPos);
    // Sala deja aleasă rămâne în listă (dropdown-ul cere ca valoarea selectată să existe printre opțiuni).
    final sel = _selectedLocation;
    if (sel != null && base.contains(sel) && !result.contains(sel)) result.insert(0, sel);
    return result;
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
        if (data['status'] == 'cancelled') continue;
        final double matchStart = hourValue(data['startHour']);
        final double matchEnd = hourValue(data['endHour']);
        final int tableId = (data['tableId'] as num?)?.toInt() ?? 0;

        // Verifica suprapunere: [start, end)
        if (_startHour! < matchEnd && matchStart < _endHour!) {
          reserved.add(tableId);
        }
      }

      // 4. Intervale blocate de sală (mentenanță etc.)
      final blk = VenueTools.blockFor(venueData, dateStr, _startHour!, _endHour!, sport: _selectedSport);
      if (blk.allTables) isDayBlocked = true;
      reserved.addAll(blk.tables);

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
  /// Validează datele de facturare (doar dacă utilizatorul a cerut factură pe firmă).
  String? _invoiceError() {
    if (!_wantsInvoice) return null;
    if (_invoiceCompanyController.text.trim().isEmpty) return tr('cm.err_invoice_company');
    final String cui = _invoiceCuiController.text.trim().toUpperCase().replaceAll(' ', '');
    if (!RegExp(r'^(RO)?[0-9]{2,10}$').hasMatch(cui)) return tr('cm.err_invoice_cui');
    if (_invoiceAddressController.text.trim().isEmpty) return tr('cm.err_invoice_address');
    final String email = _invoiceEmailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return tr('cm.err_invoice_email');
    return null;
  }

  /// Prețul mesei (fără extra / bar) pentru intervalul ales.
  double _tablePrice() {
    if (_selectedLocation == null || _startHour == null || _endHour == null) return 0;
    if (_venueData != null) {
      return LevelUtils.calculateVenueBookingPrice(
        venueData: _venueData!,
        startHour: _startHour!,
        endHour: _endHour!,
        date: _selectedDate,
      );
    }
    return LevelUtils.calculateTotalBookingPrice(_selectedLocation!.pricePerHourText, _startHour!, _endHour!);
  }

  double get _voucherDiscount {
    final v = _voucher;
    if (v == null || !v.validFor(_tablePrice())) return 0;
    return v.discount;
  }

  /// Consumă codul de reducere pe server. Întoarce false dacă rezervarea nu mai poate continua.
  Future<bool> _redeemVoucherIfAny() async {
    _redeemedVoucher = null;
    _bookingCreated = false;
    final v = _voucher;
    if (v == null || _selectedLocation == null) return true;
    final amount = _tablePrice();
    if (!v.validFor(amount)) {
      setState(() => _voucher = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('vc.stale')), backgroundColor: Colors.orange));
      return false;
    }
    setState(() => _isLoading = true);
    final res = await VoucherService.redeem(venueId: _selectedLocation!.id, code: v.code, amount: amount);
    if (mounted) setState(() => _isLoading = false);
    if (!res.ok) {
      if (mounted) {
        setState(() => _voucher = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.errorMessage), backgroundColor: Colors.redAccent));
      }
      return false;
    }
    _redeemedVoucher = res;
    return true;
  }

  /// După încercarea de rezervare: dacă nu s-a creat nimic, eliberează folosirea codului.
  Future<void> _settleVoucher() async {
    final r = _redeemedVoucher;
    _redeemedVoucher = null;
    if (_bookingCreated) {
      if (mounted) setState(() => _voucher = null);
    } else if (r != null) {
      await VoucherService.release(r);
    }
  }

  Future<void> _createMatch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_needsTrainer && (_selectedTrainer == null || !_trainerAvailable(_selectedTrainer!))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('tr.pick_required')), backgroundColor: Colors.redAccent));
      return;
    }
    if (_venueHasRules && !_rulesAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('spec.rules_required')), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = userDoc.data() ?? {};
      final username = playerDisplayName(data, email: user.email, fallback: tr('common.unknown_player'));
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
      double baseAmount = 0.0; // doar prețul mesei, fără extra / bar (pentru rezervările recurente)
      if (_selectedLocation != null && _startHour != null && _endHour != null) {
        if (_venueData != null) {
          totalAmount = LevelUtils.calculateVenueBookingPrice(
            venueData: _venueData!,
            startHour: _startHour!,
            endHour: _endHour!,
                date: _selectedDate,
          );
        } else {
          totalAmount = LevelUtils.calculateTotalBookingPrice(
            _selectedLocation!.pricePerHourText,
            _startHour!,
            _endHour!,
          );
        }
        baseAmount = totalAmount;
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

      final double voucherDiscount = _redeemedVoucher?.discount ?? 0;
      if (voucherDiscount > 0) {
        totalAmount -= voucherDiscount;
        if (totalAmount < 0) totalAmount = 0;
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

      // Antrenor: prietenii bifați intră direct în lobby; lobby-ul poate fi închis pentru ceilalți.
      final bool trainerOn = _needsTrainer && _selectedTrainer != null;
      final bool lockLobby = trainerOn && _trainerLock;
      final List<Map<String, dynamic>> lobbyPlayers = [hostData];
      if (trainerOn) {
        for (final String fuid in _trainerFriendUids.take(_trainerPersons - 1)) {
          try {
            final fd = (await FirebaseFirestore.instance.collection('users').doc(fuid).get()).data() ?? {};
            lobbyPlayers.add({
              'uid': fuid,
              'username': playerDisplayName(fd, email: fd['email']?.toString(), fallback: tr('common.unknown_player')),
              'avatarUrl': fd['avatarUrl'],
              'rating': fd['rating'] ?? 0,
              'level': _levelNameFor((fd['rating'] as num?) ?? 0),
              'role': 'player',
            });
          } catch (_) {}
        }
      }
      final int effectiveMax = lockLobby
          ? (lobbyPlayers.length > _trainerPersons ? lobbyPlayers.length : _trainerPersons)
          : (lobbyPlayers.length > _maxPlayers ? lobbyPlayers.length : _maxPlayers);

      final matchData = {
        'hostUid': user.uid,
        'hostUsername': username,
        'hostAvatarUrl': avatarUrl,
        'hostRating': rating,
        'hostLevel': levelName,
        'joinedPlayers': lobbyPlayers,
        'joinedUids': lobbyPlayers.map((p) => p['uid']).toList(),
        'maxPlayers': effectiveMax,
        'visibility': lockLobby ? 'private' : _visibility.toLowerCase(),
        if (trainerOn) 'trainerId': _selectedTrainer!.id,
        if (trainerOn) 'trainerName': _selectedTrainer!.name,
        if (trainerOn) 'trainerPlan': _trainerPlan,
        if (trainerOn) 'trainerPersons': _trainerPersons,
        if (trainerOn) 'trainerLocked': lockLobby,
        'isFriendly': _matchType == 'Amical',
        'requireApproval': _requireApproval,
        'joinRequestUids': <String>[],
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
        'status': lobbyPlayers.length >= effectiveMax ? 'matched' : 'open',
        'price': totalAmount,
        'extraServices': _selectedExtraServices,
        'barOrderItems': finalBarOrder,
        if (_redeemedVoucher != null) 'voucherCode': _redeemedVoucher!.code,
        if (_redeemedVoucher != null) 'voucherDiscount': _redeemedVoucher!.discount,
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

      final newMatchId = await BookingService.createMatchChecked(matchData);
      if (newMatchId == null) {
        if (mounted) {
          setState(() => _selectedTable = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('cm.err_taken')),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      _bookingCreated = true;

      // Notificări (popup + email): sala primește rezervarea nouă, gazda confirmarea.
      final bookingArgs = {...NotificationService.matchArgs(matchData), 'player': username};
      await NotificationService.send(
        toUid: _selectedLocation!.id,
        type: 'booking_new',
        titleKey: 'n.booking_venue_title',
        bodyKey: 'n.booking_venue_body',
        args: bookingArgs,
        matchId: newMatchId,
      );
      await NotificationService.send(
        toUid: user.uid,
        allowSelf: true,
        type: 'booking_confirmed',
        titleKey: 'n.booking_host_title',
        bodyKey: 'n.booking_host_body',
        args: bookingArgs,
        matchId: newMatchId,
      );

      if (_recurring && !_paymentMethod.contains('Card') && !_needsTrainer) {
        await _createRecurring(matchData, newMatchId, baseAmount);
      }

      if (_needsTrainer && _selectedTrainer != null) {
        try {
          await TrainerService.requestSession(
            trainer: _selectedTrainer!,
            matchId: newMatchId,
            locationId: _selectedLocation!.id,
            locationName: _selectedLocation!.name,
            sport: _selectedSport,
            date: _selectedDate,
            startHour: _startHour!.toInt(),
            endHour: _endHour!.toInt(),
            plan: _trainerPlan,
            persons: _trainerPersons,
            group: [
              for (final p in lobbyPlayers.skip(1)) {'uid': (p['uid'] ?? '').toString(), 'name': (p['username'] ?? '').toString()},
            ],
          );
          // Prietenii adăugați în lobby află imediat (popup + email).
          for (final p in lobbyPlayers.skip(1)) {
            await NotificationService.send(
              toUid: (p['uid'] ?? '').toString(),
              type: 'lobby_added',
              titleKey: 'n.lobby_added_title',
              bodyKey: 'n.lobby_added_body',
              args: {...bookingArgs, 'host': username, 'trainer': _selectedTrainer!.name},
              matchId: newMatchId,
            );
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr('tr.requested', {'name': _selectedTrainer!.name})), backgroundColor: Colors.green),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr('tr.err_request', {'error': '$e'})), backgroundColor: Colors.orange),
            );
          }
        }
      }

      if (_wantsInvoice && mounted) {
        try {
          await InvoiceService.generateAndShareInvoice(
            matchId: newMatchId,
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
          SnackBar(content: Text(tr('cm.created')), backgroundColor: Colors.green),
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
          _requireApproval = true;
          _rulesAccepted = false;
          _selectedExtraServices.clear();
          _wantsInvoice = false;
          _invoiceCompanyController.clear();
          _invoiceCuiController.clear();
          _invoiceRegController.clear();
          _invoiceAddressController.clear();
          _invoiceEmailController.clear();
          _barInventory.clear();
          _selectedBarItems.clear();
          _trainers = [];
          _selectedTrainer = null;
          _needsTrainer = false;
          _trainerPlan = 'session';
          _trainerPersons = 1;
          _trainerLock = true;
          _trainerFriendUids.clear();
          _recurring = false;
          _recurringWeeks = 4;
          _voucher = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('cm.err_create', {'error': '$e'})), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Repetă rezervarea săptămânal: câte o rezervare nouă pe aceeași masă și oră, doar în săptămânile în care slotul e liber.
  Future<void> _createRecurring(Map<String, dynamic> base, String firstId, double weeklyPrice) async {
    final db = FirebaseFirestore.instance;
    final blocked = List<dynamic>.from(_venueData?['blockedDates'] ?? const []);
    int created = 1;
    final List<String> skipped = [];
    try {
      await db.collection('matches').doc(firstId).update({
        'recurringGroupId': firstId,
        'recurringWeek': 0,
        'recurringTotal': _recurringWeeks,
      });
      for (int w = 1; w < _recurringWeeks; w++) {
        final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate.add(Duration(days: 7 * w)));
        if (blocked.contains(dateStr)) {
          skipped.add(dateStr);
          continue;
        }
        final blk = VenueTools.blockFor(_venueData, dateStr, _startHour!, _endHour!, sport: _selectedSport);
        if (blk.allTables || (_selectedTable != null && blk.tables.contains(_selectedTable))) {
          skipped.add(dateStr);
          continue;
        }
        final copy = Map<String, dynamic>.from(base)
          ..remove('voucherCode')
          ..remove('voucherDiscount')
          ..['date'] = dateStr
          ..['price'] = weeklyPrice
          ..['extraServices'] = <String, dynamic>{}
          ..['barOrderItems'] = <Map<String, dynamic>>[]
          ..['recurringGroupId'] = firstId
          ..['recurringWeek'] = w
          ..['recurringTotal'] = _recurringWeeks
          ..['createdAt'] = FieldValue.serverTimestamp();
        final id = await BookingService.createMatchChecked(copy);
        if (id == null) {
          skipped.add(dateStr);
        } else {
          created++;
        }
      }
    } catch (e) {
      debugPrint('Eroare la rezervările recurente: $e');
    }
    if (!mounted) return;
    final msg = skipped.isEmpty
        ? tr('rec.done_all', {'n': '$created'})
        : tr('rec.done_some', {'created': '$created', 'total': '$_recurringWeeks', 'dates': skipped.join(', ')});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: skipped.isEmpty ? Colors.green : Colors.orange, duration: const Duration(seconds: 6)),
    );
  }

  Widget _buildRecurringOptions() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: _recurring,
            onChanged: (v) => setState(() => _recurring = v),
            title: Text(tr('rec.toggle'), style: TextStyle(color: AppColors.text, fontSize: 14)),
            subtitle: Text(tr('rec.toggle_sub'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
          if (_recurring)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(child: Text(tr('rec.weeks'), style: TextStyle(color: AppColors.text70, fontSize: 13))),
                  DropdownButton<int>(
                    value: _recurringWeeks,
                    dropdownColor: AppColors.card,
                    items: [
                      for (final n in const [2, 3, 4, 6, 8, 12])
                        DropdownMenuItem(value: n, child: Text(tr('rec.n_weeks', {'n': '$n'}))),
                    ],
                    onChanged: (v) => setState(() => _recurringWeeks = v ?? 4),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWaitlistButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.notifications_active_outlined, size: 18),
        label: Text(tr('wl.btn')),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: BorderSide(color: AppColors.accent),
        ),
        onPressed: _joinWaitlist,
      ),
    );
  }

  /// Lista de așteptare: când cineva anulează o masă din acest interval, jucătorul primește notificare.
  Future<void> _joinWaitlist() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedLocation == null || _startHour == null || _endHour == null) return;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final id = '${user.uid}_${_selectedLocation!.id}_${dateStr}_${_selectedSport}_${_startHour}_$_endHour'.replaceAll('/', '-');
    try {
      await FirebaseFirestore.instance.collection('waitlist').doc(id).set({
        'uid': user.uid,
        'venueId': _selectedLocation!.id,
        'venueName': _selectedLocation!.name,
        'sport': _selectedSport,
        'date': dateStr,
        'startHour': _startHour,
        'endHour': _endHour,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('wl.added')), backgroundColor: Colors.green),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('wl.failed')), backgroundColor: Colors.redAccent),
        );
      }
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
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
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
                color: AppColors.accent,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                  Text('$price RON', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.remove_circle_outline, color: AppColors.muted),
                onPressed: count > 0
                    ? () => setState(() => _selectedBarItems[id] = count - 1)
                    : null,
              ),
              Text('$count', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(
                icon: Icon(Icons.add_circle_outline, color: AppColors.accent),
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
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('cm.err_city')), backgroundColor: Colors.redAccent));
              return;
            }
            if (_selectedTableType == null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('cm.err_table_type')), backgroundColor: Colors.redAccent));
              return;
            }
          } else if (_currentStep == 1) {
            if (_startHour == null || _endHour == null || _selectedTable == null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('cm.err_slot')), backgroundColor: Colors.redAccent));
              return;
            }
            // Mesele sunt deja dezactivate în UI dacă există un turneu sau un blocaj,
            // astfel încât utilizatorul nu poate selecta o masă indisponibilă și nu poate continua.
          } else if (_currentStep == 2) {
             // Pasul „Echipamente, bar și antrenor": dacă ai cerut antrenor, trebuie ales unul disponibil.
            if (_needsTrainer && (_selectedTrainer == null || !_trainerAvailable(_selectedTrainer!))) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('tr.pick_required')), backgroundColor: Colors.redAccent));
              return;
            }
          } else if (_currentStep == 3) {
            // Pasul „Plată": doar validăm; rezervarea se confirmă la pasul „Rezumat".
            final String? invoiceError = _invoiceError();
            if (invoiceError != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(invoiceError), backgroundColor: Colors.redAccent),
              );
              return;
            }
          } else if (_currentStep == 4) {
            if (!await _redeemVoucherIfAny()) return;
            if (_paymentMethod.contains('Card')) {
              double amount = _tablePrice() - (_redeemedVoucher?.discount ?? 0);
              
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

              // O rezervare gratuită (cod de 100%) nu trece prin plata cu cardul.
              final paymentSuccess = amount < 1
                  ? true
                  : await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PaymentScreen(
                        amount: amount,
                        venueId: _selectedLocation!.id,
                        destinationAccountId: _selectedLocation!.stripeAccountId,
                      )),
                    );

              if (paymentSuccess == true) {
                await _createMatch();
              }
            } else {
              await _createMatch();
            }
            await _settleVoucher();
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
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppColors.text, strokeWidth: 2))
                        : Text(isLastStep ? tr('cm.confirm') : tr('common.continue').toUpperCase()),
                  ),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: details.onStepCancel,
                      child: Text(tr('common.back').toUpperCase()),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          Step(
            title: Text(tr('cm.step1_title')),
            subtitle: Text(tr('cm.step1_sub')),
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
                if (_selectedCity != null)
                  VenueFilterBar(
                    filters: _venueFilters,
                    requestLocation: _requestUserLocation,
                    onChanged: (f) => setState(() => _venueFilters = f),
                  ),
                DropdownButtonFormField<PingPongLocation>(
                  initialValue: _selectedLocation,
                  decoration: InputDecoration(labelText: venueFieldLabel(_selectedSport), prefixIcon: Icon(Icons.sports_tennis)),
                  items: _filteredLocations.map((loc) => DropdownMenuItem(value: loc, child: _venueItem(loc))).toList(),
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
                      _trainers = [];
                      _selectedTrainer = null;
                      _needsTrainer = false;
                      _trainerPersons = 1;
                      _trainerFriendUids.clear();
                      _rulesAccepted = false;
                    });
                    if (val != null) {
                      _loadBarInventory(val.id);
                      _loadTrainers(val.id);
                    }
                  },
                ),
                if (_selectedCity != null && _filteredLocations.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _venueFilters.isActive
                        ? tr('vf.no_match')
                        : tr('cm.no_venues', {'sport': sportLabel(_selectedSport), 'city': _selectedCity!}),
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ],
                if (_selectedLocation != null) ...[
                  if (_selectedLocation!.offersSubscription) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.star, color: AppColors.accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('cm.sub_title'), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                                Text(tr('cm.sub_desc', {'price': '${_selectedLocation!.subscriptionPrice}'}), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('cm.sub_soon'))));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(tr('cm.buy')),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_selectedLocation!.extraServices.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(tr('cm.extras'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    ..._selectedLocation!.extraServices.map((service) {
                      final String name = service['name'] ?? '';
                      final double price = (service['price'] as num).toDouble();
                      final int count = _selectedExtraServices[name] ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.card2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
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
                                    Text(name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                                    Text(tr('cm.per_piece', {'price': '$price'}), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                  ],
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(Icons.remove_circle_outline, color: AppColors.muted),
                                  onPressed: count > 0
                                      ? () => setState(() => _selectedExtraServices[name] = count - 1)
                                      : null,
                                ),
                                Text('$count', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                                IconButton(
                                  icon: Icon(Icons.add_circle_outline, color: AppColors.accent),
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
                  Text(tr('cm.table_type'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    tr('cm.type_counts', {'i': '${_selectedLocation!.indoorTables}', 'o': '${_selectedLocation!.outdoorTables}'}),
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
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
                                  ? AppColors.accent.withValues(alpha: 0.2)
                                  : _getIndoorCount() == 0
                                      ? Colors.grey.withValues(alpha: 0.1)
                                      : AppColors.card2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _selectedTableType == 'indoor'
                                    ? AppColors.accent
                                    : _getIndoorCount() == 0
                                        ? Colors.grey.withValues(alpha: 0.3)
                                        : AppColors.border700,
                                width: _selectedTableType == 'indoor' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.house_outlined,
                                  color: _selectedTableType == 'indoor'
                                      ? AppColors.accent
                                      : _getIndoorCount() == 0
                                          ? AppColors.muted2
                                          : AppColors.text70,
                                  size: 28,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  tr('cm.indoor'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTableType == 'indoor'
                                        ? AppColors.accent
                                        : _getIndoorCount() == 0
                                            ? AppColors.muted2
                                            : AppColors.text,
                                  ),
                                ),
                                Text(
                                  tr('cm.n_tables', {'n': '${_getIndoorCount()}'}),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _getIndoorCount() == 0
                                        ? AppColors.muted2
                                        : AppColors.muted,
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
                                  ? AppColors.good.withValues(alpha: 0.2)
                                  : _getOutdoorCount() == 0
                                      ? Colors.grey.withValues(alpha: 0.1)
                                      : AppColors.card2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _selectedTableType == 'outdoor'
                                    ? AppColors.good
                                    : _getOutdoorCount() == 0
                                        ? Colors.grey.withValues(alpha: 0.3)
                                        : AppColors.border700,
                                width: _selectedTableType == 'outdoor' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.park_outlined,
                                  color: _selectedTableType == 'outdoor'
                                      ? AppColors.good
                                      : _getOutdoorCount() == 0
                                          ? AppColors.muted2
                                          : AppColors.text70,
                                  size: 28,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  tr('cm.outdoor'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTableType == 'outdoor'
                                        ? AppColors.good
                                        : _getOutdoorCount() == 0
                                            ? AppColors.muted2
                                            : AppColors.text,
                                  ),
                                ),
                                Text(
                                  tr('cm.n_tables', {'n': '${_getOutdoorCount()}'}),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _getOutdoorCount() == 0
                                        ? AppColors.muted2
                                        : AppColors.muted,
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
                    Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        tr('cm.select_type_hint'),
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                if (_selectedLocation != null &&
                    (_currentSpecs != null || _selectedLocation!.venueRules.trim().isNotEmpty)) ...[
                  Text(tr('spec.details'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SportSpecsCard(
                    sport: _selectedSport,
                    specs: _currentSpecs,
                    venueRules: _selectedLocation!.venueRules,
                    showTitle: false,
                  ),
                  const SizedBox(height: 8),
                ],
                Text(tr('cm.match_settings'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Builder(builder: (_) {
                        final List<int> opts = _playerOptions;
                        if (!opts.contains(_maxPlayers)) _maxPlayers = opts.first;
                        return DropdownButtonFormField<int>(
                          key: ValueKey('fmt_${_selectedSport}_${_selectedLocation?.id}_${opts.join(',')}'),
                          initialValue: _maxPlayers,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: tr('cm.format'), prefixIcon: const Icon(Icons.people)),
                          items: [
                            for (final n in opts)
                              DropdownMenuItem(value: n, child: Text(SportSpecs.playerOptionLabel(_selectedSport, n), overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) => setState(() => _maxPlayers = val ?? opts.first),
                        );
                      }),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _visibility,
                        decoration: InputDecoration(labelText: tr('cm.visibility'), prefixIcon: Icon(Icons.visibility)),
                        items: [
                          DropdownMenuItem(value: 'Public', child: Text(tr('cm.vis_public'))),
                          DropdownMenuItem(value: 'Privat', child: Text(tr('cm.vis_private'))),
                        ],
                        onChanged: (val) => setState(() => _visibility = val ?? 'Public'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _matchType,
                  decoration: InputDecoration(labelText: tr('cm.match_type'), prefixIcon: Icon(Icons.emoji_events_outlined)),
                  items: [
                    DropdownMenuItem(value: 'Competitiv', child: Text(tr('cm.type_competitive'))),
                    DropdownMenuItem(value: 'Amical', child: Text(tr('cm.type_friendly'))),
                  ],
                  onChanged: (val) => setState(() => _matchType = val ?? 'Competitiv'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('cm.require_approval'), style: TextStyle(color: AppColors.text, fontSize: 14)),
                  subtitle: Text(tr('cm.require_approval_sub'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  value: _requireApproval,
                  onChanged: (v) => setState(() => _requireApproval = v),
                ),
              ],
            ),
          ),
          Step(
            title: Text(tr('cm.step2_title')),
            subtitle: Text(tr('cm.step2_sub')),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: _selectedLocation == null
                ? Text(tr('cm.pick_venue_first'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('cm.booking_date'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
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
                          icon: Icon(Icons.calendar_month, color: AppColors.accent),
                          label: Text(
                            DateFormat('dd MMM yyyy').format(_selectedDate),
                            style: TextStyle(color: AppColors.text, fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                            side: BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
                            alignment: Alignment.centerLeft,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(tr('cm.pick_hours'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableHours.map((h) {
                          final isSelected = _selectedHours.contains(h);
                          return ChoiceChip(
                            label: Text(_formatHour(h)),
                            selected: isSelected,
                            selectedColor: AppColors.accent,
                            labelStyle: TextStyle(color: isSelected ? AppColors.onAccent : AppColors.text),
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
                      Text(tr('cm.tables_plan'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.text)),
                      Text(tr('cm.pick_table'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      const SizedBox(height: 16),
                      if (_isLoading) const Center(child: CircularProgressIndicator())
                      else if (_startHour == null || _endHour == null)
                        Center(child: Text(tr('cm.pick_hours_first'), style: TextStyle(color: AppColors.muted)))
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.card.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.card2, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.05),
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
                                    Text(
                                      'PLAN CAMERĂ CLUB',
                                      style: TextStyle(color: AppColors.text38, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 2),
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
                                        _buildLegendItem(tr('cm.st_free'), AppColors.good),
                                        _buildLegendItem(tr('cm.legend_selected'), AppColors.accent),
                                        _buildLegendItem(tr('cm.legend_busy'), AppColors.bad),
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

                                    String statusText = tr('cm.st_free');
                                    if (_isDayBlockedFlag) {
                                      statusText = tr('cm.st_closed');
                                    } else if (_overlappingTournament != null) {
                                      statusText = tr('cm.st_tournament');
                                    } else if (isReserved) {
                                      statusText = tr('cm.st_busy');
                                    }

                                    return GestureDetector(
                                      onTap: isTableBlocked ? null : () {
                                        setState(() => _selectedTable = tableId);
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        decoration: BoxDecoration(
                                          color: isTableBlocked ? Colors.red.withValues(alpha: 0.15) : (isSelected ? AppColors.accent.withValues(alpha: 0.3) : AppColors.card2),
                                          border: Border.all(
                                            color: isTableBlocked ? Colors.redAccent : (isSelected ? AppColors.accent : AppColors.border),
                                            width: 1.5,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.table_restaurant, size: 20, color: isTableBlocked ? Colors.redAccent : (isSelected ? AppColors.accent : AppColors.muted)),
                                              const SizedBox(height: 4),
                                              Text(tr('cm.table_n', {'n': '$tableId'}), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isTableBlocked ? Colors.redAccent : AppColors.text)),
                                              Text(statusText, style: TextStyle(fontSize: 10, color: isTableBlocked ? Colors.redAccent : AppColors.muted)),
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
                      if (_reservedTables.isNotEmpty && _startHour != null && _endHour != null) _buildWaitlistButton(),
                    ],
                  ),
          ),
          Step(
            title: Text(tr('cm.step3_title')),
            subtitle: Text(tr('cm.step3_sub')),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTrainerSection(),
                const SizedBox(height: 12),
                _barInventory.isEmpty
                ? Text(tr('cm.no_menu'), style: TextStyle(color: AppColors.muted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_barInventory.any((item) => item['category'] == 'Echipament')) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(tr('cm.equipment'), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        ..._barInventory.where((item) => item['category'] == 'Echipament').map((item) => _buildInventoryRow(item)).toList(),
                        const SizedBox(height: 16),
                      ],
                      if (_barInventory.any((item) => item['category'] != 'Echipament')) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(tr('cm.drinks'), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        ..._barInventory.where((item) => item['category'] != 'Echipament').map((item) => _buildInventoryRow(item)).toList(),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          Step(
            title: Text(tr('cm.step4_title')),
            subtitle: Text(tr('cm.step4_sub')),
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
                date: _selectedDate,
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
                    totalAmount -= _voucherDiscount;
                    if (totalAmount < 0) totalAmount = 0;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.card2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: AppColors.accent, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$priceInfo\nTotal de plată: ${totalAmount.toStringAsFixed(0)} lei (achitat integral de Host)',
                              style: TextStyle(color: AppColors.text, fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                ),
                Text(tr('cm.payment_method'), style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.muted)),
                RadioListTile(
                  title: Text(tr('cm.pay_cash')),
                  activeColor: AppColors.accent,
                  value: 'Cash la locație',
                  groupValue: _paymentMethod,
                  onChanged: (val) => setState(() => _paymentMethod = val.toString()),
                ),
                RadioListTile(
                  title: Text(tr('cm.pay_card')),
                  activeColor: AppColors.accent,
                  value: 'Card în aplicație',
                  groupValue: _paymentMethod,
                  onChanged: (val) => setState(() {
                    _paymentMethod = val.toString();
                    _recurring = false; // plata cu cardul e pe o singură rezervare
                  }),
                ),
                if (_venueData != null && _selectedLocation != null && _selectedLocation!.isPublic != true)
                  VoucherField(
                    venueId: _selectedLocation!.id,
                    amount: _tablePrice,
                    applied: _voucher,
                    onChanged: (v) => setState(() => _voucher = v),
                  ),
                if (!_paymentMethod.contains('Card') && !_needsTrainer && _selectedTable != null) _buildRecurringOptions(),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: Text(tr('cm.want_invoice'), style: TextStyle(color: AppColors.text, fontSize: 14)),
                  activeColor: AppColors.accent,
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
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _invoiceCompanyController,
                          decoration: InputDecoration(labelText: tr('cm.inv_company'), isDense: true),
                          style: TextStyle(fontSize: 13, color: AppColors.text),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _invoiceCuiController,
                          decoration: InputDecoration(labelText: tr('cm.inv_cui'), isDense: true),
                          style: TextStyle(fontSize: 13, color: AppColors.text),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _invoiceRegController,
                          decoration: InputDecoration(labelText: tr('cm.inv_reg'), isDense: true),
                          style: TextStyle(fontSize: 13, color: AppColors.text),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _invoiceAddressController,
                          decoration: InputDecoration(labelText: tr('cm.inv_address'), isDense: true),
                          style: TextStyle(fontSize: 13, color: AppColors.text),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _invoiceEmailController,
                          decoration: InputDecoration(labelText: tr('cm.inv_email'), isDense: true),
                          style: TextStyle(fontSize: 13, color: AppColors.text),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Step(
            title: Text(tr('cm.step5_title')),
            subtitle: Text(tr('cm.step5_sub')),
            isActive: _currentStep >= 4,
            content: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow(Icons.location_on, tr('cm.sum_location'), '${_selectedLocation?.name ?? '-'} (${_selectedCity ?? '-'})'),
                  _summaryRow(Icons.calendar_today, tr('cm.sum_date'), DateFormat('dd MMM yyyy').format(_selectedDate)),
                  _summaryRow(Icons.access_time, tr('cm.sum_hours'), '${_startHour != null ? formatHour(_startHour) : '-'} - ${_endHour != null ? formatHour(_endHour) : '-'} (${tr('cm.hours_count', {'n': ((_endHour ?? 0) - (_startHour ?? 0)).toString()})})'),
                  _summaryRow(Icons.table_restaurant, tr('cm.sum_table'), _selectedTable != null ? tr('cm.table_n', {'n': '$_selectedTable'}) + ' (${_selectedTableType ?? 'N/A'})' : '-'),
                  _summaryRow(Icons.house_outlined, tr('cm.sum_type'), _selectedTableType == 'indoor' ? '🏠 ${tr('cm.indoor')}' : _selectedTableType == 'outdoor' ? '🌳 ${tr('cm.outdoor')}' : '-'),
                  Builder(builder: (context) {
                    List<String> barDesc = [];
                    for (var item in _barInventory) {
                      int count = _selectedBarItems[item['id']] ?? 0;
                      if (count > 0) {
                         barDesc.add('${item['name']} x$count');
                      }
                    }
                    if (barDesc.isEmpty) return const SizedBox.shrink();
                    return _summaryRow(Icons.local_cafe, tr('cm.sum_bar'), barDesc.join('\n'));
                  }),
                  if (_needsTrainer && _selectedTrainer != null)
                    _summaryRow(Icons.sports, tr('tr.sum_trainer'), '${_selectedTrainer!.name} (${_trainerPriceText(_selectedTrainer!)})'),
                  if (_needsTrainer && _selectedTrainer != null)
                    _summaryRow(Icons.event_repeat, tr('tr.sum_plan'), _trainerPlan == 'month' ? tr('tr.plan_month') : tr('tr.plan_session')),
                  if (_needsTrainer && _selectedTrainer != null)
                    _summaryRow(
                      Icons.groups,
                      tr('tr.sum_persons'),
                      _trainerPersons == 1 ? tr('tr.persons_one') : tr('tr.persons_many', {'n': '$_trainerPersons'}),
                    ),
                  if (_needsTrainer && _selectedTrainer != null)
                    _summaryRow(Icons.lock_outline, tr('tr.sum_lobby'), _trainerLock ? tr('tr.sum_lobby_closed') : tr('tr.sum_lobby_open')),
                  Divider(color: AppColors.muted),
                  _summaryRow(Icons.emoji_events, tr('cm.match_type'), _matchType == 'Amical' ? tr('match.friendly') : tr('match.competitive')),
                  _summaryRow(Icons.payment, tr('cm.sum_payment'), _paymentMethod.contains('Card') ? tr('cm.pay_card_short') : tr('cm.pay_cash')),
                  if (_recurring && !_paymentMethod.contains('Card') && !_needsTrainer)
                    _summaryRow(Icons.event_repeat, tr('rec.sum'), tr('rec.sum_val', {'n': '$_recurringWeeks'})),
                  if (_voucherDiscount > 0)
                    _summaryRow(
                      Icons.confirmation_number_outlined,
                      tr('vc.sum', {'code': _voucher!.code}),
                      '-${_voucherDiscount.toStringAsFixed(_voucherDiscount % 1 == 0 ? 0 : 2)} RON',
                    ),
                  _summaryRow(
                    Icons.monetization_on,
                    tr('cm.sum_total'),
                    '${_selectedLocation != null && _startHour != null && _endHour != null
                        ? ((_venueData != null
                            ? LevelUtils.calculateVenueBookingPrice(
                                venueData: _venueData!,
                                startHour: _startHour!,
                                endHour: _endHour!,
                date: _selectedDate,
                              )
                            : LevelUtils.calculateTotalBookingPrice(
                                _selectedLocation!.pricePerHourText,
                                _startHour!,
                                _endHour!,
                              )) - _voucherDiscount).toStringAsFixed(0)
                        : ((_endHour ?? 0) - (_startHour ?? 0)) * 20} RON',
                  ),
                  if (_venueHasRules) ...[
                    Divider(color: AppColors.muted),
                    SportSpecsCard(
                      sport: _selectedSport,
                      specs: _currentSpecs,
                      venueRules: _selectedLocation!.venueRules,
                      showTitle: false,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.accent,
                      checkColor: Colors.black,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(tr('spec.accept_rules'), style: TextStyle(color: AppColors.text, fontSize: 14)),
                      value: _rulesAccepted,
                      onChanged: (v) => setState(() => _rulesAccepted = v ?? false),
                    ),
                  ],
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
          Icon(icon, color: AppColors.accent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: AppColors.text, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSportSelector() {
    final sports = sportOptions();
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
                selectedColor: AppColors.accent,
                labelStyle: TextStyle(color: isSelected ? AppColors.onAccent : AppColors.text),
                backgroundColor: AppColors.card2,
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
        Text(label, style: TextStyle(color: AppColors.text70, fontSize: 11)),
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
      final tableName = table['name'] ?? tr('cm.table_n', {'n': '$tableId'});
      final isReserved = _reservedTables.contains(tableId);
      final isTrainingBlocked = _isTableReservedForTraining(table, _venueTrainingConfig);
      final isTableBlocked = isReserved || isTrainingBlocked || _isDayBlockedFlag || _overlappingTournament != null;
      final isSelected = _selectedTable == tableId;

      String statusText = tr('cm.st_free');
      if (_isDayBlockedFlag) {
        statusText = tr('cm.st_closed');
      } else if (_overlappingTournament != null) {
        statusText = tr('cm.st_tournament');
      } else if (isReserved) {
        statusText = tr('cm.st_busy');
      } else if (isTrainingBlocked) {
        statusText = tr('cm.st_training');
      }

      final Color blockedColor = isTrainingBlocked ? Colors.purpleAccent : Colors.redAccent;
      final Color blockedBgColor = isTrainingBlocked ? Colors.purple.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15);
      final Color activeBorderColor = isTableBlocked ? blockedColor : (isSelected ? AppColors.accent : AppColors.good);
      final Color activeBgColor = isTableBlocked ? blockedBgColor : (isSelected ? AppColors.accent.withValues(alpha: 0.3) : AppColors.good.withValues(alpha: 0.1));
      final Color contentColor = isTableBlocked ? blockedColor : (isSelected ? AppColors.accent : AppColors.good);

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
                Text(tableName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isTableBlocked ? blockedColor : AppColors.text), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                Text(statusText, style: TextStyle(fontSize: 9, color: isTableBlocked ? blockedColor : AppColors.muted)),
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
