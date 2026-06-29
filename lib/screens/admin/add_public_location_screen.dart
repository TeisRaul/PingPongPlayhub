import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../../data/mock_locations.dart';
import '../../widgets/city_selector.dart';

class AddPublicLocationScreen extends StatefulWidget {
  final bool isEditMode;
  final String? venueId;
  final Map<String, dynamic>? venueData;

  const AddPublicLocationScreen({
    super.key,
    this.isEditMode = false,
    this.venueId,
    this.venueData,
  });

  @override
  State<AddPublicLocationScreen> createState() => _AddPublicLocationScreenState();
}

class _AddPublicLocationScreenState extends State<AddPublicLocationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  
  String? _selectedCity;
  
  final Map<String, bool> _supportedSports = {
    'ping_pong': false,
    'padel': false,
    'tenis': false,
    'fotbal': false,
    'handbal': false,
    'baschet': false,
  };

  final Map<String, int> _resources = {};
  bool _isLoading = false;
  bool _isVerifying = false;
  LatLng? _verifiedLocation;
  
  List<Map<String, dynamic>> _addressSuggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode && widget.venueData != null) {
      _nameController.text = widget.venueData!['venueName'] ?? '';
      _addressController.text = widget.venueData!['address'] ?? '';
      _selectedCity = widget.venueData!['city'];

      if (widget.venueData!['latitude'] != null && widget.venueData!['longitude'] != null) {
        _verifiedLocation = LatLng(
          (widget.venueData!['latitude'] as num).toDouble(),
          (widget.venueData!['longitude'] as num).toDouble(),
        );
      }

      final List<dynamic> sports = widget.venueData!['supportedSports'] ?? [];
      for (var s in sports) {
        if (_supportedSports.containsKey(s)) {
          _supportedSports[s.toString()] = true;
          // Calculate tables based on layouts
          final layouts = widget.venueData!['layouts'] as Map<String, dynamic>? ?? {};
          final sportLayout = layouts[s.toString()] as List<dynamic>? ?? [];
          _resources[s.toString()] = sportLayout.length;
        }
      }
    }
  }

  void _onAddressChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (value.length < 3) {
      setState(() => _addressSuggestions = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (_selectedCity == null) return;
      setState(() => _isVerifying = true);
      
      try {
        final query = Uri.encodeComponent('$value, $_selectedCity, Romania');
        final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=5');
        final response = await http.get(url, headers: {'User-Agent': 'PingPongPlayhub/1.0'});

        if (response.statusCode == 200) {
          final List data = json.decode(response.body);
          if (mounted) {
            setState(() {
              _addressSuggestions = data.map((e) => e as Map<String, dynamic>).toList();
            });
          }
        }
      } catch (e) {
        // ignore
      } finally {
        if (mounted) setState(() => _isVerifying = false);
      }
    });
  }

  void _selectAddress(Map<String, dynamic> option) {
    _addressController.text = option['display_name'] ?? '';
    final lat = double.parse(option['lat'].toString());
    final lon = double.parse(option['lon'].toString());
    
    setState(() {
      _verifiedLocation = LatLng(lat, lon);
      _addressSuggestions = [];
      FocusScope.of(context).unfocus();
    });
  }

  void _saveLocation() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alege un oraș!'), backgroundColor: Colors.red),
      );
      return;
    }
    
    // We remove the strict requirement for _verifiedLocation since the user might not use the autocomplete properly
    // But we should strongly encourage it.

    final activeSports = _supportedSports.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (activeSports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selectează măcar un sport!'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final docRef = FirebaseFirestore.instance.collection('venues').doc();
      
      Map<String, List<Map<String, dynamic>>> layouts = {};
      
      for (String sport in activeSports) {
        int numTables = _resources[sport] ?? 1;
        List<Map<String, dynamic>> sportLayout = [];
        for (int i = 0; i < numTables; i++) {
          sportLayout.add({
            'tableId': i + 1,
            'name': 'Masa/Teren ${i + 1}',
            'type': 'indoor',
            'x': i % 5,
            'y': i ~/ 5,
          });
        }
        layouts[sport] = sportLayout;
      }

      final data = {
        'venueName': _nameController.text.trim(),
        'city': _selectedCity,
        'address': _addressController.text.trim(),
        'isPublic': true,
        'pricePerHourText': '0 RON/oră (Gratis)',
        'supportedSports': activeSports,
        'layouts': layouts,
        if (_verifiedLocation != null) 'latitude': _verifiedLocation!.latitude,
        if (_verifiedLocation != null) 'longitude': _verifiedLocation!.longitude,
        if (!widget.isEditMode) 'createdAt': FieldValue.serverTimestamp(),
      };

      if (widget.isEditMode && widget.venueId != null) {
        await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).update(data);
      } else {
        data['uid'] = docRef.id;
        await docRef.set(data);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Locația a fost adăugată pe hartă!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Editare Sală' : 'Adaugă Locație Publică', style: const TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00FF66)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.park, size: 64, color: Color(0xFF00FF66)),
              const SizedBox(height: 16),
              const Text(
                'Această locație va apărea gratuită pentru toți jucătorii pe hartă.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nume Locație (ex: Parc IOR)',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                ),
                validator: (v) => v!.isEmpty ? 'Necesar' : null,
              ),
              const SizedBox(height: 16),
              
              CitySelectorField(
                labelText: 'Oraș',
                selectedCity: _selectedCity,
                cityOptions: romanianCities,
                onCitySelected: (c) => setState(() => _selectedCity = c),
                validator: (v) => v == null ? 'Necesar' : null,
              ),
              const SizedBox(height: 16),
              
              Stack(
                alignment: Alignment.centerRight,
                children: [
                  TextFormField(
                    controller: _addressController,
                    style: const TextStyle(color: Colors.white),
                    onChanged: _onAddressChanged,
                    decoration: const InputDecoration(
                      labelText: 'Caută Adresă',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                    ),
                  ),
                  if (_isVerifying)
                    const Padding(
                      padding: EdgeInsets.only(right: 16.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Color(0xFF00FF66), strokeWidth: 2),
                      ),
                    ),
                ],
              ),
              if (_addressSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[800]!),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _addressSuggestions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black26),
                    itemBuilder: (context, index) {
                      final option = _addressSuggestions[index];
                      return ListTile(
                        leading: const Icon(Icons.location_on, color: Colors.grey),
                        title: Text(option['display_name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                        onTap: () => _selectAddress(option),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              
              if (_verifiedLocation != null)
                Container(
                  height: 200,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00FF66)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: _verifiedLocation!,
                        initialZoom: 15.0,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.pingpongplayhub.app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _verifiedLocation!,
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              
              const Text('Selectează Sporturile Practicate:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _supportedSports.keys.map((sport) {
                  final isActive = _supportedSports[sport] ?? false;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _supportedSports[sport] = !isActive;
                        if (!isActive) _resources[sport] = 1;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFF00FF66).withValues(alpha: 0.2) : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive ? const Color(0xFF00FF66) : Colors.grey[800]!,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isActive ? Icons.check_circle : Icons.circle_outlined,
                            color: isActive ? const Color(0xFF00FF66) : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            sport.toUpperCase(),
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.grey,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              
              ..._supportedSports.keys.where((s) => _supportedSports[s] == true).map((sport) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131A2A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00FF66).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Mese / Terenuri de ${sport.toUpperCase()}',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          initialValue: (_resources[sport] ?? 1).toString(),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.grey)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF00FF66))),
                          ),
                          onChanged: (v) => _resources[sport] = int.tryParse(v) ?? 1,
                        ),
                      ),
                    ],
                  ),
                );
              }),

              
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF66),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black))
                    : const Text('SALVEAZĂ LOCAȚIA', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
