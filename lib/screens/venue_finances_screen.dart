import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VenueFinancesScreen extends StatefulWidget {
  final String venueId;

  const VenueFinancesScreen({super.key, required this.venueId});

  @override
  State<VenueFinancesScreen> createState() => _VenueFinancesScreenState();
}

class _VenueFinancesScreenState extends State<VenueFinancesScreen> {
  bool _isLoading = true;
  double _totalCash = 0.0;
  double _totalCard = 0.0;
  double _totalRefunded = 0.0;
  int _totalBookings = 0;

  @override
  void initState() {
    super.initState();
    _loadFinances();
  }

  Future<void> _loadFinances() async {
    setState(() => _isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('matches')
          .where('locationId', isEqualTo: widget.venueId)
          .get();

      double cash = 0.0;
      double card = 0.0;
      double refunded = 0.0;
      int bookingsCount = 0;

      for (var doc in snap.docs) {
        final data = doc.data();
        final String status = data['status'] ?? 'open';
        final String paymentMethod = data['paymentMethod'] ?? '';
        final String paymentStatus = data['paymentStatus'] ?? '';
        final double price = (data['price'] as num?)?.toDouble() ?? 0.0;
        final double refundedAmount = (data['refundedAmount'] as num?)?.toDouble() ?? 0.0;

        bookingsCount++;

        if (status == 'cancelled') {
          if (paymentStatus == 'refunded') {
            refunded += refundedAmount;
          }
          continue; // Don't add to cash/card if it was cancelled
        }

        if (paymentMethod.contains('Card') && paymentStatus == 'confirmed') {
          card += price;
        } else if (paymentMethod.contains('Cash') && paymentStatus == 'confirmed') {
          cash += price;
        } else if (paymentStatus == 'pending') {
          // You might not want to count pending cash or card yet, but usually we don't count pending towards "Incasat"
        }
      }

      setState(() {
        _totalCash = cash;
        _totalCard = card;
        _totalRefunded = refunded;
        _totalBookings = bookingsCount;
      });
    } catch (e) {
      debugPrint('Eroare la incarcarea finantelor: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        title: const Text('Panou Financiar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF131A2A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00E5FF)),
            onPressed: _loadFinances,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : RefreshIndicator(
              onRefresh: _loadFinances,
              color: const Color(0xFF00E5FF),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Statistici Încasări',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildFinanceCard(
                      title: 'Total Cash Încasat',
                      amount: _totalCash,
                      icon: Icons.money,
                      color: const Color(0xFF00FF66),
                    ),
                    const SizedBox(height: 12),
                    _buildFinanceCard(
                      title: 'Total Card Încasat',
                      amount: _totalCard,
                      icon: Icons.credit_card,
                      color: const Color(0xFF00E5FF),
                    ),
                    const SizedBox(height: 12),
                    _buildFinanceCard(
                      title: 'Total Returnat (Refund)',
                      amount: _totalRefunded,
                      icon: Icons.assignment_return,
                      color: const Color(0xFFFF0055),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Număr Total Rezervări',
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                          Text(
                            '$_totalBookings',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFinanceCard({required String title, required double amount, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '${amount.toStringAsFixed(2)} RON',
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
