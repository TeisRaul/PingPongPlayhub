import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/billing_service.dart';
import '../theme/app_theme.dart';

/// Abonamentul Playhub al sălii: stare, activare și gestionare.
class VenueSubscriptionScreen extends StatefulWidget {
  const VenueSubscriptionScreen({super.key});

  @override
  State<VenueSubscriptionScreen> createState() => _VenueSubscriptionScreenState();
}

class _VenueSubscriptionScreenState extends State<VenueSubscriptionScreen> {
  bool _busy = false;
  bool _required = false;

  @override
  void initState() {
    super.initState();
    BillingService.subscriptionRequired().then((v) {
      if (mounted) setState(() => _required = v);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Abonament Playhub'), backgroundColor: Colors.transparent, elevation: 0),
      body: uid == null
          ? const Center(child: Text('Nu ești autentificat.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('venues').doc(uid).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final venue = snap.data!.data();
                final bool active = BillingService.isActive(venue);
                final String status = BillingService.status(venue);
                final DateTime? manual = BillingService.manualUntil(venue);
                final DateTime? end = BillingService.periodEnd(venue);
                final bool hasCustomer = (venue?['billing'] is Map) && (venue!['billing']['stripeCustomerId'] != null);
                final bool cancelling = (venue?['billing'] is Map) && venue!['billing']['cancelAtPeriodEnd'] == true;

                String title;
                String detail;
                Color color;
                if (manual != null && manual.isAfter(DateTime.now())) {
                  title = 'Perioadă gratuită';
                  detail = 'Acordată de Playhub până la ${_fmt(manual)}.';
                  color = Colors.greenAccent;
                } else if (status == 'active' || status == 'trialing') {
                  title = 'Abonament activ';
                  detail = end == null
                      ? 'Abonamentul este activ.'
                      : (cancelling ? 'Se oprește la ${_fmt(end)} (anulat).' : 'Se reînnoiește la ${_fmt(end)}.');
                  color = Colors.greenAccent;
                } else if (status == 'past_due') {
                  title = 'Plată restantă';
                  detail = 'Nu am putut încasa abonamentul. Actualizează metoda de plată în „Gestionează”.';
                  color = Colors.orangeAccent;
                } else {
                  title = 'Abonament inactiv';
                  detail = status.isEmpty ? 'Nu ai încă un abonament.' : 'Ultima stare: $status.';
                  color = Colors.redAccent;
                }

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(detail, style: TextStyle(color: AppColors.text70)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '100 lei / lună',
                      style: TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Abonamentul include rezervările făcute prin aplicație, rapoartele de check-in și vizibilitatea sălii pentru jucători. '
                      'Plățile cu cardul au în plus un service fee de 5 lei per rezervare, reținut automat. '
                      'Poți anula oricând din „Gestionează”.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    if (!_required)
                      Text(
                        'Momentan abonamentul nu este obligatoriu, iar sala ta rămâne vizibilă.',
                        style: TextStyle(color: AppColors.text54, fontSize: 12, fontStyle: FontStyle.italic),
                      )
                    else if (!active)
                      const Text(
                        'Fără abonament activ, sala nu mai apare jucătorilor la rezervare.',
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                      ),
                    const SizedBox(height: 20),
                    if (!active || status == 'canceled')
                      ElevatedButton.icon(
                        onPressed: _busy ? null : () => _run(BillingService.startCheckout),
                        icon: const Icon(Icons.workspace_premium_outlined),
                        label: const Text('Activează abonamentul'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    if (hasCustomer) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _run(BillingService.openPortal),
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Gestionează abonamentul / metoda de plată'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: AppColors.muted),
                        ),
                      ),
                    ],
                    if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
                  ],
                );
              },
            ),
    );
  }
}
