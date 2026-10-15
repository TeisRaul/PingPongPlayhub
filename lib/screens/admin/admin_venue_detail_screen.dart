import 'package:flutter/material.dart';
import '../../utils/hour_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../venue_signup_screen.dart';
import 'add_public_location_screen.dart';
import 'admin_bar_inventory_screen.dart';
import 'admin_reports_screen.dart';
import '../../theme/app_theme.dart';

class AdminVenueDetailScreen extends StatefulWidget {
  final String venueId;
  final Map<String, dynamic> venueData;

  const AdminVenueDetailScreen({
    super.key,
    required this.venueId,
    required this.venueData,
  });

  @override
  State<AdminVenueDetailScreen> createState() => _AdminVenueDetailScreenState();
}

class _AdminVenueDetailScreenState extends State<AdminVenueDetailScreen> {
  late TextEditingController _nameController;
  late TextEditingController _cityController;
  bool _isLoading = false;
  late bool _isVerified;

  @override
  void initState() {
    super.initState();
    _isVerified = widget.venueData['isVerified'] != false;
    _nameController = TextEditingController(text: widget.venueData['venueName'] ?? '');
    _cityController = TextEditingController(text: widget.venueData['city'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _setVerified(bool value) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).update({
        'isVerified': value,
      });
      if (mounted) {
        setState(() => _isVerified = value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'Sala a fost aprobată.' : 'Verificarea sălii a fost retrasă.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateVenueDetails() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).update({
        'venueName': _nameController.text.trim(),
        'city': _cityController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Detalii actualizate!'), backgroundColor: Colors.green),
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

  void _manageMatches() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminVenueMatchesScreen(
          venueId: widget.venueId,
          posProvider: widget.venueData['posProvider'] ?? 'none',
        ),
      ),
    );
  }

  Future<void> _deleteVenue() async {
    final bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Ștergere Sală', style: TextStyle(color: AppColors.text)),
        content: Text('Ești sigur că vrei să ștergi această locație? Acțiunea este ireversibilă.', style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Anulează', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Șterge', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);
      try {
        await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).delete();
        if (mounted) {
          Navigator.pop(context); // back to venues list
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Locația a fost ștearsă!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Detalii Sală', style: TextStyle(color: AppColors.text, fontSize: 18)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _isLoading ? null : _deleteVenue,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                labelText: 'Nume Sală',
                labelStyle: TextStyle(color: AppColors.muted),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.muted)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cityController,
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                labelText: 'Oraș',
                labelStyle: TextStyle(color: AppColors.muted),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.muted)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.venueData['isPublic'] != true) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (_isVerified ? AppColors.accent : Colors.orangeAccent).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _isVerified ? AppColors.accent : Colors.orangeAccent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isVerified ? Icons.verified : Icons.hourglass_empty,
                          color: _isVerified ? AppColors.accent : Colors.orangeAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isVerified ? 'Sală verificată' : 'În așteptarea aprobării',
                          style: TextStyle(
                            color: _isVerified ? AppColors.accent : Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isVerified
                          ? 'Sala apare jucătorilor și poate organiza turnee.'
                          : 'Sala nu apare jucătorilor până nu o aprobi.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _setVerified(!_isVerified),
                      icon: Icon(_isVerified ? Icons.block : Icons.check_circle, size: 18),
                      label: Text(_isVerified ? 'Retrage verificarea' : 'Aprobă sala'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isVerified ? Colors.redAccent : AppColors.good,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Detalii Terenuri', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Mese/Terenuri Indoor:', style: TextStyle(color: AppColors.muted)),
                      Text('${widget.venueData['indoorTables'] ?? widget.venueData['totalTables'] ?? 0}', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Mese/Terenuri Outdoor:', style: TextStyle(color: AppColors.muted)),
                      Text('${widget.venueData['outdoorTables'] ?? 0}', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _updateVenueDetails,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black))
                  : const Text('Salvează Nume/Oraș', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                if (widget.venueData['isPublic'] == true) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddPublicLocationScreen(
                        isEditMode: true,
                        venueId: widget.venueId,
                        venueData: widget.venueData,
                      ),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VenueSignupScreen(
                        isEditMode: true,
                        venueId: widget.venueId,
                        venueData: widget.venueData,
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.edit_document),
              label: const Text('Editează Sală Complet (Formular)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: Colors.amberAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.amberAccent),
              ),
            ),
            const SizedBox(height: 32),
            Divider(color: AppColors.muted),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminBarInventoryScreen(venueId: widget.venueId),
                  ),
                );
              },
              icon: const Icon(Icons.local_cafe),
              label: const Text('Gestionează Bar / Consumație', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: AppColors.text,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _manageMatches,
              icon: const Icon(Icons.list_alt),
              label: const Text('Gestionează Meciuri (Plăți)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: AppColors.text,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminReportsScreen(venueId: widget.venueId),
                  ),
                );
              },
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Rapoarte și Casierie (Z, X)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: AppColors.good,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: AppColors.good),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _showPOSConfigDialog(context);
              },
              icon: const Icon(Icons.settings_cell),
              label: const Text('Configurare Smart POS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.blueAccent),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _deleteVenue,
              icon: const Icon(Icons.delete),
              label: const Text('Șterge Sală', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPOSConfigDialog(BuildContext context) {
    String currentPOS = widget.venueData['posProvider'] ?? 'none';
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.card2,
              title: Text('Configurare Smart POS', style: TextStyle(color: AppColors.text)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Selectează sistemul POS folosit în locație pentru App-to-App integration:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 16),
                  RadioListTile<String>(
                    title: Text('Niciunul (POS Tradițional)', style: TextStyle(color: AppColors.text)),
                    activeColor: AppColors.accent,
                    value: 'none',
                    groupValue: currentPOS,
                    onChanged: (val) => setDialogState(() => currentPOS = val!),
                  ),
                  RadioListTile<String>(
                    title: Text('Viva Wallet', style: TextStyle(color: AppColors.text)),
                    activeColor: AppColors.accent,
                    value: 'viva',
                    groupValue: currentPOS,
                    onChanged: (val) => setDialogState(() => currentPOS = val!),
                  ),
                  RadioListTile<String>(
                    title: Text('SumUp', style: TextStyle(color: AppColors.text)),
                    activeColor: AppColors.accent,
                    value: 'sumup',
                    groupValue: currentPOS,
                    onChanged: (val) => setDialogState(() => currentPOS = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Anulează', style: TextStyle(color: AppColors.muted)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).update({
                      'posProvider': currentPOS,
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configurație POS salvată!'), backgroundColor: Colors.green));
                      // Refresh the screen state to reflect changes if needed
                      setState(() {
                        widget.venueData['posProvider'] = currentPOS;
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                  child: const Text('Salvează'),
                ),
              ],
            );
          }
        );
      }
    );
  }
}

class AdminVenueMatchesScreen extends StatelessWidget {
  final String venueId;
  final String posProvider;
  
  const AdminVenueMatchesScreen({
    super.key, 
    required this.venueId,
    required this.posProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Meciuri Sală', style: TextStyle(color: AppColors.text, fontSize: 18)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('matches')
            .where('locationId', isEqualTo: venueId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.accent));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text('Niciun meci înregistrat la această sală.', style: TextStyle(color: AppColors.muted)),
            );
          }

          final matches = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: matches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = matches[index];
              final data = doc.data() as Map<String, dynamic>;
              final date = data['date'] ?? 'Fără dată';
              final startHour = data['startHour'] ?? 0;
              final status = data['status'] ?? 'open';
              final paymentStatus = data['paymentStatus'] ?? 'none';

              return Card(
                color: AppColors.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text('$date | Ora ${formatHour(startHour)}', style: TextStyle(color: AppColors.text)),
                  subtitle: Text('Status: $status | Plată: $paymentStatus', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  trailing: ElevatedButton(
                    onPressed: () {
                      _showMatchAdminOptions(context, doc.id, data, posProvider);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Administrează'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showMatchAdminOptions(BuildContext context, String matchId, Map<String, dynamic> data, String posProvider) {
    final List<dynamic> barItems = data['barOrderItems'] ?? [];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Opțiuni Admin Meci', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (barItems.isNotEmpty) ...[
              Text('Consumație Bar Curentă:', style: TextStyle(color: AppColors.text70, fontWeight: FontWeight.bold)),
              ...barItems.map((item) => Text('- ${item['name']} (x${item['quantity']}) - ${item['price']} RON', style: TextStyle(color: AppColors.muted))),
              const SizedBox(height: 16),
            ],
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showAddBarItemDialog(context, matchId, data);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
              child: const Text('Adaugă Consumație Bar (Tab)'),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
                        'paymentStatus': 'confirmed',
                        'paymentMethod': 'Cash la locație',
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Încasat Cash!'), backgroundColor: Colors.green));
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.good, foregroundColor: Colors.black),
                    child: const Text('Încasează Cash', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
                        'paymentStatus': 'confirmed',
                        'paymentMethod': 'Card la POS fizic',
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Încasat pe POS (Card)!'), backgroundColor: Colors.blueAccent));
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                    child: const Text('Încasează Card (POS)', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
            if (posProvider != 'none') ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  _launchSmartPOS(context, data['price'] ?? 0.0, matchId, posProvider);
                },
                icon: const Icon(Icons.contactless),
                label: Text('Trimite către Smart POS ($posProvider)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.card2,
                  foregroundColor: AppColors.accent,
                  side: BorderSide(color: AppColors.accent),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
                  'status': 'cancelled',
                  'paymentStatus': 'refunded',
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meci anulat și plată rambursată!'), backgroundColor: Colors.orange));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Anulează Meci (Refund)'),
            ),
          ],
        ),
      ),
    );
  }

  void _launchSmartPOS(BuildContext context, num amount, String matchId, String provider) async {
    // import 'package:url_launcher/url_launcher.dart'; // Trebuie adăugat la nivel global
    
    // Convert to minor units (bani / cents) depending on provider, for RO usually RON * 100
    final int amountInMinorUnits = (amount * 100).toInt();
    
    Uri? uri;
    if (provider == 'viva') {
      uri = Uri.parse('vivapay://pay/v1?amount=$amountInMinorUnits&merchantRef=$matchId&callback=pingpongplayhub://pos-success?matchId=$matchId');
    } else if (provider == 'sumup') {
      // https://developer.sumup.com/docs/sumup-app/
      uri = Uri.parse('sumupmerchant://pay/1.0?amount=${amount.toStringAsFixed(2)}&currency=RON&affiliate-key=YOUR_AFFILIATE_KEY&callback=pingpongplayhub://pos-success?matchId=$matchId');
    }
    
    if (uri != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Se lansează POS-ul $provider...')));
      
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare la lansarea aplicației POS: $e')));
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('POS Provider necunoscut.')));
    }
  }

  void _showAddBarItemDialog(BuildContext context, String matchId, Map<String, dynamic> matchData) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Meniu Bar', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('venues').doc(venueId).collection('inventory').where('isActive', isEqualTo: true).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(child: Text('Nu există produse în bar.', style: TextStyle(color: AppColors.muted)));
                      }
                      
                      final items = snapshot.data!.docs;
                      return ListView.builder(
                        controller: scrollController,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final doc = items[index];
                          final data = doc.data() as Map<String, dynamic>;
                          return ListTile(
                            title: Text(data['name'] ?? '', style: TextStyle(color: AppColors.text)),
                            subtitle: Text('${data['price']} RON', style: TextStyle(color: AppColors.muted)),
                            trailing: IconButton(
                              icon: Icon(Icons.add_circle, color: AppColors.accent),
                              onPressed: () async {
                                // Add to match
                                List<dynamic> currentItems = List.from(matchData['barOrderItems'] ?? []);
                                bool found = false;
                                for (var i = 0; i < currentItems.length; i++) {
                                  if (currentItems[i]['id'] == doc.id) {
                                    currentItems[i]['quantity'] = (currentItems[i]['quantity'] ?? 0) + 1;
                                    found = true;
                                    break;
                                  }
                                }
                                if (!found) {
                                  currentItems.add({
                                    'id': doc.id,
                                    'name': data['name'],
                                    'price': data['price'],
                                    'quantity': 1,
                                  });
                                }
                                
                                double currentPrice = (matchData['price'] ?? 0.0).toDouble();
                                currentPrice += (data['price'] ?? 0).toDouble();
                                
                                await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
                                  'barOrderItems': currentItems,
                                  'price': currentPrice,
                                });
                                
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produs adăugat pe notă!'), backgroundColor: Colors.green));
                                }
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          }
        );
      },
    );
  }
}
