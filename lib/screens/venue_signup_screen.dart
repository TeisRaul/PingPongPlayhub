import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/mock_locations.dart';
import '../widgets/city_selector.dart';

class VenueSignupScreen extends StatefulWidget {
  final bool isAdminCreating;
  final bool isEditMode;
  final String? venueId;
  final Map<String, dynamic>? venueData;

  const VenueSignupScreen({
    super.key,
    this.isAdminCreating = false,
    this.isEditMode = false,
    this.venueId,
    this.venueData,
  });

  @override
  State<VenueSignupScreen> createState() => _VenueSignupScreenState();
}

class _VenueSignupScreenState extends State<VenueSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Controllers
  final _venueNameController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _websiteController = TextEditingController();

  bool _isPublic = false;
  bool _allowHalfHourRentals = true;

  final Map<String, bool> _supportedSports = {
    'ping_pong': true,
    'padel': false,
    'tenis': false,
    'fotbal': false,
    'handbal': false,
    'baschet': false,
  };

  final Map<String, String> _sportNames = {
    'ping_pong': 'Ping Pong',
    'padel': 'Padel',
    'tenis': 'Tenis',
    'fotbal': 'Fotbal',
    'handbal': 'Handbal',
    'baschet': 'Baschet',
  };

  final Map<String, TextEditingController> _indoorResourcesControllers = {
    'ping_pong': TextEditingController(text: '0'),
  };
  final Map<String, TextEditingController> _outdoorResourcesControllers = {
    'ping_pong': TextEditingController(text: '0'),
  };

  void _toggleSport(String key, bool? value) {
    setState(() {
      _supportedSports[key] = value ?? false;
      if (_supportedSports[key]!) {
        _indoorResourcesControllers.putIfAbsent(key, () => TextEditingController(text: '0'));
        _outdoorResourcesControllers.putIfAbsent(key, () => TextEditingController(text: '0'));
      }
    });
  }

  // Operating hours controllers
  final _lvOpenController = TextEditingController(text: '08:00');
  final _lvCloseController = TextEditingController(text: '22:00');
  final _sOpenController = TextEditingController(text: '09:00');
  final _sCloseController = TextEditingController(text: '21:00');
  final _dOpenController = TextEditingController(text: '09:00');
  final _dCloseController = TextEditingController(text: '18:00');

  String _priceType = 'flat';
  final _flatPriceHourController = TextEditingController(text: '30');
  final _flatPriceHalfController = TextEditingController(text: '15');
  int _dynamicHourLimit = 17;
  final _dynamicPriceHourBeforeController = TextEditingController(text: '30');
  final _dynamicPriceHalfBeforeController = TextEditingController(text: '15');
  final _dynamicPriceHourAfterController = TextEditingController(text: '40');
  final _dynamicPriceHalfAfterController = TextEditingController(text: '20');

  // Subscription & Equipment
  bool _offerSubscription = false;
  final _subscriptionPriceController = TextEditingController(text: '150');
  
  List<Map<String, dynamic>> _extraServices = [];

  final _cuiController = TextEditingController();
  final _ibanController = TextEditingController();

  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Facilities checklist mapping
  final Map<String, bool> _facilities = {
    'Vestiare / Dușuri': false,
    'Aer condiționat / Încălzire': false,
    'Închiriere palete / mingi': false,
    'Antrenor personal / Cursuri': false,
    'Parcare proprie': false,
    'Bar / Automat de băuturi': false,
  };

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode && widget.venueData != null) {
      final data = widget.venueData!;
      _venueNameController.text = data['venueName'] ?? '';
      _contactPersonController.text = data['contactPerson'] ?? '';
      _phoneController.text = data['phoneNumber'] ?? '';
      _emailController.text = data['email'] ?? '';
      _cityController.text = data['city'] ?? '';
      _addressController.text = data['address'] ?? '';
      _websiteController.text = data['website'] ?? '';
      
      _isPublic = data['isPublic'] ?? false;
      _allowHalfHourRentals = data['allowHalfHourRentals'] ?? true;
      
      final activeSports = (data['supportedSports'] as List?)?.cast<String>() ?? [];
      for (var sport in _supportedSports.keys) {
        _supportedSports[sport] = activeSports.contains(sport);
      }
      
      final resources = data['resourcesPerSport'] as Map<String, dynamic>? ?? {};
      resources.forEach((sport, res) {
        if (_supportedSports[sport] == true) {
          _indoorResourcesControllers[sport] = TextEditingController(text: (res['indoor'] ?? 0).toString());
          _outdoorResourcesControllers[sport] = TextEditingController(text: (res['outdoor'] ?? 0).toString());
        }
      });
      
      final hours = data['operatingHours'] as Map<String, dynamic>? ?? {};
      _lvOpenController.text = hours['lv_open'] ?? '08:00';
      _lvCloseController.text = hours['lv_close'] ?? '22:00';
      _sOpenController.text = hours['s_open'] ?? '09:00';
      _sCloseController.text = hours['s_close'] ?? '21:00';
      _dOpenController.text = hours['d_open'] ?? '09:00';
      _dCloseController.text = hours['d_close'] ?? '18:00';
      
      final pricing = data['pricing'] as Map<String, dynamic>? ?? {};
      _priceType = pricing['type'] ?? 'flat';
      _flatPriceHourController.text = (pricing['flatPriceHour'] ?? 30).toString();
      _flatPriceHalfController.text = (pricing['flatPriceHalf'] ?? 15).toString();
      _dynamicHourLimit = pricing['dynamicHourLimit'] ?? 17;
      _dynamicPriceHourBeforeController.text = (pricing['dynamicPriceHourBefore'] ?? 30).toString();
      _dynamicPriceHalfBeforeController.text = (pricing['dynamicPriceHalfBefore'] ?? 15).toString();
      _dynamicPriceHourAfterController.text = (pricing['dynamicPriceHourAfter'] ?? 40).toString();
      _dynamicPriceHalfAfterController.text = (pricing['dynamicPriceHalfAfter'] ?? 20).toString();
      
      _offerSubscription = data['offerSubscription'] ?? false;
      _subscriptionPriceController.text = (data['subscriptionPrice'] ?? 150).toString();
      
      _extraServices = (data['extraServices'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      
      _cuiController.text = data['cui'] ?? '';
      _ibanController.text = data['iban'] ?? '';
      
      final facilities = (data['facilities'] as List?)?.cast<String>() ?? [];
      _facilities['Vestiare / Dușuri'] = facilities.contains('vestiare');
      _facilities['Aer condiționat / Încălzire'] = facilities.contains('aer_conditionat');
      _facilities['Închiriere palete / mingi'] = facilities.contains('inchiriere_palete');
      _facilities['Antrenor personal / Cursuri'] = facilities.contains('antrenor');
      _facilities['Parcare proprie'] = facilities.contains('parcare');
      _facilities['Bar / Automat de băuturi'] = facilities.contains('bar');
    }
  }

  @override
  void dispose() {
    _venueNameController.dispose();
    _contactPersonController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _websiteController.dispose();
    for (var ctrl in _indoorResourcesControllers.values) {
      ctrl.dispose();
    }
    for (var ctrl in _outdoorResourcesControllers.values) {
      ctrl.dispose();
    }
    _lvOpenController.dispose();
    _lvCloseController.dispose();
    _sOpenController.dispose();
    _sCloseController.dispose();
    _dOpenController.dispose();
    _dCloseController.dispose();
    _flatPriceHourController.dispose();
    _flatPriceHalfController.dispose();
    _dynamicPriceHourBeforeController.dispose();
    _dynamicPriceHalfBeforeController.dispose();
    _dynamicPriceHourAfterController.dispose();
    _dynamicPriceHalfAfterController.dispose();
    _subscriptionPriceController.dispose();
    _cuiController.dispose();
    _ibanController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
    final initialTimeStr = controller.text;
    int initialHour = 8;
    int initialMinute = 0;
    
    if (initialTimeStr.contains(':')) {
      final parts = initialTimeStr.split(':');
      initialHour = int.tryParse(parts[0]) ?? 8;
      initialMinute = int.tryParse(parts[1]) ?? 0;
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00E5FF),
              onPrimary: Colors.black,
              surface: Color(0xFF131A2A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final hourStr = picked.hour.toString().padLeft(2, '0');
      final minuteStr = picked.minute.toString().padLeft(2, '0');
      setState(() {
        controller.text = '$hourStr:$minuteStr';
      });
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!widget.isAdminCreating && !widget.isEditMode) {
      if (_passwordController.text != _confirmPasswordController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parolele nu coincid!'), backgroundColor: Colors.redAccent),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      String uid = widget.venueId ?? '';
      
      if (!widget.isEditMode) {
        if (!widget.isAdminCreating) {
          // 1. Create auth account in Firebase
          final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          uid = userCredential.user!.uid;
        } else {
          // Admin creating: don't create Auth, just generate a UID
          uid = FirebaseFirestore.instance.collection('venues').doc().id;
        }
      }

      // 2. Map selected facilities to standard list tags
      final List<String> selectedFacilities = [];
      _facilities.forEach((facility, isSelected) {
        if (isSelected) {
          if (facility == 'Vestiare / Dușuri') selectedFacilities.add('vestiare');
          if (facility == 'Aer condiționat / Încălzire') selectedFacilities.add('aer_conditionat');
          if (facility == 'Închiriere palete / mingi') selectedFacilities.add('inchiriere_palete');
          if (facility == 'Antrenor personal / Cursuri') selectedFacilities.add('antrenor');
          if (facility == 'Parcare proprie') selectedFacilities.add('parcare');
          if (facility == 'Bar / Automat de băuturi') selectedFacilities.add('bar');
        }
      });

      // 3. Parse hourly price as structured
      String priceText = 'Gratis (Locație Publică)';
      double mainPrice = 0.0;
      final double flatPriceHour = _isPublic ? 0.0 : (double.tryParse(_flatPriceHourController.text) ?? 30.0);
      final double flatPriceHalf = _isPublic ? 0.0 : (double.tryParse(_flatPriceHalfController.text) ?? 15.0);
      final double dynamicPriceHourBefore = _isPublic ? 0.0 : (double.tryParse(_dynamicPriceHourBeforeController.text) ?? 30.0);
      final double dynamicPriceHalfBefore = _isPublic ? 0.0 : (double.tryParse(_dynamicPriceHalfBeforeController.text) ?? 15.0);
      final double dynamicPriceHourAfter = _isPublic ? 0.0 : (double.tryParse(_dynamicPriceHourAfterController.text) ?? 40.0);
      final double dynamicPriceHalfAfter = _isPublic ? 0.0 : (double.tryParse(_dynamicPriceHalfAfterController.text) ?? 20.0);

      if (!_isPublic) {
        if (_priceType == 'flat') {
          priceText = '${flatPriceHour.toStringAsFixed(0)} RON/oră';
          if (_allowHalfHourRentals) priceText += ', ${flatPriceHalf.toStringAsFixed(0)} RON/jumătate de oră';
          mainPrice = flatPriceHour;
        } else {
          priceText = '${dynamicPriceHourBefore.toStringAsFixed(0)} RON/oră înainte de $_dynamicHourLimit:00, ${dynamicPriceHourAfter.toStringAsFixed(0)} RON/oră după $_dynamicHourLimit:00';
          mainPrice = dynamicPriceHourBefore;
        }
      }

      int totalIndoor = 0;
      int totalOutdoor = 0;
      Map<String, Map<String, int>> resourcesPerSport = {};
      List<String> activeSports = [];
      Map<String, List<Map<String, dynamic>>> generatedLayouts = {};

      _supportedSports.forEach((sport, isActive) {
        if (isActive) {
          activeSports.add(sport);
          int indoor = int.tryParse(_indoorResourcesControllers[sport]?.text ?? '0') ?? 0;
          int outdoor = int.tryParse(_outdoorResourcesControllers[sport]?.text ?? '0') ?? 0;
          resourcesPerSport[sport] = {'indoor': indoor, 'outdoor': outdoor};
          totalIndoor += indoor;
          totalOutdoor += outdoor;
          
          List<Map<String, dynamic>> sportLayout = [];
          int logicalId = 1;
          
          // Place indoor tables/fields sequentially
          for (int i = 0; i < indoor; i++) {
            sportLayout.add({
              'tableId': logicalId++,
              'name': 'Teren/Masă ${i + 1}',
              'type': 'indoor',
              'x': i % 5,
              'y': i ~/ 5,
            });
          }
          
          // Place outdoor tables/fields sequentially on their OWN grid
          for (int i = 0; i < outdoor; i++) {
            sportLayout.add({
              'tableId': logicalId++,
              'name': 'Teren/Masă ${i + 1} Out',
              'type': 'outdoor',
              'x': i % 5,
              'y': i ~/ 5,
            });
          }
          
          generatedLayouts[sport] = sportLayout;
        }
      });
      final int totalTables = totalIndoor + totalOutdoor;

      // 4. Save to venues Firestore collection
      final Map<String, dynamic> venueData = {
        'venueId': uid,
        'venueName': _venueNameController.text.trim(),
        'contactPerson': _contactPersonController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'email': email,
        'city': _cityController.text.trim(),
        'address': _addressController.text.trim(),
        'website': _websiteController.text.trim(),
        'indoorTables': totalIndoor,
        'outdoorTables': totalOutdoor,
        'totalTables': totalTables,
        'supportedSports': activeSports,
        'resourcesPerSport': resourcesPerSport,
        'isPublic': _isPublic,
        'allowHalfHourRentals': _allowHalfHourRentals,
        'layouts': generatedLayouts,
        'facilities': selectedFacilities,
        'priceType': _priceType,
        'flatPriceHour': flatPriceHour,
        'flatPriceHalf': flatPriceHalf,
        'dynamicHourLimit': _dynamicHourLimit,
        'dynamicPriceHourBefore': dynamicPriceHourBefore,
        'dynamicPriceHalfBefore': dynamicPriceHalfBefore,
        'dynamicPriceHourAfter': dynamicPriceHourAfter,
        'dynamicPriceHalfAfter': dynamicPriceHalfAfter,
        'offersSubscription': _offerSubscription,
        'subscriptionPrice': _offerSubscription ? (double.tryParse(_subscriptionPriceController.text) ?? 150.0) : 0.0,
        'extraServices': _extraServices,
        'pricePerHour': mainPrice,
        'pricePerHourText': priceText,
        'schedule': {
          'Luni-Vineri': '${_lvOpenController.text} - ${_lvCloseController.text}',
          'Sambata': '${_sOpenController.text} - ${_sCloseController.text}',
          'Duminica': '${_dOpenController.text} - ${_dCloseController.text}',
        },
        'cui': _cuiController.text.trim(),
        'iban': _ibanController.text.trim(),
        'isVerified': true,
      };

      if (!widget.isEditMode) {
        venueData['blockedDates'] = [];
        venueData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('venues').doc(uid).set(venueData);
        
        if (widget.isAdminCreating) {
          // Also create a dummy user document so they can reset password later
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'email': email,
            'role': 'venue_admin',
            'fullName': _contactPersonController.text.trim(),
            'phone': _phoneController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        await FirebaseFirestore.instance.collection('venues').doc(uid).update(venueData);
      }

      // Show success modal
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A2A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
              ),
              title: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF00E5FF), size: 28),
                  const SizedBox(width: 10),
                  Text(widget.isEditMode ? 'Sală Actualizată!' : (widget.isAdminCreating ? 'Sală Creată (Admin)' : 'Cont Creat!'), style: const TextStyle(color: Colors.white)),
                ],
              ),
              content: Text(
                widget.isEditMode
                    ? 'Modificările au fost salvate cu succes!'
                    : (widget.isAdminCreating
                        ? 'Sala a fost creată cu succes, dar administratorul trebuie să-și reseteze parola pe baza email-ului setat.'
                        : 'Contul de Sală a fost creat cu succes!\n\nAcesta va deveni complet funcțional și vizibil pentru jucători după ce va fi aprobat manual de către administratorul PingPong Playhub.'),
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (widget.isEditMode || widget.isAdminCreating) {
                      Navigator.pop(context); // Close dialog
                      Navigator.pop(context); // Return to previous admin screen
                    } else {
                      Navigator.pop(context); // Close dialog
                      Navigator.pop(context); // Return to login
                    }
                  },
                  child: const Text('OK', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la crearea contului: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00E5FF),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Divider(color: Color(0xFF1E293B), height: 1, thickness: 1.5),
        ],
      ),
    );
  }

  Widget _buildTimeSelectorRow(String label, TextEditingController openCtrl, TextEditingController closeCtrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 15)),
          ),
          Expanded(
            flex: 4,
            child: InkWell(
              onTap: () => _selectTime(context, openCtrl),
              child: IgnorePointer(
                child: TextFormField(
                  controller: openCtrl,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Deschidere',
                    contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: InkWell(
              onTap: () => _selectTime(context, closeCtrl),
              child: IgnorePointer(
                child: TextFormField(
                  controller: closeCtrl,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Închidere',
                    contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Înregistrare Sală / Club'),
        backgroundColor: const Color(0xFF131A2A),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.storefront,
                  size: 64,
                  color: Color(0xFF00E5FF),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Creează Cont de Sală',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Completează detaliile clubului tău pentru a începe organizarea de turnee și meciuri.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),

                // 1. Date Contact Business
                _buildSectionHeader('1. Informații Sală & Contact'),
                TextFormField(
                  controller: _venueNameController,
                  decoration: const InputDecoration(
                    labelText: 'Numele Sălii / Clubului',
                    prefixIcon: Icon(Icons.business),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Te rugăm să introduci numele sălii';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _contactPersonController,
                  decoration: const InputDecoration(
                    labelText: 'Nume Administrator / Persoană de contact',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Te rugăm să introduci persoana de contact';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Telefon Business',
                          prefixIcon: Icon(Icons.phone),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Te rugăm să introduci numărul de telefon';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Business (pentru logare)',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty || !value.contains('@')) {
                      return 'Te rugăm să introduci un email valid';
                    }
                    return null;
                  },
                ),

                // 2. Adresă și Mediu Online
                _buildSectionHeader('2. Adresă & Locație'),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: CitySelectorField(
                        selectedCity: _cityController.text.isEmpty ? null : _cityController.text,
                        cityOptions: romanianCities,
                        onCitySelected: (val) {
                          setState(() {
                            _cityController.text = val;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Oraș obligatoriu';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                          labelText: 'Adresă completă',
                          prefixIcon: Icon(Icons.map_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Adresă obligatorie';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _websiteController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Website / Rețele Sociale (Opțional)',
                    prefixIcon: Icon(Icons.language),
                  ),
                ),

                // 3. Dotări și Facilități
                _buildSectionHeader('3. Detalii Sală & Dotări'),
                SwitchListTile(
                  title: const Text('Locație Publică / Gratuită', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Mese/terenuri publice gratis. Tarifele vor fi dezactivate.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: _isPublic,
                  activeColor: const Color(0xFF00E5FF),
                  onChanged: (val) => setState(() => _isPublic = val),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sporturi Suportate:',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: _supportedSports.keys.map((String key) {
                    return FilterChip(
                      label: Text(_sportNames[key]!),
                      selected: _supportedSports[key]!,
                      selectedColor: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                      checkmarkColor: const Color(0xFF00E5FF),
                      backgroundColor: const Color(0xFF131A2A),
                      labelStyle: TextStyle(
                        color: _supportedSports[key]! ? const Color(0xFF00E5FF) : Colors.white70,
                      ),
                      onSelected: (bool selected) {
                        _toggleSport(key, selected);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Număr Terenuri / Mese per Sport:',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._supportedSports.entries.where((e) => e.value).map((entry) {
                  final sportKey = entry.key;
                  final sportName = _sportNames[sportKey]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _indoorResourcesControllers[sportKey],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '$sportName Indoor',
                              prefixIcon: const Icon(Icons.sports),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _outdoorResourcesControllers[sportKey],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '$sportName Outdoor',
                              prefixIcon: const Icon(Icons.wb_sunny_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                const Text(
                  'Facilități incluse:',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  color: const Color(0xFF131A2A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.15)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: Column(
                      children: _facilities.keys.map((String key) {
                        return CheckboxListTile(
                          title: Text(key, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          activeColor: const Color(0xFF00E5FF),
                          checkColor: Colors.black,
                          value: _facilities[key],
                          onChanged: (bool? value) {
                            setState(() {
                              _facilities[key] = value ?? false;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // 4. Program și Tarife
                _buildSectionHeader('4. Program de Funcționare & Tarife'),
                _buildTimeSelectorRow('Luni - Vineri', _lvOpenController, _lvCloseController),
                _buildTimeSelectorRow('Sâmbătă', _sOpenController, _sCloseController),
                _buildTimeSelectorRow('Duminică', _dOpenController, _dCloseController),
                if (!_isPublic) ...[
                  SwitchListTile(
                    title: const Text('Permite închiriere la jumătate de oră', style: TextStyle(color: Colors.white, fontSize: 14)),
                    value: _allowHalfHourRentals,
                    activeColor: const Color(0xFF00E5FF),
                    onChanged: (val) => setState(() => _allowHalfHourRentals = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _priceType,
                    dropdownColor: const Color(0xFF131A2A),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Tip Tarifare',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'flat', child: Text('Preț Fix (Același tarif oricând)')),
                      DropdownMenuItem(value: 'dynamic', child: Text('Preț Dinamic (Tarife diferite în funcție de oră)')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _priceType = val ?? 'flat';
                      });
                    },
                  ),
                ],
                if (!_isPublic && _priceType == 'flat') ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _flatPriceHourController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            labelText: 'Tarif 1 Oră (RON)',
                            prefixIcon: Icon(Icons.monetization_on_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Introdu prețul';
                            if (double.tryParse(value) == null) return 'Valoare invalidă';
                            return null;
                          },
                        ),
                      ),
                      if (_allowHalfHourRentals) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _flatPriceHalfController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Tarif 0.5 Oră (RON)',
                              prefixIcon: Icon(Icons.monetization_on_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) return 'Introdu prețul';
                              if (double.tryParse(value) == null) return 'Valoare invalidă';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else if (!_isPublic && _priceType == 'dynamic') ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _dynamicHourLimit,
                    dropdownColor: const Color(0xFF131A2A),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Oră Limită Preț',
                      prefixIcon: Icon(Icons.access_time),
                    ),
                    items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text('$i:00'))),
                    onChanged: (val) => setState(() => _dynamicHourLimit = val ?? 17),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _dynamicPriceHourBeforeController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            labelText: 'Tarif 1 Oră Înainte (RON)',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Introdu prețul';
                            if (double.tryParse(value) == null) return 'Valoare invalidă';
                            return null;
                          },
                        ),
                      ),
                      if (_allowHalfHourRentals) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _dynamicPriceHalfBeforeController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Tarif 0.5 Oră Înainte (RON)',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) return 'Introdu prețul';
                              if (double.tryParse(value) == null) return 'Valoare invalidă';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _dynamicPriceHourAfterController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            labelText: 'Tarif 1 Oră După (RON)',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Introdu prețul';
                            if (double.tryParse(value) == null) return 'Valoare invalidă';
                            return null;
                          },
                        ),
                      ),
                      if (_allowHalfHourRentals) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _dynamicPriceHalfAfterController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: const InputDecoration(
                              labelText: 'Tarif 0.5 Oră După (RON)',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) return 'Introdu prețul';
                              if (double.tryParse(value) == null) return 'Valoare invalidă';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ],

                const SizedBox(height: 24),
                _buildSectionHeader('Abonamente (Opțional)'),
                SwitchListTile(
                  title: const Text('Oferă Abonament Lunar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Jucătorii pot cumpăra abonament pentru ore nelimitate/limitate.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  value: _offerSubscription,
                  activeColor: const Color(0xFF00E5FF),
                  onChanged: (val) => setState(() => _offerSubscription = val),
                ),
                if (_offerSubscription) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _subscriptionPriceController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Preț Abonament (RON/lună)',
                      prefixIcon: Icon(Icons.star_outline),
                    ),
                    validator: (value) {
                      if (_offerSubscription) {
                        if (value == null || value.trim().isEmpty) return 'Introdu prețul abonamentului';
                        if (double.tryParse(value) == null) return 'Valoare invalidă';
                      }
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: 24),
                _buildSectionHeader('Servicii Extra (Mâncare, Echipament, etc.)'),
                const Text(
                  'Adaugă servicii suplimentare pe care le oferiți contra cost (ex: Închiriere palete, Apă plată, Sucuri).',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ..._extraServices.asMap().entries.map((entry) {
                  int idx = entry.key;
                  var service = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            initialValue: service['name'],
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(labelText: 'Nume Serviciu', isDense: true),
                            onChanged: (val) => setState(() => _extraServices[idx]['name'] = val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            initialValue: service['price'].toString(),
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(labelText: 'Preț (RON)', isDense: true),
                            onChanged: (val) => setState(() => _extraServices[idx]['price'] = double.tryParse(val) ?? 0.0),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => setState(() => _extraServices.removeAt(idx)),
                        ),
                      ],
                    ),
                  );
                }),
                TextButton.icon(
                  onPressed: () => setState(() => _extraServices.add({'name': '', 'price': 0.0})),
                  icon: const Icon(Icons.add, color: Color(0xFF00E5FF)),
                  label: const Text('Adaugă Serviciu Extra', style: TextStyle(color: Color(0xFF00E5FF))),
                ),

                // 5. Date Financiare
                _buildSectionHeader('5. Date Financiare (Salarizare)'),
                TextFormField(
                  controller: _cuiController,
                  decoration: const InputDecoration(
                    labelText: 'CUI / Date Fiscale (Opțional pentru MVP)',
                    prefixIcon: Icon(Icons.receipt_long),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ibanController,
                  decoration: const InputDecoration(
                    labelText: 'IBAN de încasare plăți',
                    prefixIcon: Icon(Icons.account_balance),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Te rugăm să introduci contul IBAN al clubului';
                    }
                    return null;
                  },
                ),

                // 6. Securitate
                if (!widget.isAdminCreating && !widget.isEditMode) ...[
                  _buildSectionHeader('6. Securitate Cont'),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Parolă',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 6) {
                        return 'Parola trebuie să aibă minim 6 caractere';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirmă parolă',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Te rugăm să confirmi parola';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),
                ],

                const SizedBox(height: 32),

                // Submit Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : const Text('ÎNREGISTREAZĂ SALA'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
