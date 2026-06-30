import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../widgets/player_drawer.dart';
import '../data/mock_locations.dart';
import '../widgets/city_selector.dart';
import 'payment_screen.dart';

class VenueProfileScreen extends StatefulWidget {
  final String? venueId;
  const VenueProfileScreen({super.key, this.venueId});

  @override
  State<VenueProfileScreen> createState() => _VenueProfileScreenState();
}

class _VenueProfileScreenState extends State<VenueProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;
  bool _isSaving = false;
  bool _allowHalfHour = false;

  // Form Controllers
  final _venueNameController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _websiteController = TextEditingController();
  final _indoorTablesController = TextEditingController();
  final _outdoorTablesController = TextEditingController();
  String _priceType = 'flat';
  final _flatPriceHourController = TextEditingController(text: '30');
  final _flatPriceHalfController = TextEditingController(text: '15');
  int _dynamicHourLimit = 17;
  final _dynamicPriceHourBeforeController = TextEditingController(text: '30');
  final _dynamicPriceHalfBeforeController = TextEditingController(text: '15');
  final _dynamicPriceHourAfterController = TextEditingController(text: '40');
  final _dynamicPriceHalfAfterController = TextEditingController(text: '20');

  final _cuiController = TextEditingController();
  final _ibanController = TextEditingController();

  // Subscription & Equipment
  bool _offerSubscription = false;
  String _subscriptionType = 'unlimited';
  final _subscriptionEntriesController = TextEditingController(text: '10');
  final _subscriptionPriceController = TextEditingController(text: '150');
  
  List<Map<String, dynamic>> _extraServices = [];

  // Schedule controllers for Editing
  final _lvOpenCtrl = TextEditingController();
  final _lvCloseCtrl = TextEditingController();
  final _sOpenCtrl = TextEditingController();
  final _sCloseCtrl = TextEditingController();
  final _dOpenCtrl = TextEditingController();
  final _dCloseCtrl = TextEditingController();

  // Facilities mapping for Editing
  final Map<String, bool> _tempFacilities = {
    'vestiare': false,
    'aer_conditionat': false,
    'inchiriere_palete': false,
    'antrenor': false,
    'parcare': false,
    'bar': false,
  };

  @override
  void dispose() {
    _venueNameController.dispose();
    _contactPersonController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _websiteController.dispose();
    _indoorTablesController.dispose();
    _outdoorTablesController.dispose();
    _flatPriceHourController.dispose();
    _flatPriceHalfController.dispose();
    _dynamicPriceHourBeforeController.dispose();
    _dynamicPriceHalfBeforeController.dispose();
    _dynamicPriceHourAfterController.dispose();
    _dynamicPriceHalfAfterController.dispose();
    _cuiController.dispose();
    _ibanController.dispose();
    _lvOpenCtrl.dispose();
    _lvCloseCtrl.dispose();
    _sOpenCtrl.dispose();
    _sCloseCtrl.dispose();
    _dOpenCtrl.dispose();
    _dCloseCtrl.dispose();
    _subscriptionPriceController.dispose();
    _subscriptionEntriesController.dispose();
    super.dispose();
  }

  // Populate controllers with active database data when entering Edit Mode
  void _enterEditMode(Map<String, dynamic> data) {
    _venueNameController.text = data['venueName'] ?? '';
    _contactPersonController.text = data['contactPerson'] ?? '';
    _phoneController.text = data['phoneNumber'] ?? '';
    _cityController.text = data['city'] ?? '';
    _addressController.text = data['address'] ?? '';
    _websiteController.text = data['website'] ?? '';
    _indoorTablesController.text = (data['indoorTables'] ?? 0).toString();
    _outdoorTablesController.text = (data['outdoorTables'] ?? 0).toString();
    _priceType = data['priceType'] ?? 'flat';
    final double defaultHour = (data['pricePerHour'] ?? 30.0).toDouble();
    _flatPriceHourController.text = (data['flatPriceHour'] ?? defaultHour).toString();
    _flatPriceHalfController.text = (data['flatPriceHalf'] ?? (defaultHour / 2)).toString();
    _dynamicHourLimit = (data['dynamicHourLimit'] ?? 17) as int;
    _dynamicPriceHourBeforeController.text = (data['dynamicPriceHourBefore'] ?? defaultHour).toString();
    _dynamicPriceHalfBeforeController.text = (data['dynamicPriceHalfBefore'] ?? (defaultHour / 2)).toString();
    _dynamicPriceHourAfterController.text = (data['dynamicPriceHourAfter'] ?? (defaultHour + 10.0)).toString();
    _dynamicPriceHalfAfterController.text = (data['dynamicPriceHalfAfter'] ?? ((defaultHour + 10.0) / 2)).toString();
    _cuiController.text = data['cui'] ?? '';
    _ibanController.text = data['iban'] ?? '';
    _allowHalfHour = data['allowHalfHour'] ?? false;
    _offerSubscription = data['offersSubscription'] ?? false;
    _subscriptionType = data['subscriptionType'] ?? 'unlimited';
    _subscriptionEntriesController.text = (data['subscriptionEntries'] ?? 10).toString();
    _subscriptionPriceController.text = (data['subscriptionPrice'] ?? 150.0).toString();
    
    _extraServices = List<Map<String, dynamic>>.from(
      (data['extraServices'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e))
    );

    // Schedule Parsing
    final schedule = data['schedule'] ?? {};
    final lvParts = (schedule['Luni-Vineri'] ?? '08:00 - 22:00').split(' - ');
    _lvOpenCtrl.text = lvParts.isNotEmpty ? lvParts[0] : '08:00';
    _lvCloseCtrl.text = lvParts.length > 1 ? lvParts[1] : '22:00';

    final sParts = (schedule['Sambata'] ?? '09:00 - 21:00').split(' - ');
    _sOpenCtrl.text = sParts.isNotEmpty ? sParts[0] : '09:00';
    _sCloseCtrl.text = sParts.length > 1 ? sParts[1] : '21:00';

    final dParts = (schedule['Duminica'] ?? '09:00 - 18:00').split(' - ');
    _dOpenCtrl.text = dParts.isNotEmpty ? dParts[0] : '09:00';
    _dCloseCtrl.text = dParts.length > 1 ? dParts[1] : '18:00';

    // Facilities Mapping
    final List<dynamic> dbFacilities = data['facilities'] ?? [];
    for (var key in _tempFacilities.keys) {
      _tempFacilities[key] = dbFacilities.contains(key);
    }

    setState(() {
      _isEditing = true;
    });
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

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Parse structured hourly and half-hourly prices
        final String priceText;
        double mainPrice = 30.0;
        final double flatPriceHour = double.tryParse(_flatPriceHourController.text) ?? 30.0;
        final double flatPriceHalf = double.tryParse(_flatPriceHalfController.text) ?? 15.0;
        final double dynamicPriceHourBefore = double.tryParse(_dynamicPriceHourBeforeController.text) ?? 30.0;
        final double dynamicPriceHalfBefore = double.tryParse(_dynamicPriceHalfBeforeController.text) ?? 15.0;
        final double dynamicPriceHourAfter = double.tryParse(_dynamicPriceHourAfterController.text) ?? 40.0;
        final double dynamicPriceHalfAfter = double.tryParse(_dynamicPriceHalfAfterController.text) ?? 20.0;

        if (_priceType == 'flat') {
          priceText = '${flatPriceHour.toStringAsFixed(0)} RON/oră, ${flatPriceHalf.toStringAsFixed(0)} RON/jumătate de oră';
          mainPrice = flatPriceHour;
        } else {
          priceText = '${dynamicPriceHourBefore.toStringAsFixed(0)} RON/oră înainte de $_dynamicHourLimit:00, ${dynamicPriceHourAfter.toStringAsFixed(0)} RON/oră după $_dynamicHourLimit:00';
          mainPrice = dynamicPriceHourBefore;
        }

        final int indoor = int.tryParse(_indoorTablesController.text) ?? 0;
        final int outdoor = int.tryParse(_outdoorTablesController.text) ?? 0;
        final int total = indoor + outdoor;

        // Facilities List
        final List<String> updatedFacilities = [];
        _tempFacilities.forEach((facilityKey, isSelected) {
          if (isSelected) {
            updatedFacilities.add(facilityKey);
          }
        });

        await FirebaseFirestore.instance.collection('venues').doc(user.uid).update({
          'venueName': _venueNameController.text.trim(),
          'contactPerson': _contactPersonController.text.trim(),
          'phoneNumber': _phoneController.text.trim(),
          'city': _cityController.text.trim(),
          'address': _addressController.text.trim(),
          'website': _websiteController.text.trim(),
          'indoorTables': indoor,
          'outdoorTables': outdoor,
          'totalTables': total,
          'facilities': updatedFacilities,
          'priceType': _priceType,
          'flatPriceHour': flatPriceHour,
          'flatPriceHalf': flatPriceHalf,
          'dynamicHourLimit': _dynamicHourLimit,
          'dynamicPriceHourBefore': dynamicPriceHourBefore,
          'dynamicPriceHalfBefore': dynamicPriceHalfBefore,
          'dynamicPriceHourAfter': dynamicPriceHourAfter,
          'dynamicPriceHalfAfter': dynamicPriceHalfAfter,
          'pricePerHour': mainPrice,
          'pricePerHourText': priceText,
          'schedule': {
            'Luni-Vineri': '${_lvOpenCtrl.text} - ${_lvCloseCtrl.text}',
            'Sambata': '${_sOpenCtrl.text} - ${_sCloseCtrl.text}',
            'Duminica': '${_dOpenCtrl.text} - ${_dCloseCtrl.text}',
          },
          'cui': _cuiController.text.trim(),
          'iban': _ibanController.text.trim(),
          'allowHalfHour': _allowHalfHour,
          'offersSubscription': _offerSubscription,
          'subscriptionType': _subscriptionType,
          'subscriptionEntries': _offerSubscription && _subscriptionType == 'limited' ? (int.tryParse(_subscriptionEntriesController.text) ?? 10) : 0,
          'subscriptionPrice': _offerSubscription ? (double.tryParse(_subscriptionPriceController.text) ?? 150.0) : 0.0,
          'extraServices': _extraServices,
        });

        setState(() {
          _isEditing = false;
          _isSaving = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profilul a fost actualizat cu succes!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la salvare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _addBlockedDate(List<dynamic> currentBlocked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
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
      final dateStr = DateFormat('yyyy-MM-dd').format(picked);
      if (currentBlocked.contains(dateStr)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Această dată este deja blocată!'), backgroundColor: Colors.orangeAccent),
          );
        }
        return;
      }

      final List<dynamic> updated = List.from(currentBlocked)..add(dateStr);
      await FirebaseFirestore.instance.collection('venues').doc(user.uid).update({
        'blockedDates': updated,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data $dateStr a fost blocată pentru rezervări.'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _removeBlockedDate(String dateStr, List<dynamic> currentBlocked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131A2A),
        title: const Text('Deblocare Dată', style: TextStyle(color: Colors.white)),
        content: Text('Dorești să deblochezi data de $dateStr pentru rezervări standard?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deblochează', style: TextStyle(color: Color(0xFF00E5FF))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final List<dynamic> updated = List.from(currentBlocked)..remove(dateStr);
      await FirebaseFirestore.instance.collection('venues').doc(user.uid).update({
        'blockedDates': updated,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data $dateStr a fost deblocată.'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _setupStripeConnect(String? existingAccountId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF635BFF))),
      );

      String accountId = existingAccountId ?? '';

      // 1. Create account if doesn't exist
      if (accountId.isEmpty) {
        final res = await http.post(
          Uri.parse('https://us-central1-pingpongplayhub1.cloudfunctions.net/createStripeConnectAccount'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': user.email}),
        );
        if (res.statusCode == 200) {
          accountId = jsonDecode(res.body)['accountId'];
          // Save to Firestore
          await FirebaseFirestore.instance.collection('venues').doc(user.uid).update({
            'stripeAccountId': accountId,
          });
        } else {
          throw Exception('Failed to create account: ${res.body}');
        }
      }

      // 2. Create account link
      final linkRes = await http.post(
        Uri.parse('https://us-central1-pingpongplayhub1.cloudfunctions.net/createStripeAccountLink'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'accountId': accountId}),
      );

      if (mounted) {
        Navigator.pop(context); // close loader
      }

      if (linkRes.statusCode == 200) {
        final url = jsonDecode(linkRes.body)['url'];
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } else {
          throw Exception('Nu s-a putut deschide linkul de Stripe.');
        }
      } else {
        throw Exception('Failed to create account link: ${linkRes.body}');
      }
    } catch (e) {
      if (mounted) {
        // If loader is still showing, close it
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare Stripe Connect: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showChangePasswordDialog() {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A2A),
              title: const Text('Schimbă Parola', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Parola veche'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Parola nouă'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Parola nouă trebuie să aibă minim 8 caractere, o literă mare și un simbol.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Anulează', style: TextStyle(color: Colors.redAccent)),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final oldP = oldPassCtrl.text;
                          final newP = newPassCtrl.text;

                          if (newP.length < 8 || !newP.contains(RegExp(r'[A-Z]')) || !newP.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parola nouă nu respectă condițiile!'), backgroundColor: Colors.red));
                            return;
                          }

                          setDialogState(() => isSaving = true);

                          try {
                            User? user = FirebaseAuth.instance.currentUser;
                            if (user != null && user.email != null) {
                              AuthCredential credential = EmailAuthProvider.credential(email: user.email!, password: oldP);
                              await user.reauthenticateWithCredential(credential);
                              await user.updatePassword(newP);

                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parola a fost schimbată!'), backgroundColor: Colors.green));
                              }
                            }
                          } on FirebaseAuthException catch (e) {
                            setDialogState(() => isSaving = false);
                            String msg = 'Eroare la schimbare.';
                            if (e.code == 'wrong-password' || e.code == 'invalid-credential') msg = 'Parola veche este incorectă.';
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
                          }
                        },
                  child: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Salvează'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Facility Visual Component Mapping
  Widget _buildFacilityIconTag(String key) {
    IconData iconData = Icons.done;
    String label = '';

    if (key == 'vestiare') {
      iconData = Icons.shower_outlined;
      label = 'Vestiare / Dușuri';
    } else if (key == 'aer_conditionat') {
      iconData = Icons.ac_unit_outlined;
      label = 'AC / Încălzire';
    } else if (key == 'inchiriere_palete') {
      iconData = Icons.sports_tennis_outlined;
      label = 'Închiriere Palete';
    } else if (key == 'antrenor') {
      iconData = Icons.psychology_outlined;
      label = 'Antrenor / Cursuri';
    } else if (key == 'parcare') {
      iconData = Icons.local_parking_outlined;
      label = 'Parcare Proprie';
    } else if (key == 'bar') {
      iconData = Icons.local_bar_outlined;
      label = 'Bar / Automat';
    } else {
      label = key;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, color: const Color(0xFF00E5FF), size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSportChip(String sportKey) {
    final Map<String, String> names = {
      'ping_pong': 'Ping Pong',
      'padel': 'Padel',
      'tenis': 'Tenis',
      'fotbal': 'Fotbal',
      'handbal': 'Handbal',
      'baschet': 'Baschet',
      'mma': 'MMA',
      'box': 'Box',
    };
    return Chip(
      backgroundColor: const Color(0xFF131A2A),
      side: const BorderSide(color: Color(0xFF00E5FF), width: 0.8),
      label: Text(
        names[sportKey] ?? sportKey,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetVenueId = widget.venueId ?? currentUser?.uid;

    if (targetVenueId == null) {
      return const Scaffold(body: Center(child: Text('Eroare: Nu s-a putut găsi ID-ul sălii.')));
    }
    
    // Dacă am primit venueId specific, nu permitem editarea (mod vizualizare)
    final bool isReadOnly = widget.venueId != null && widget.venueId != currentUser?.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('venues').doc(targetVenueId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(child: Text('Datele sălii nu au putut fi încărcate.')),
          );
        }

        final venueData = snapshot.data!.data() as Map<String, dynamic>;

        return Scaffold(
          drawer: isReadOnly ? null : const PlayerDrawer(activePage: 'venue_profile'),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: isReadOnly 
                ? IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  )
                : (!_isEditing
                    ? Builder(
                        builder: (context) => IconButton(
                          icon: const Icon(Icons.menu, color: Color(0xFF00E5FF)),
                          onPressed: () {
                            Scaffold.of(context).openDrawer();
                          },
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.close, color: Colors.redAccent),
                        onPressed: () {
                          setState(() {
                            _isEditing = false;
                          });
                        },
                      )),
            title: Text(_isEditing ? 'Editează Profilul Sălii' : (isReadOnly ? venueData['venueName'] ?? 'Profil Sală' : 'Profilul Sălii'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            centerTitle: true,
            actions: [
              if (!_isEditing && !isReadOnly)
                IconButton(
                  icon: const Icon(Icons.edit, color: Color(0xFF00E5FF)),
                  onPressed: () => _enterEditMode(venueData),
                ),
            ],
          ),
          body: _isSaving
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: _isEditing ? _buildEditForm() : _buildVisualProfile(venueData, targetVenueId, isReadOnly),
                ),
        );
      },
    );
  }

  Future<void> _buySubscription(String targetVenueId, Map<String, dynamic> data) async {
    final amount = double.tryParse(data['subscriptionPrice']?.toString() ?? '150') ?? 150.0;
    
    final success = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          amount: amount,
          venueId: targetVenueId,
          destinationAccountId: data['stripeAccountId'],
        ),
      ),
    );

    if (success == true) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('subscriptions').add({
          'venueId': targetVenueId,
          'type': data['subscriptionType'],
          'entries': data['subscriptionEntries'],
          'price': amount,
          'purchasedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Abonament achiziționat cu succes!'), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  Future<void> _showReviewDialog(String targetVenueId) async {
    final commentController = TextEditingController();
    double currentRating = 5.0;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A2A),
              title: const Text('Adaugă o recenzie', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < currentRating ? Icons.star : Icons.star_border,
                          color: Colors.yellowAccent,
                          size: 32,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            currentRating = index + 1.0;
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Cum a fost experiența ta?',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Anulează', style: TextStyle(color: Colors.redAccent)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
                  onPressed: () async {
                    if (commentController.text.trim().isEmpty) return;
                    final user = FirebaseAuth.instance.currentUser!;
                    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                    final username = userDoc.data()?['username'] ?? 'Jucător';
                    final avatarUrl = userDoc.data()?['avatarUrl'];

                    await FirebaseFirestore.instance
                        .collection('venues')
                        .doc(targetVenueId)
                        .collection('reviews')
                        .add({
                      'authorId': user.uid,
                      'authorUsername': username,
                      'authorAvatarUrl': avatarUrl,
                      'rating': currentRating,
                      'comment': commentController.text.trim(),
                      'createdAt': FieldValue.serverTimestamp(),
                    });

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Recenzia a fost adăugată!'), backgroundColor: Colors.green),
                      );
                    }
                  },
                  child: const Text('Trimite'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- 1. VISUAL PROFILE (READ-ONLY) ---
  Widget _buildVisualProfile(Map<String, dynamic> data, String targetVenueId, bool isReadOnly) {
    final bool isVerified = data['isVerified'] ?? false;
    final List<dynamic> facilities = data['facilities'] ?? [];
    final List<dynamic> blockedDates = data['blockedDates'] ?? [];
    final schedule = data['schedule'] ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Premium Cyberpunk Header
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF00E5FF), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                      blurRadius: 15,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: const CircleAvatar(
                  radius: 46,
                  backgroundColor: Color(0xFF131A2A),
                  child: Icon(Icons.storefront, color: Color(0xFF00E5FF), size: 50),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          data['venueName'] ?? '-',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),

        // Verification Status Badge
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isVerified ? const Color(0xFF00E5FF).withValues(alpha: 0.1) : Colors.orangeAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isVerified ? const Color(0xFF00E5FF) : Colors.orangeAccent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isVerified ? Icons.verified : Icons.hourglass_empty,
                  color: isVerified ? const Color(0xFF00E5FF) : Colors.orangeAccent,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  isVerified ? 'Club Verificat' : 'În curs de verificare',
                  style: TextStyle(
                    color: isVerified ? const Color(0xFF00E5FF) : Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),

        if (data['isPublic'] == true) ...[
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green, width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.park, color: Colors.green, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Locație Publică (Gratis)',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 30),
        const Divider(color: Colors.grey, thickness: 0.5),

        // Section 1: Business Details
        _buildSectionHeader('Informații Business'),
        _buildProfileDetailRow(Icons.person_outline, 'Administrator / Contact', data['contactPerson'] ?? '-'),
        _buildProfileDetailRow(Icons.phone_outlined, 'Telefon', data['phoneNumber'] ?? '-'),
        _buildProfileDetailRow(Icons.email_outlined, 'Email', data['email'] ?? '-'),
        _buildProfileDetailRow(Icons.language_outlined, 'Website', data['website']?.toString().isEmpty == true ? '-' : (data['website'] ?? '-')),
        _buildProfileDetailRow(Icons.location_on_outlined, 'Locație', '${data['address'] ?? '-'}, ${data['city'] ?? '-'}'),

        const SizedBox(height: 20),
        const Divider(color: Colors.grey, thickness: 0.5),

        // Section: Supported Sports
        _buildSectionHeader('Sporturi Suportate'),
        (data['supportedSports'] != null && (data['supportedSports'] as List).isNotEmpty)
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (data['supportedSports'] as List).map((s) => _buildSportChip(s.toString())).toList(),
              )
            : const Text('Doar Ping Pong (Legacy)', style: TextStyle(color: Colors.grey)),

        const SizedBox(height: 20),
        const Divider(color: Colors.grey, thickness: 0.5),

        // Section 2: Table Capacity
        _buildSectionHeader('Mese & Capacitate'),
        Row(
          children: [
            Expanded(
              child: _buildCapacityBox('Indoor', (data['indoorTables'] ?? 0).toString(), Icons.home_outlined),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildCapacityBox('Outdoor', (data['outdoorTables'] ?? 0).toString(), Icons.wb_sunny_outlined),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildCapacityBox('Total Mese', (data['totalTables'] ?? 0).toString(), Icons.sports_tennis_outlined),
            ),
          ],
        ),

        const SizedBox(height: 25),
        const Divider(color: Colors.grey, thickness: 0.5),

        // Section 3: Facilities
        _buildSectionHeader('Dotări & Facilități'),
        facilities.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Nicio facilitate selectată.', style: TextStyle(color: Colors.grey)),
              )
            : Wrap(
                spacing: 10,
                runSpacing: 10,
                children: facilities.map((f) => _buildFacilityIconTag(f.toString())).toList(),
              ),

        const SizedBox(height: 25),
        const Divider(color: Colors.grey, thickness: 0.5),

        // Section: Meniu & Servicii (Inventory)
        _buildSectionHeader('Meniu & Echipamente'),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('venues')
              .doc(targetVenueId)
              .collection('inventory')
              .snapshots(),
          builder: (context, invSnapshot) {
            if (invSnapshot.hasError) {
              return const Text('Eroare la încărcarea meniului.', style: TextStyle(color: Colors.red));
            }
            if (invSnapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator(color: Color(0xFF00E5FF));
            }

            final items = invSnapshot.data?.docs ?? [];
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Niciun produs adăugat în meniu.', style: TextStyle(color: Colors.grey)),
              );
            }

            return Column(
              children: items.map((doc) {
                final itemData = doc.data() as Map<String, dynamic>;
                final String name = itemData['name'] ?? '';
                final String category = itemData['category'] ?? '';
                final double price = (itemData['price'] as num?)?.toDouble() ?? 0.0;

                IconData iconData = Icons.local_drink;
                if (category == 'Echipament') iconData = Icons.sports_tennis;
                else if (category == 'Mâncare') iconData = Icons.restaurant;
                else if (category == 'Apă') iconData = Icons.water_drop;
                else if (category == 'Cafea') iconData = Icons.local_cafe;
                else if (category == 'Snack') iconData = Icons.fastfood;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(iconData, color: const Color(0xFF00E5FF), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            Text(category, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text('$price RON', style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),

        const SizedBox(height: 25),
        const Divider(color: Colors.grey, thickness: 0.5),

        // Section 4: Schedule
        _buildSectionHeader('Program de Funcționare'),
        _buildScheduleRow('Luni - Vineri', schedule['Luni-Vineri'] ?? '08:00 - 22:00'),
        _buildScheduleRow('Sâmbătă', schedule['Sambata'] ?? '09:00 - 21:00'),
        _buildScheduleRow('Duminică', schedule['Duminica'] ?? '09:00 - 18:00'),

        const SizedBox(height: 25),
        const Divider(color: Colors.grey, thickness: 0.5),

        // Section 5: Tariffs and Financials
        _buildSectionHeader('Tarif & Detalii Financiare'),
        _buildProfileDetailRow(
          Icons.monetization_on_outlined,
          'Tarif pe oră',
          (data['pricePerHourText'] != null && (data['pricePerHourText'] as String).isNotEmpty)
              ? data['pricePerHourText']
              : '${data['pricePerHour'] ?? 20.0} RON/oră',
        ),
        _buildProfileDetailRow(
          Icons.star_outline,
          'Abonament',
          data['offersSubscription'] == true 
              ? '${data['subscriptionPrice'] ?? 150} RON pentru ${data['subscriptionType'] == 'unlimited' ? 'Nelimitat' : '${data['subscriptionEntries']} intrări'}' 
              : 'Nu este disponibil',
        ),
        if (isReadOnly && data['offersSubscription'] == true) ...[
          const SizedBox(height: 8),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.credit_card, size: 18),
              label: const Text('Cumpără Abonament'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
              ),
              onPressed: () => _buySubscription(targetVenueId, data),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (data['extraServices'] != null && (data['extraServices'] as List).isNotEmpty)
          ...((data['extraServices'] as List).map((srv) => _buildProfileDetailRow(
                Icons.add_circle_outline,
                srv['name'] ?? 'Serviciu Extra',
                '${srv['price'] ?? 0} RON',
              )).toList())
        else
          _buildProfileDetailRow(
            Icons.add_circle_outline,
            'Servicii Extra',
            'Nu sunt disponibile',
          ),
        _buildProfileDetailRow(Icons.description_outlined, 'CUI Fiscal', data['cui']?.toString().isEmpty == true ? '-' : (data['cui'] ?? '-')),
        _buildProfileDetailRow(Icons.account_balance_wallet_outlined, 'IBAN de Plată', data['iban']?.toString().isEmpty == true ? '-' : (data['iban'] ?? '-')),
        
        if (!isReadOnly) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF635BFF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF635BFF).withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.payment, color: Color(0xFF635BFF)),
                    SizedBox(width: 8),
                    Text('Încasări prin Stripe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  (data['stripeAccountId'] != null)
                      ? 'Contul Stripe este conectat. Sunteți pregătit să încasați plăți automat în IBAN-ul dvs.'
                      : 'Pentru a putea încasa banii din rezervări, trebuie să vă conectați IBAN-ul prin Stripe.',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _setupStripeConnect(data['stripeAccountId']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF635BFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text((data['stripeAccountId'] != null) ? 'Gestionează Cont Stripe' : 'Configurați Încasări Stripe'),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 25),
        const Divider(color: Colors.grey, thickness: 0.5),

        // Section 6: Blocked Dates Management
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Zile Blocate (Fără Rezervări)'),
            if (!isReadOnly)
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00E5FF)),
                onPressed: () => _addBlockedDate(blockedDates),
              ),
          ],
        ),
        const SizedBox(height: 8),
        blockedDates.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Nicio dată blocată.', style: TextStyle(color: Colors.grey, fontSize: 14)),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: blockedDates.map((dateStr) {
                  return Chip(
                    backgroundColor: const Color(0xFF131A2A),
                    side: const BorderSide(color: Colors.redAccent, width: 0.8),
                    label: Text(
                      dateStr.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    deleteIcon: isReadOnly ? null : const Icon(Icons.cancel, color: Colors.redAccent, size: 18),
                    onDeleted: isReadOnly ? null : () => _removeBlockedDate(dateStr.toString(), blockedDates),
                  );
                }).toList(),
              ),

        const SizedBox(height: 25),
        const Divider(color: Colors.grey, thickness: 0.5),

        // Section 6.5: Trainers List
        _buildSectionHeader('Antrenori Asociați'),
        const SizedBox(height: 8),
        _buildTrainersList(targetVenueId, isReadOnly),

        const SizedBox(height: 25),
        const Divider(color: Colors.grey, thickness: 0.5),

        // Section 7: Reviews
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Recenzii Jucători'),
            if (isReadOnly)
              TextButton.icon(
                icon: const Icon(Icons.add_comment, color: Color(0xFF00E5FF), size: 16),
                label: const Text('Adaugă Recenzie', style: TextStyle(color: Color(0xFF00E5FF))),
                onPressed: () => _showReviewDialog(targetVenueId),
              ),
            if (!isReadOnly && data['rating'] != null)
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.yellowAccent, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${(data['rating'] as num).toStringAsFixed(1)} / 5.0 (${data['ratingCount'] ?? 0})',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        _buildReviewsList(targetVenueId),

        const SizedBox(height: 35),

        // Security Actions
        if (!isReadOnly)
          OutlinedButton.icon(
          onPressed: _showChangePasswordDialog,
          icon: const Icon(Icons.lock_outline),
          label: const Text('Schimbă Parola Contului'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.grey),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00E5FF),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildProfileDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF00E5FF).withValues(alpha: 0.8), size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityBox(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF00E5FF), size: 24),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleRow(String dayGroup, String hours) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(dayGroup, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
          Text(
            hours,
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 15,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainersList(String venueId, bool isReadOnly) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('isTrainer', isEqualTo: true)
          .where('trainerVenueId', isEqualTo: venueId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Niciun antrenor asociat acestei săli.', style: TextStyle(color: Colors.grey, fontSize: 14)),
          );
        }

        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
            final price = data['trainerPrice'] ?? 0;
            return Card(
              color: const Color(0xFF1E293B),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF131A2A),
                  child: Icon(Icons.sports, color: Color(0xFF00E5FF)),
                ),
                title: Text(name.isEmpty ? 'Antrenor Necunoscut' : name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('Preț: $price RON/oră', style: const TextStyle(color: Color(0xFF00E5FF))),
                trailing: isReadOnly ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.rate_review, color: Colors.yellowAccent, size: 20),
                      onPressed: () => _showTrainerReviewDialog(doc.id),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () {
                        // Rezervare antrenor (mock or actual scheduling logic)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Rezervarea antrenorului $name este în lucru!')),
                        );
                      },
                      child: const Text('Rezervă', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ) : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _showTrainerReviewDialog(String trainerId) async {
    final commentController = TextEditingController();
    double currentRating = 5.0;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF131A2A),
              title: const Text('Recenzie Antrenor', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < currentRating ? Icons.star : Icons.star_border,
                          color: Colors.yellowAccent,
                          size: 32,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            currentRating = index + 1.0;
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Părerea ta despre antrenor',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Anulează', style: TextStyle(color: Colors.redAccent)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
                  onPressed: () async {
                    if (commentController.text.trim().isEmpty) return;
                    final user = FirebaseAuth.instance.currentUser!;
                    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                    final username = userDoc.data()?['username'] ?? 'Jucător';

                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(trainerId)
                        .collection('reviews')
                        .add({
                      'authorId': user.uid,
                      'authorUsername': username,
                      'rating': currentRating,
                      'comment': commentController.text.trim(),
                      'createdAt': FieldValue.serverTimestamp(),
                    });

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Recenzie adăugată pentru antrenor!'), backgroundColor: Colors.green),
                      );
                    }
                  },
                  child: const Text('Trimite'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildReviewsList(String venueId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('venues')
          .doc(venueId)
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Nu există recenzii momentan.', style: TextStyle(color: Colors.grey, fontSize: 14)),
          );
        }

        final docs = snapshot.data!.docs;
        return Column(
          children: docs.map((doc) {
            final rData = doc.data() as Map<String, dynamic>;
            final rating = (rData['rating'] as num?)?.toInt() ?? 5;
            final comment = rData['comment'] as String? ?? '';
            final authorName = rData['authorUsername'] as String? ?? 'Jucător';
            final avatarUrl = rData['authorAvatarUrl'] as String?;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF131A2A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[800]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.grey[700],
                        backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
                        child: (avatarUrl == null || avatarUrl.isEmpty)
                            ? const Icon(Icons.person, size: 20, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          authorName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < rating ? Icons.star : Icons.star_border,
                            color: Colors.yellowAccent,
                            size: 16,
                          );
                        }),
                      ),
                    ],
                  ),
                  if (comment.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(comment, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // --- EDIT MODE VIEW ---
  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Actualizează Datele Clubului',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // Venue name
          _buildTextField(
            controller: _venueNameController,
            label: 'Nume Sală / Club',
            validator: (value) => value!.isEmpty ? 'Introdu numele sălii!' : null,
          ),
          const SizedBox(height: 16),

          // Contact person
          _buildTextField(
            controller: _contactPersonController,
            label: 'Nume Administrator / Persoană de contact',
            validator: (value) => value!.isEmpty ? 'Introdu numele contactului!' : null,
          ),
          const SizedBox(height: 16),

          // Phone
          _buildTextField(
            controller: _phoneController,
            label: 'Telefon Business',
            keyboardType: TextInputType.phone,
            validator: (value) => value!.isEmpty ? 'Introdu numărul de telefon!' : null,
          ),
          const SizedBox(height: 16),

          // City
          CitySelectorField(
            selectedCity: _cityController.text.isEmpty ? null : _cityController.text,
            cityOptions: romanianCities,
            onCitySelected: (val) {
              setState(() {
                _cityController.text = val;
              });
            },
            validator: (value) => value == null || value.isEmpty ? 'Introdu orașul!' : null,
          ),
          const SizedBox(height: 16),

          // Address
          _buildTextField(
            controller: _addressController,
            label: 'Adresă Completă',
            validator: (value) => value!.isEmpty ? 'Introdu adresa completă!' : null,
          ),
          const SizedBox(height: 16),

          // Website
          _buildTextField(
            controller: _websiteController,
            label: 'Website / Rețele Sociale (Opțional)',
          ),
          const SizedBox(height: 24),

          const Text(
            'Capacitate (Mese)',
            style: TextStyle(color: Color(0xFF00E5FF), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _indoorTablesController,
                  label: 'Mese Indoor',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value!.isEmpty) return 'Introdu nr.';
                    if (int.tryParse(value) == null) return 'Invalid';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  controller: _outdoorTablesController,
                  label: 'Mese Outdoor',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value!.isEmpty) return 'Introdu nr.';
                    if (int.tryParse(value) == null) return 'Invalid';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Facilities Selection
          const Text(
            'Facilități Incluse',
            style: TextStyle(color: Color(0xFF00E5FF), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _buildFacilityCheckbox('vestiare', 'Vestiare / Dușuri'),
          _buildFacilityCheckbox('aer_conditionat', 'Aer condiționat / Încălzire'),
          _buildFacilityCheckbox('inchiriere_palete', 'Închiriere palete / mingi'),
          _buildFacilityCheckbox('antrenor', 'Antrenor personal / Cursuri'),
          _buildFacilityCheckbox('parcare', 'Parcare proprie'),
          _buildFacilityCheckbox('bar', 'Bar / Automat de băuturi'),

          const SizedBox(height: 24),

          // Operating hours selection
          const Text(
            'Program de Funcționare',
            style: TextStyle(color: Color(0xFF00E5FF), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildScheduleEditRow('Luni - Vineri', _lvOpenCtrl, _lvCloseCtrl),
          _buildScheduleEditRow('Sâmbătă', _sOpenCtrl, _sCloseCtrl),
          _buildScheduleEditRow('Duminică', _dOpenCtrl, _dCloseCtrl),

          const SizedBox(height: 24),

          const Text(
            'Tarife & Informații Financiare',
            style: TextStyle(color: Color(0xFF00E5FF), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

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
          if (_priceType == 'flat') ...[
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
            ),
          ] else ...[
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
            ),
          ],
          const SizedBox(height: 16),

          _buildTextField(
            controller: _cuiController,
            label: 'CUI Fiscal (Opțional)',
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _ibanController,
            label: 'IBAN de Plată',
            validator: (value) => value!.isEmpty ? 'Introdu codul IBAN pentru viramente!' : null,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Permite Rezervări la Jumătate de Oră', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('Jucătorii pot alege intervale de tip 16:30 - 17:30', style: TextStyle(color: Colors.white54, fontSize: 11)),
            value: _allowHalfHour,
            activeThumbColor: const Color(0xFF00E5FF),
            onChanged: (val) => setState(() => _allowHalfHour = val),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Oferă Abonament Lunar', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('Jucătorii pot cumpăra abonament pentru ore nelimitate/limitate.', style: TextStyle(color: Colors.white54, fontSize: 11)),
            value: _offerSubscription,
            activeThumbColor: const Color(0xFF00E5FF),
            onChanged: (val) => setState(() => _offerSubscription = val),
          ),
          if (_offerSubscription) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _subscriptionType,
              dropdownColor: const Color(0xFF131A2A),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Tip Abonament',
                prefixIcon: Icon(Icons.merge_type),
              ),
              items: const [
                DropdownMenuItem(value: 'unlimited', child: Text('Intrări Nelimitate')),
                DropdownMenuItem(value: 'limited', child: Text('Număr Limitat de Intrări')),
              ],
              onChanged: (val) {
                setState(() {
                  _subscriptionType = val ?? 'unlimited';
                });
              },
            ),
            if (_subscriptionType == 'limited') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _subscriptionEntriesController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Număr Intrări pe Lună',
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                ),
                validator: (value) {
                  if (_offerSubscription && _subscriptionType == 'limited') {
                    if (value == null || value.trim().isEmpty) return 'Introdu numărul de intrări';
                    if (int.tryParse(value) == null) return 'Valoare invalidă';
                  }
                  return null;
                },
              ),
            ],
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
          const SizedBox(height: 16),
          _buildSectionHeader('Alte Servicii Extra (ex: Antrenor, Masaj)'),
          const Text(
            'Adaugă servicii speciale, altele decât produsele de bar sau echipamentele de închiriat (vezi Secțiunea Meniu & Echipamente pentru bar).',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 35),

          // Form Actions
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _isEditing = false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Anulează', style: TextStyle(color: Colors.redAccent, fontSize: 16)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Salvează', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF00E5FF), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey[800]!),
        ),
        errorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildFacilityCheckbox(String key, String title) {
    return CheckboxListTile(
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
      value: _tempFacilities[key],
      activeColor: const Color(0xFF00E5FF),
      checkColor: Colors.black,
      contentPadding: EdgeInsets.zero,
      onChanged: (bool? val) {
        setState(() {
          _tempFacilities[key] = val ?? false;
        });
      },
    );
  }

  Widget _buildScheduleEditRow(String label, TextEditingController openCtrl, TextEditingController closeCtrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _selectTime(context, openCtrl),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[800]!),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  openCtrl.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF00E5FF), fontFamily: 'monospace', fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('la', style: TextStyle(color: Colors.grey)),
          ),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _selectTime(context, closeCtrl),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[800]!),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  closeCtrl.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF00E5FF), fontFamily: 'monospace', fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
