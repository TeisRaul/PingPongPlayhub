import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';

class AdminReportsScreen extends StatefulWidget {
  final String venueId;
  const AdminReportsScreen({super.key, required this.venueId});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  DateTime _selectedDate = DateTime.now();

  Stream<QuerySnapshot> _getMatchesStream() {
    return FirebaseFirestore.instance
        .collection('matches')
        .where('venueId', isEqualTo: widget.venueId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Rapoarte și Casierie', style: TextStyle(color: AppColors.text, fontSize: 18)),
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2023),
                lastDate: DateTime.now(),
              );
              if (date != null) {
                setState(() => _selectedDate = date);
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getMatchesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.accent));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('Nu există date pentru această sală.', style: TextStyle(color: AppColors.muted)));
          }

          final allMatches = snapshot.data!.docs;
          final dateString = DateFormat('yyyy-MM-dd').format(_selectedDate);

          final todayMatches = allMatches.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final date = data['date'] ?? ''; 
            return date == dateString;
          }).toList();

          double totalCash = 0;
          double totalCardPOS = 0;
          double totalCardApp = 0;
          double totalUnpaid = 0;
          
          double totalMese = 0;
          double totalBar = 0;

          for (var doc in todayMatches) {
            final data = doc.data() as Map<String, dynamic>;
            final paymentStatus = data['paymentStatus'] ?? 'pending';
            final status = data['status'] ?? 'pending';
            final paymentMethod = data['paymentMethod'] ?? '';
            
            if (status == 'cancelled') continue; 
            
            double matchPrice = (data['price'] ?? 0).toDouble();
            
            double barCost = 0;
            final barItems = data['barOrderItems'] as List<dynamic>? ?? [];
            for (var item in barItems) {
              barCost += ((item['price'] ?? 0) * (item['quantity'] ?? 1)).toDouble();
            }
            double meseCost = matchPrice - barCost;
            if (meseCost < 0) meseCost = 0;

            if (paymentStatus == 'confirmed') {
              totalMese += meseCost;
              totalBar += barCost;

              if (paymentMethod == 'Cash la locație') {
                totalCash += matchPrice;
              } else if (paymentMethod == 'Card la POS fizic') {
                totalCardPOS += matchPrice;
              } else if (paymentMethod.contains('Card în aplicație') || paymentMethod.contains('Stripe') || paymentMethod == 'Card') {
                totalCardApp += matchPrice;
              } else {
                totalCash += matchPrice;
              }
            } else {
              totalUnpaid += matchPrice;
            }
          }

          final grandTotal = totalCash + totalCardPOS + totalCardApp;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderCard(dateString, grandTotal),
                const SizedBox(height: 16),
                _buildDetailsCard('Defalcare Metode de Plată', [
                  _DetailRow('Cash (în Sertar)', totalCash, Colors.greenAccent),
                  _DetailRow('Card la POS Fizic', totalCardPOS, Colors.blueAccent),
                  _DetailRow('Card în Aplicație', totalCardApp, Colors.orangeAccent),
                ]),
                const SizedBox(height: 16),
                _buildDetailsCard('Defalcare Servicii (Doar Încasate)', [
                  _DetailRow('Încasări Mese Ping Pong', totalMese, AppColors.text),
                  _DetailRow('Încasări Bar / Snack', totalBar, AppColors.text),
                ]),
                const SizedBox(height: 16),
                _buildDetailsCard('Restanțe / Neplătite', [
                  _DetailRow('Meciuri Active (Neîncasate)', totalUnpaid, Colors.redAccent),
                ]),
                const SizedBox(height: 32),
                Text(
                  'NOTĂ: Acest raport este STRICT PENTRU GESTIUNE INTERNĂ (Echivalent Raport X).\n\nÎnchiderea Zilei Fiscale (Raportul Z Oficial) se eliberează direct de pe casa de marcat fizică (din dotare). Asigurați-vă că totalul Cash de aici corespunde cu sertarul de bani înainte de a tipări Raportul Z fizic.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(String dateString, double grandTotal) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        children: [
          Text('Raport Schimb (Tip X)', style: TextStyle(color: AppColors.muted, fontSize: 14)),
          const SizedBox(height: 4),
          Text(DateFormat('dd MMM yyyy').format(_selectedDate), style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text('${grandTotal.toStringAsFixed(2)} RON', style: TextStyle(color: AppColors.accent, fontSize: 32, fontWeight: FontWeight.bold)),
          Text('Total Încasat (Astăzi)', style: TextStyle(color: AppColors.muted, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(String title, List<_DetailRow> rows) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
          Divider(color: AppColors.muted),
          ...rows.map((r) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(r.label, style: TextStyle(color: AppColors.muted, fontSize: 14)),
                Text('${r.amount.toStringAsFixed(2)} RON', style: TextStyle(color: r.color, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _DetailRow {
  final String label;
  final double amount;
  final Color color;

  _DetailRow(this.label, this.amount, this.color);
}
