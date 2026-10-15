import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../data/sports.dart';
import '../services/billing_service.dart';
import '../widgets/sport_specs_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// dart:html is web-only and breaks Android/iOS builds
import 'package:url_launcher/url_launcher.dart';
import 'create_match_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/rating_badge.dart';
import '../data/city_coords.dart';
import '../services/location_service.dart';

LatLng? _coordsForCity(String? city) => coordsForCity(city);

// ────────────────────────────────────────────────────────────────────────────

class _VenueMarker {
  final String id;
  final String name;
  final String city;
  final String address;
  final String? priceText;
  final LatLng coords;
  final bool isPublic;
  final List<String> supportedSports;
  final Map<String, dynamic> sportSpecs;
  final String venueRules;
  final double? rating;
  final int ratingCount;

  const _VenueMarker({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    required this.priceText,
    required this.coords,
    this.isPublic = false,
    this.supportedSports = const ['ping_pong'],
    this.sportSpecs = const {},
    this.venueRules = '',
    this.rating,
    this.ratingCount = 0,
  });
}

class VenueMapScreen extends StatefulWidget {
  const VenueMapScreen({super.key});

  @override
  State<VenueMapScreen> createState() => _VenueMapScreenState();
}

class _VenueMapScreenState extends State<VenueMapScreen> {
  final MapController _mapController = MapController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<_VenueMarker> _markers = [];
  _VenueMarker? _selected;
  bool _loading = true;
  String _filterCity = '';
  List<String> _selectedSports = [];
  LatLng? _userLocation;
  String _drawerSearchQuery = '';
  bool _onlyVisibleInBounds = true;

  @override
  void initState() {
    super.initState();
    _loadVenues();
    _getUserLocation();
  }

  Future<void> _getUserLocation({bool forceRefresh = false}) async {
    final p = await LocationService.current(forceRefresh: forceRefresh);
    if (mounted && p != null) setState(() => _userLocation = p);
  }

  double _kmTo(_VenueMarker m) => const Distance().distance(_userLocation!, m.coords) / 1000;

  String _kmLabel(double km) => km < 1 ? '${(km * 1000).round()} m' : '${km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0)} km';

  Future<void> _loadVenues() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('venues').get();
      final result = <_VenueMarker>[];
      final bool subscriptionRequired = await BillingService.subscriptionRequired();

      for (final doc in snap.docs) {
        final data = doc.data();
        if (!BillingService.venueVisible(data, subscriptionRequired)) continue; // fără abonament activ
        final city    = (data['city']    as String?)?.trim() ?? '';
        final address = (data['address'] as String?)?.trim() ?? '';
        final name    = (data['venueName'] as String?)?.trim() ?? 'Sală necunoscută';
        final price   = data['pricePerHourText'] as String?;

        final isPublic = data['isPublic'] as bool? ?? false;
        final supportedSports = List<String>.from(data['supportedSports'] ?? ['ping_pong']);
        final Map<String, dynamic> sportSpecs = {};
        final rawSpecs = data['sportSpecs'];
        if (rawSpecs is Map) {
          rawSpecs.forEach((k, v) {
            if (v is Map) sportSpecs[k.toString()] = Map<String, dynamic>.from(v);
          });
        }

        LatLng finalCoords;
        if (data.containsKey('latitude') && data.containsKey('longitude')) {
          finalCoords = LatLng(
            (data['latitude'] as num).toDouble(),
            (data['longitude'] as num).toDouble(),
          );
        } else {
          final coords = _coordsForCity(city);
          if (coords == null) continue; // skip venues with unknown city

          // Add a tiny random offset so venues in the same city don't overlap
          final offset = _markerOffset(result.length);
          finalCoords = LatLng(
            coords.latitude  + offset.$1,
            coords.longitude + offset.$2,
          );
        }

        result.add(_VenueMarker(
          id: doc.id,
          name: name,
          city: city,
          address: address,
          priceText: price,
          isPublic: isPublic,
          supportedSports: supportedSports,
          sportSpecs: sportSpecs,
          venueRules: (data['venueRules'] ?? '').toString(),
          rating: (data['rating'] as num?)?.toDouble(),
          ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
          coords: finalCoords,
        ));
      }

      if (mounted) {
        setState(() {
          _markers = result;
          _loading = false;
        });

        // Zoom to Romania center by default
        if (result.isNotEmpty) {
          _mapController.move(const LatLng(45.9432, 24.9668), 6.5);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Tiny offset so multiple venues in the same city don't stack exactly
  (double, double) _markerOffset(int index) {
    const offsets = [
      (0.00, 0.00), (0.01, 0.01), (-0.01, 0.01),
      (0.01, -0.01), (-0.01, -0.01), (0.02, 0.00),
    ];
    return offsets[index % offsets.length];
  }

  List<_VenueMarker> get _filteredMarkers {
    Iterable<_VenueMarker> filtered = _markers;
    if (_filterCity.isNotEmpty) {
      filtered = filtered.where((m) => m.city.toLowerCase().contains(_filterCity.toLowerCase()));
    }
    if (_selectedSports.isNotEmpty) {
      filtered = filtered.where((m) => _selectedSports.any((s) => m.supportedSports.contains(s)));
    }
    return filtered.toList();
  }

  List<_VenueMarker> get _drawerFilteredMarkers {
    Iterable<_VenueMarker> result = _markers;

    if (_drawerSearchQuery.isNotEmpty) {
      final query = _drawerSearchQuery.toLowerCase().trim();
      result = result.where((m) =>
          m.name.toLowerCase().contains(query) ||
          m.city.toLowerCase().contains(query) ||
          m.address.toLowerCase().contains(query));
    } else if (_onlyVisibleInBounds) {
      try {
        final bounds = _mapController.camera.visibleBounds;
        result = result.where((m) => bounds.contains(m.coords));
      } catch (_) {
        // Camera bounds not ready yet
      }
    }

    final list = result.toList();
    // Cu locația cunoscută, cele mai apropiate săli apar primele.
    if (_userLocation != null) list.sort((a, b) => _kmTo(a).compareTo(_kmTo(b)));
    return list;
  }

  void _moveTo(_VenueMarker m) {
    setState(() => _selected = m);
    _mapController.move(m.coords, 13.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: Text(
          tr('map.title'),
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.accent),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: [
                TextField(
                  style: TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    hintText: 'Filtrează după oraș...',
                    hintStyle: TextStyle(color: AppColors.text38),
                    prefixIcon: Icon(Icons.search, color: AppColors.accent),
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.accent, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.card3, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.accent, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (val) => setState(() {
                    _filterCity = val;
                    _selected = null;
                  }),
                ),
                const SizedBox(height: 8),
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
                          labelStyle: TextStyle(color: isSelected ? AppColors.onAccent : AppColors.text, fontSize: 12),
                          backgroundColor: AppColors.card2,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                _selectedSports.add(sport['id']!);
                              } else {
                                _selectedSports.remove(sport['id']);
                              }
                              _selected = null;
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
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Stack(
              children: [
                // ── OpenStreetMap ──────────────────────────────────────────
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(45.9432, 24.9668),
                    initialZoom: 6.5,
                    onTap: (_, __) => setState(() => _selected = null),
                    onPositionChanged: (_, __) {
                      if (mounted) setState(() {});
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.pingpongplayhub.app',
                    ),
                    MarkerLayer(
                      markers: [
                        ..._filteredMarkers.map((m) => _buildMarker(m)),
                        if (_userLocation != null)
                          Marker(
                            point: _userLocation!,
                            width: 30,
                            height: 30,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.blue, width: 2),
                              ),
                              child: const Center(
                                child: Icon(Icons.my_location, color: Colors.blue, size: 16),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // ── Panel info sală selectată ──────────────────────────────
                if (_selected != null)
                  Positioned(
                    bottom: 16,
                    left: 12,
                    right: 12,
                    child: _buildInfoCard(_selected!),
                  ),

                // ── Badge "X săli găsite" ──────────────────────────────────
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.card.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.accent, width: 1),
                    ),
                    child: Text(
                      '${_filteredMarkers.length} sali găsite',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),

                // ── Buton "Centrare pe România" ────────────────────────────
                Positioned(
                  top: 50,
                  right: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.card.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.4), width: 1),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.zoom_out_map, color: AppColors.accent, size: 20),
                      tooltip: 'Centrare România',
                      onPressed: () {
                        _mapController.move(const LatLng(45.9432, 24.9668), 6.5);
                        setState(() => _selected = null);
                      },
                    ),
                  ),
                ),

                // ── Listă oraşe cu săli (drawer lateral) ──────────────────
                if (_markers.isEmpty && !_loading)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_off, color: AppColors.accent, size: 48),
                          SizedBox(height: 16),
                          Text(
                            'Nicio sală înregistrată\ncu locație validă.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.text70, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

      // ── Drawer lateral cu lista sălilor ─────────────────────────────────
      endDrawer: _buildVenueList(),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'myLocationBtn',
            mini: true,
            backgroundColor: AppColors.card,
            foregroundColor: Colors.blue,
            onPressed: () async {
              if (_userLocation == null) await _getUserLocation(forceRefresh: true);
              if (!mounted) return;
              if (_userLocation == null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('vf.loc_denied')), backgroundColor: Colors.orange));
                return;
              }
              _mapController.move(_userLocation!, 13.0);
              setState(() => _selected = null);
            },
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'listBtn',
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.black,
            icon: const Icon(Icons.list),
            label: const Text('Listă Săli', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
    );
  }

  Marker _buildMarker(_VenueMarker m) {
    final isSelected = _selected == m;
    final markerColor = m.isPublic ? AppColors.good : AppColors.accent;
    final markerIcon = m.isPublic ? Icons.park : Icons.sports_tennis;

    return Marker(
      point: m.coords,
      width: isSelected ? 48 : 38,
      height: isSelected ? 48 : 38,
      child: GestureDetector(
        onTap: () => _moveTo(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? markerColor : AppColors.card,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? AppColors.text : markerColor,
              width: isSelected ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: markerColor.withValues(alpha: isSelected ? 0.7 : 0.4),
                blurRadius: isSelected ? 16 : 8,
                spreadRadius: isSelected ? 2 : 0,
              ),
            ],
          ),
          child: Icon(
            markerIcon,
            color: isSelected ? AppColors.onAccent : markerColor,
            size: isSelected ? 24 : 18,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(_VenueMarker m) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.2),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.sports_tennis, color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            m.city,
                            style: TextStyle(color: AppColors.accent, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        RatingBadge(rating: m.rating, count: m.ratingCount),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: AppColors.text54, size: 20),
                onPressed: () => setState(() => _selected = null),
              ),
            ],
          ),
          if (m.address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on, color: AppColors.text38, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    m.address,
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
          if (m.isPublic) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.good.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('Locație Publică - Gratuit', style: TextStyle(color: AppColors.good, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ] else if (m.priceText != null && m.priceText!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.attach_money, color: AppColors.text38, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    m.priceText!,
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
          if (m.supportedSports.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: m.supportedSports.map((sport) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.card2,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    sport.toUpperCase(),
                    style: TextStyle(color: AppColors.muted, fontSize: 10),
                  ),
                );
              }).toList(),
            ),
          ],
          if (m.sportSpecs.isNotEmpty || m.venueRules.trim().isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                iconColor: AppColors.accent,
                collapsedIconColor: AppColors.text54,
                title: Text(tr('spec.details'), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 14)),
                children: [
                  for (final sport in m.supportedSports)
                    if (m.sportSpecs[sport] != null)
                      SportSpecsCard(sport: sport, specs: m.sportSpecs[sport] as Map<String, dynamic>?),
                  if (m.venueRules.trim().isNotEmpty)
                    SportSpecsCard(sport: 'ping_pong', specs: null, venueRules: m.venueRules, rulesOnly: true),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (!m.isPublic) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateMatchScreen(
                        preselectedCity: m.city,
                        preselectedVenueId: m.id,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.sports_tennis, size: 18),
                label: const Text('Rezervă aici', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${m.coords.latitude},${m.coords.longitude}');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.directions, size: 18),
              label: const Text('Obține Direcții', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: m.isPublic ? AppColors.good : AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: m.isPublic ? AppColors.good : AppColors.accent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVenueList() {
    final list = _drawerFilteredMarkers;
    return Drawer(
      backgroundColor: AppColors.bg,
      child: Column(
        children: [
          // Drawer Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border(bottom: BorderSide(color: AppColors.accent, width: 1)),
            ),
            child: Row(
              children: [
                Icon(Icons.sports_tennis, color: AppColors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('map.count', {'n': '${list.length}'}),
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Drawer Search
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: AppColors.card,
            child: TextField(
              style: TextStyle(color: AppColors.text, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Caută după nume sau oraș...',
                hintStyle: TextStyle(color: AppColors.text38, fontSize: 12),
                prefixIcon: Icon(Icons.search, color: AppColors.accent, size: 16),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.accent, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.card3, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.accent, width: 1.2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (val) => setState(() {
                _drawerSearchQuery = val;
              }),
            ),
          ),

          // Drawer Bounds Filter Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: AppColors.card,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.zoom_in, color: AppColors.text54, size: 14),
                    SizedBox(width: 8),
                    Text(
                      'Doar cele vizibile pe hartă',
                      style: TextStyle(color: AppColors.text70, fontSize: 11),
                    ),
                  ],
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _onlyVisibleInBounds,
                    activeThumbColor: AppColors.accent,
                    activeTrackColor: AppColors.accent.withValues(alpha: 0.3),
                    inactiveThumbColor: AppColors.muted,
                    inactiveTrackColor: AppColors.text10,
                    onChanged: (val) => setState(() {
                      _onlyVisibleInBounds = val;
                    }),
                  ),
                ),
              ],
            ),
          ),

          // Divider below options
          Container(
            height: 1,
            color: AppColors.accent.withValues(alpha: 0.3),
          ),

          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'Nicio sală găsită.\n(Încearcă să dezactivezi filtrul de hartă sau să cauți alt oraș)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.text54, fontSize: 12),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    separatorBuilder: (_, __) => Divider(
                      color: AppColors.card3,
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                    itemBuilder: (context, i) {
                      final m = list[i];
                      final isSelected = _selected == m;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (m.isPublic ? AppColors.good : AppColors.accent).withValues(alpha: 0.15)
                                : AppColors.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? (m.isPublic ? AppColors.good : AppColors.accent)
                                  : AppColors.card3,
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            m.isPublic ? Icons.park : Icons.sports_tennis,
                            color: isSelected ? (m.isPublic ? AppColors.good : AppColors.accent) : AppColors.text38,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                m.name,
                                style: TextStyle(
                                  color: isSelected ? (m.isPublic ? AppColors.good : AppColors.accent) : AppColors.text,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (m.isPublic)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.good.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('PUBLIC', style: TextStyle(color: AppColors.good, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          (_userLocation != null ? '${_kmLabel(_kmTo(m))} · ' : '') + m.city + (m.address.isNotEmpty ? ' · ${m.address}' : ''),
                          style: TextStyle(color: AppColors.text38, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.pop(context); // close drawer
                          _moveTo(m);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
