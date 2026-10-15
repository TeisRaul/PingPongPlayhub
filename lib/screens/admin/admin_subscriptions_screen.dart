import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/billing_service.dart';
import '../../theme/app_theme.dart';

/// Admin: abonamentele sălilor. Comutator „abonament obligatoriu" + stare per sală + perioade acordate manual.
class AdminSubscriptionsScreen extends StatelessWidget {
  const AdminSubscriptionsScreen({super.key});

  static final _db = FirebaseFirestore.instance;

  String _fmt(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

  Future<void> _setRequired(BuildContext context, bool value) async {
    try {
      await _db.collection('config').doc('billing').set({'subscriptionRequired': value}, SetOptions(merge: true));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _grant(BuildContext context, String venueId) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
      helpText: 'Gratuit până la',
    );
    if (picked == null) return;
    // Până la sfârșitul zilei alese.
    final end = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    await _db.collection('venues').doc(venueId).set({
      'billing': {'manualUntil': Timestamp.fromDate(end)},
    }, SetOptions(merge: true));
  }

  Future<void> _revoke(String venueId) async {
    await _db.collection('venues').doc(venueId).update({'billing.manualUntil': FieldValue.delete()});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abonamente săli'), backgroundColor: Colors.transparent, elevation: 0),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _db.collection('config').doc('billing').snapshots(),
            builder: (context, snap) {
              final bool required = snap.data?.data()?['subscriptionRequired'] == true;
              return SwitchListTile(
                activeColor: AppColors.accent,
                title: Text('Abonament obligatoriu', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                subtitle: Text(
                  'Când e activ, sălile fără abonament valid (sau perioadă gratuită) nu mai apar jucătorilor la rezervare. '
                  'Locațiile publice gratuite nu sunt afectate.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                value: required,
                onChanged: (v) => _setRequired(context, v),
              );
            },
          ),
          Divider(color: AppColors.muted, height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db.collection('venues').snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Eroare: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs.where((d) => d.data()['isPublic'] != true).toList()
                  ..sort((a, b) => (a.data()['venueName'] ?? '').toString().toLowerCase().compareTo((b.data()['venueName'] ?? '').toString().toLowerCase()));
                if (docs.isEmpty) {
                  return Center(child: Text('Nu există săli.', style: TextStyle(color: AppColors.muted)));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final v = d.data();
                    final bool active = BillingService.isActive(v);
                    final DateTime? manual = BillingService.manualUntil(v);
                    final DateTime? end = BillingService.periodEnd(v);
                    final String status = BillingService.status(v);
                    final bool manualActive = manual != null && manual.isAfter(DateTime.now());

                    String label;
                    if (manualActive) {
                      label = 'Gratuit până la ${_fmt(manual)}';
                    } else if (status.isEmpty) {
                      label = 'Fără abonament';
                    } else {
                      label = '$status${end != null ? ' · până la ${_fmt(end)}' : ''}';
                    }
                    final Color color = active ? Colors.greenAccent : Colors.redAccent;

                    return Card(
                      color: AppColors.card2,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    (v['venueName'] ?? d.id).toString(),
                                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: color),
                                  ),
                                  child: Text(active ? 'ACTIV' : 'INACTIV', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(label, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _grant(context, d.id),
                                  icon: const Icon(Icons.card_giftcard, size: 16),
                                  label: const Text('Acordă gratuit până la…'),
                                ),
                                if (manualActive)
                                  TextButton(onPressed: () => _revoke(d.id), child: const Text('Anulează perioada gratuită')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
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
