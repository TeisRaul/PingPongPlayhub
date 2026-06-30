import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../venue_signup_screen.dart';
import 'add_public_location_screen.dart';
import 'admin_bar_inventory_screen.dart';
import 'admin_reports_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.venueData['venueName'] ?? '');
    _cityController = TextEditingController(text: widget.venueData['city'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    super.dispose();
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
        backgroundColor: const Color(0xFF131A2A),
        title: const Text('Ștergere Sală', style: TextStyle(color: Colors.white)),
        content: const Text('Ești sigur că vrei să ștergi această locație? Acțiunea este ireversibilă.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
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
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Detalii Sală', style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
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
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nume Sală',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cityController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Oraș',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF131A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[800]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Detalii Terenuri', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Mese/Terenuri Indoor:', style: TextStyle(color: Colors.grey)),
                      Text('${widget.venueData['indoorTables'] ?? widget.venueData['totalTables'] ?? 0}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Mese/Terenuri Outdoor:', style: TextStyle(color: Colors.grey)),
                      Text('${widget.venueData['outdoorTables'] ?? 0}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _updateVenueDetails,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
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
                backgroundColor: const Color(0xFF131A2A),
                foregroundColor: Colors.amberAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.amberAccent),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(color: Colors.grey),
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
                backgroundColor: const Color(0xFF131A2A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _manageMatches,
              icon: const Icon(Icons.list_alt),
              label: const Text('Gestionează Meciuri (Plăți)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF131A2A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.grey),
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
                backgroundColor: const Color(0xFF131A2A),
                foregroundColor: const Color(0xFF00FF66),
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Color(0xFF00FF66)),
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
                backgroundColor: const Color(0xFF131A2A),
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
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('Configurare Smart POS', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Selectează sistemul POS folosit în locație pentru App-to-App integration:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 16),
                  RadioListTile<String>(
                    title: const Text('Niciunul (POS Tradițional)', style: TextStyle(color: Colors.white)),
                    activeColor: const Color(0xFF00E5FF),
                    value: 'none',
                    groupValue: currentPOS,
                    onChanged: (val) => setDialogState(() => currentPOS = val!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Viva Wallet', style: TextStyle(color: Colors.white)),
                    activeColor: const Color(0xFF00E5FF),
                    value: 'viva',
                    groupValue: currentPOS,
                    onChanged: (val) => setDialogState(() => currentPOS = val!),
                  ),
                  RadioListTile<String>(
                    title: const Text('SumUp', style: TextStyle(color: Colors.white)),
                    activeColor: const Color(0xFF00E5FF),
                    value: 'sumup',
                    groupValue: currentPOS,
                    onChanged: (val) => setDialogState(() => currentPOS = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
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
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Meciuri Sală', style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF131A2A),
        iconTheme: const IconThemeData(color: Color(0xFF00E5FF)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('matches')
            .where('locationId', isEqualTo: venueId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('Niciun meci înregistrat la această sală.', style: TextStyle(color: Colors.grey)),
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
                color: const Color(0xFF131A2A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text('$date | Ora $startHour:00', style: const TextStyle(color: Colors.white)),
                  subtitle: Text('Status: $status | Plată: $paymentStatus', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: ElevatedButton(
                    onPressed: () {
                      _showMatchAdminOptions(context, doc.id, data, posProvider);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
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
      backgroundColor: const Color(0xFF131A2A),
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Opțiuni Admin Meci', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (barItems.isNotEmpty) ...[
              const Text('Consumație Bar Curentă:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              ...barItems.map((item) => Text('- ${item['name']} (x${item['quantity']}) - ${item['price']} RON', style: const TextStyle(color: Colors.grey))),
              const SizedBox(height: 16),
            ],
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showAddBarItemDialog(context, matchId, data);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
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
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66), foregroundColor: Colors.black),
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
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFF00E5FF),
                  side: const BorderSide(color: Color(0xFF00E5FF)),
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
      backgroundColor: const Color(0xFF131A2A),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (context, scrollController) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Meniu Bar', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('venues').doc(venueId).collection('inventory').where('isActive', isEqualTo: true).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text('Nu există produse în bar.', style: TextStyle(color: Colors.grey)));
                      }
                      
                      final items = snapshot.data!.docs;
                      return ListView.builder(
                        controller: scrollController,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final doc = items[index];
                          final data = doc.data() as Map<String, dynamic>;
                          return ListTile(
                            title: Text(data['name'] ?? '', style: const TextStyle(color: Colors.white)),
                            subtitle: Text('${data['price']} RON', style: const TextStyle(color: Colors.grey)),
                            trailing: IconButton(
                              icon: const Icon(Icons.add_circle, color: Color(0xFF00E5FF)),
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
