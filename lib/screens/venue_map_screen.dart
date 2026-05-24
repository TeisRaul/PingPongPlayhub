import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'create_match_screen.dart';

// ── Coordonate pentru marile oraşe din România ──────────────────────────────
const Map<String, LatLng> _cityCoords = {
  'alba iulia':          LatLng(46.0667,  23.5833),
  'alexandria':          LatLng(43.9764,  25.3358),
  'arad':                LatLng(46.1833,  21.3167),
  'bacău':               LatLng(46.5675,  26.9133),
  'baia mare':           LatLng(47.6567,  23.5683),
  'bistrița':            LatLng(47.1353,  24.4992),
  'botoșani':            LatLng(47.7444,  26.6578),
  'brașov':              LatLng(45.6427,  25.5887),
  'brăila':              LatLng(45.2692,  27.9575),
  'bucurești':           LatLng(44.4268,  26.1025),
  'buzău':               LatLng(45.1500,  26.8167),
  'călărași':            LatLng(44.2019,  27.3328),
  'cluj-napoca':         LatLng(46.7712,  23.6236),
  'constanța':           LatLng(44.1598,  28.6348),
  'craiova':             LatLng(44.3302,  23.7949),
  'deva':                LatLng(45.8869,  22.9008),
  'drobeta-turnu severin': LatLng(44.6261, 22.6567),
  'focșani':             LatLng(45.6989,  27.1872),
  'galați':              LatLng(45.4353,  28.0078),
  'giurgiu':             LatLng(43.9022,  25.9697),
  'iași':                LatLng(47.1585,  27.6014),
  'miercurea ciuc':      LatLng(46.3569,  25.8028),
  'oradea':              LatLng(47.0722,  21.9217),
  'piatra neamț':        LatLng(46.9228,  26.3683),
  'pitești':             LatLng(44.8565,  24.8692),
  'ploiești':            LatLng(44.9356,  26.0225),
  'râmnicu vâlcea':      LatLng(45.0997,  24.3694),
  'reșița':              LatLng(45.2983,  21.8889),
  'satu mare':           LatLng(47.7908,  22.8872),
  'sfântu gheorghe':     LatLng(45.8672,  25.7883),
  'sibiu':               LatLng(45.7983,  24.1256),
  'slatina':             LatLng(44.4308,  24.3647),
  'slobozia':            LatLng(44.5628,  27.3672),
  'suceava':             LatLng(47.6514,  26.2556),
  'târgoviște':          LatLng(44.9275,  25.4575),
  'târgu jiu':           LatLng(45.0333,  23.2833),
  'târgu mureș':         LatLng(46.5500,  24.5667),
  'timișoara':           LatLng(45.7489,  21.2087),
  'tulcea':              LatLng(45.1667,  28.8000),
  'vaslui':              LatLng(46.6333,  27.7333),
  'zalău':               LatLng(47.1833,  23.0500),
};

LatLng? _coordsForCity(String? city) {
  if (city == null || city.isEmpty) return null;
  return _cityCoords[city.toLowerCase().trim()];
}

// ────────────────────────────────────────────────────────────────────────────

class _VenueMarker {
  final String id;
  final String name;
  final String city;
  final String address;
  final String? priceText;
  final LatLng coords;

  const _VenueMarker({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    required this.priceText,
    required this.coords,
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
  LatLng? _userLocation;
  String _drawerSearchQuery = '';
  bool _onlyVisibleInBounds = true;

  @override
  void initState() {
    super.initState();
    _loadVenues();
    _getUserLocation();
  }

  void _getUserLocation() {
    try {
      html.window.navigator.geolocation.getCurrentPosition().then((pos) {
        if (mounted) {
          setState(() {
            _userLocation = LatLng(
              pos.coords!.latitude! as double,
              pos.coords!.longitude! as double,
            );
          });
        }
      }).catchError((_) {
        if (mounted) setState(() {});
      });
    } catch (_) {
      // Geolocation not available
    }
  }

  Future<void> _loadVenues() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('venues').get();
      final result = <_VenueMarker>[];

      for (final doc in snap.docs) {
        final data = doc.data();
        final city    = (data['city']    as String?)?.trim() ?? '';
        final address = (data['address'] as String?)?.trim() ?? '';
        final name    = (data['venueName'] as String?)?.trim() ?? 'Sală necunoscută';
        final price   = data['pricePerHourText'] as String?;

        final coords = _coordsForCity(city);
        if (coords == null) continue; // skip venues with unknown city

        // Add a tiny random offset so venues in the same city don't overlap
        final offset = _markerOffset(result.length);
        result.add(_VenueMarker(
          id: doc.id,
          name: name,
          city: city,
          address: address,
          priceText: price,
          coords: LatLng(
            coords.latitude  + offset.$1,
            coords.longitude + offset.$2,
          ),
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
    if (_filterCity.isEmpty) return _markers;
    return _markers.where(
      (m) => m.city.toLowerCase().contains(_filterCity.toLowerCase()),
    ).toList();
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

    return result.toList();
  }

  void _moveTo(_VenueMarker m) {
    setState(() => _selected = m);
    _mapController.move(m.coords, 13.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131A2A),
        elevation: 0,
        title: const Text(
          'Harta Sălilor de Ping-Pong',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00E5FF)),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Filtrează după oraș...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00E5FF)),
                filled: true,
                fillColor: const Color(0xFF0A0E17),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1A2A3A), width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (val) => setState(() {
                _filterCity = val;
                _selected = null;
              }),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
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
                      color: const Color(0xFF131A2A).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF00E5FF), width: 1),
                    ),
                    child: Text(
                      '${_filteredMarkers.length} sali găsite',
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
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
                      color: const Color(0xFF131A2A).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4), width: 1),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.zoom_out_map, color: Color(0xFF00E5FF), size: 20),
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
                        color: const Color(0xFF131A2A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_off, color: Color(0xFF00E5FF), size: 48),
                          SizedBox(height: 16),
                          Text(
                            'Nicio sală înregistrată\ncu locație validă.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 16),
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
          if (_userLocation != null)
            FloatingActionButton(
              heroTag: 'myLocationBtn',
              mini: true,
              backgroundColor: const Color(0xFF131A2A),
              foregroundColor: Colors.blue,
              onPressed: () {
                _mapController.move(_userLocation!, 13.0);
                setState(() => _selected = null);
              },
              child: const Icon(Icons.my_location),
            ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'listBtn',
            backgroundColor: const Color(0xFF00E5FF),
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
    return Marker(
      point: m.coords,
      width: isSelected ? 48 : 38,
      height: isSelected ? 48 : 38,
      child: GestureDetector(
        onTap: () => _moveTo(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF131A2A),
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.white : const Color(0xFF00E5FF),
              width: isSelected ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withOpacity(isSelected ? 0.7 : 0.4),
                blurRadius: isSelected ? 16 : 8,
                spreadRadius: isSelected ? 2 : 0,
              ),
            ],
          ),
          child: Icon(
            Icons.sports_tennis,
            color: isSelected ? Colors.black : const Color(0xFF00E5FF),
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
        color: const Color(0xFF131A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withOpacity(0.2),
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
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.sports_tennis, color: Color(0xFF00E5FF), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      m.city,
                      style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => setState(() => _selected = null),
              ),
            ],
          ),
          if (m.address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.white38, size: 15),
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
          if (m.priceText != null && m.priceText!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.attach_money, color: Colors.white38, size: 15),
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
          const SizedBox(height: 12),
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
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
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
      backgroundColor: const Color(0xFF0A0E17),
      child: Column(
        children: [
          // Drawer Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: const BoxDecoration(
              color: Color(0xFF131A2A),
              border: Border(bottom: BorderSide(color: Color(0xFF00E5FF), width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.sports_tennis, color: Color(0xFF00E5FF)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${list.length} Săli de Ping-Pong',
                    style: const TextStyle(
                      color: Colors.white,
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
            color: const Color(0xFF131A2A),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Caută după nume sau oraș...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00E5FF), size: 16),
                filled: true,
                fillColor: const Color(0xFF0A0E17),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1A2A3A), width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
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
            color: const Color(0xFF131A2A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.zoom_in, color: Colors.white54, size: 14),
                    SizedBox(width: 8),
                    Text(
                      'Doar cele vizibile pe hartă',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _onlyVisibleInBounds,
                    activeThumbColor: const Color(0xFF00E5FF),
                    activeTrackColor: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: Colors.white10,
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
            color: const Color(0xFF00E5FF).withOpacity(0.3),
          ),

          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'Nicio sală găsită.\n(Încearcă să dezactivezi filtrul de hartă sau să cauți alt oraș)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    separatorBuilder: (_, __) => const Divider(
                      color: Color(0xFF1A2A3A),
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
                                ? const Color(0xFF00E5FF).withOpacity(0.15)
                                : const Color(0xFF131A2A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF00E5FF)
                                  : const Color(0xFF1A2A3A),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.sports_tennis,
                            color: isSelected ? const Color(0xFF00E5FF) : Colors.white38,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          m.name,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF00E5FF) : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          m.city + (m.address.isNotEmpty ? ' · ${m.address}' : ''),
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
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
