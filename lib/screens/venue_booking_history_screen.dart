import 'package:flutter/material.dart';
import '../utils/hour_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'check_in_flow.dart';
import '../theme/app_theme.dart';

class VenueBookingHistoryScreen extends StatefulWidget {
  final String venueName;

  /// Id-ul sălii (uid-ul contului de sală). Dacă lipsește, se folosește utilizatorul curent.
  final String? venueId;

  const VenueBookingHistoryScreen({super.key, required this.venueName, this.venueId});

  @override
  State<VenueBookingHistoryScreen> createState() => _VenueBookingHistoryScreenState();
}

class _VenueBookingHistoryScreenState extends State<VenueBookingHistoryScreen> {
  String _statusFilter = 'Toate'; // 'Toate', 'Finalizate', 'Anulate', 'Trecute'
  bool _isLoading = false;

  Future<void> _confirmPayment(String docId) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('matches').doc(docId).update({
        'paymentStatus': 'confirmed',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plată cash confirmată cu succes!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Eroare: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isPastMatch(String dateStr, double endHour) {
    try {
      final matchEnd = dateAtHour(dateStr, endHour);
      return DateTime.now().isAfter(matchEnd);
    } catch (_) {
      return false;
    }
  }

  void _openScanner() {
    CheckInFlow.scan(
      context,
      venueId: widget.venueId ?? FirebaseAuth.instance.currentUser?.uid,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.accent),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Istoric Rezervări & Meciuri',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Filter Tabs Bar
          Container(
            color: AppColors.card,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['Toate', 'Finalizate', 'Anulate', 'Trecute'].map((filter) {
                final isSelected = _statusFilter == filter;
                return InkWell(
                  onTap: () => setState(() => _statusFilter = filter),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppColors.accent : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      filter,
                      style: TextStyle(
                        color: isSelected ? AppColors.accent : Colors.white60,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('matches')
                  .where('locationName', isEqualTo: widget.venueName)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Eroare la încărcare: ${snapshot.error}',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: AppColors.accent));
                }

                final rawDocs = snapshot.data?.docs ?? [];
                
                // Filter matches based on past / cancelled / completed
                var filtered = rawDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final String status = data['status'] ?? 'open';
                  final String date = data['date'] ?? '';
                  final double endHour = hourValue(data['endHour']);
                  final bool isPast = _isPastMatch(date, endHour);

                  // A past match can be classified as historical
                  // Completed or cancelled are always historical
                  final bool isHistorical = isPast || status == 'completed' || status == 'cancelled';

                  if (!isHistorical) return false;

                  if (_statusFilter == 'Finalizate') {
                    return status == 'completed';
                  } else if (_statusFilter == 'Anulate') {
                    return status == 'cancelled';
                  } else if (_statusFilter == 'Trecute') {
                    return isPast && status != 'cancelled';
                  }
                  
                  return true;
                }).toList();

                // Sort by date/hour descending (most recent first)
                filtered.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final String aDate = aData['date'] ?? '';
                  final String bDate = bData['date'] ?? '';
                  final double aHour = hourValue(aData['startHour']);
                  final double bHour = hourValue(bData['startHour']);

                  int dateComp = bDate.compareTo(aDate);
                  if (dateComp != 0) return dateComp;
                  return bHour.compareTo(aHour);
                });

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_toggle_off, size: 48, color: AppColors.text24),
                        const SizedBox(height: 12),
                        Text(
                          'Niciun meci în istoric (${_statusFilter.toLowerCase()}).',
                          style: TextStyle(color: AppColors.text38, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final docId = filtered[index].id;
                    final data = filtered[index].data() as Map<String, dynamic>;
                    final String hostName = data['hostUsername'] ?? 'Host';
                    final String date = data['date'] ?? '';
                    final double startHour = hourValue(data['startHour']);
                    final double endHour = hourValue(data['endHour']);
                    final int tableId = data['tableId'] ?? 1;
                    final bool isFriendly = data['isFriendly'] ?? false;
                    final String status = data['status'] ?? 'open';
                    
                    final String paymentMethod = data['paymentMethod'] ?? 'Cash la locație';
                    final String paymentStatus = data['paymentStatus'] ?? 'pending';
                    final bool isCard = paymentMethod.contains('Card');
                    final bool isPaid = (isCard && paymentStatus != 'awaiting_payment') || paymentStatus == 'confirmed';
                    final double price = (data['price'] as num?)?.toDouble() ?? 0.0;

                    Color statusColor = AppColors.muted;
                    String statusText = 'TRECUT';
                    if (status == 'completed') {
                      statusColor = AppColors.good;
                      statusText = 'FINALIZAT';
                    } else if (status == 'cancelled') {
                      statusColor = Colors.redAccent;
                      statusText = 'ANULAT';
                    }

                    final bool canConfirmCash = !isPaid && !isCard && status != 'cancelled';

                    return Card(
                      color: AppColors.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: status == 'cancelled'
                              ? Colors.redAccent.withValues(alpha: 0.2)
                              : AppColors.accent.withValues(alpha: 0.1),
                          width: 1.5,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.card2,
                                  backgroundImage: data['hostAvatarUrl'] != null && (data['hostAvatarUrl'] as String).isNotEmpty
                                      ? NetworkImage(data['hostAvatarUrl'])
                                      : null,
                                  child: data['hostAvatarUrl'] == null || (data['hostAvatarUrl'] as String).isEmpty
                                      ? Text(hostName.substring(0, 1).toUpperCase(), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 12))
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    hostName,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.text),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: statusColor, width: 1),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            Divider(color: AppColors.text10, height: 20),
                            Row(
                              children: [
                                Icon(Icons.calendar_month, color: AppColors.text38, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  '$date  |  ${formatHour(startHour)} - ${formatHour(endHour)}',
                                  style: TextStyle(color: AppColors.text70, fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildBadge(Icons.table_restaurant, 'Masa $tableId', AppColors.accent),
                                _buildBadge(
                                  isFriendly ? Icons.favorite_border : Icons.emoji_events_outlined,
                                  isFriendly ? 'Amical' : 'Competitiv',
                                  isFriendly ? Colors.purpleAccent : AppColors.accent,
                                ),
                                _buildBadge(
                                  isPaid ? Icons.check_circle_outline : Icons.error_outline,
                                  isPaid
                                      ? (isCard ? 'Card (Achitat)' : 'Cash (Achitat)')
                                      : 'Cash (Neachitat)',
                                  isPaid ? AppColors.good : Colors.orangeAccent,
                                ),
                                if (price > 0)
                                  _buildBadge(
                                    Icons.payments_outlined,
                                    'De plată: ${price.toStringAsFixed(0)} RON',
                                    AppColors.gold,
                                  ),
                              ],
                            ),
                            if (canConfirmCash) ...[
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading ? null : () => _confirmPayment(docId),
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text(
                                    'CONFIRMĂ PLATĂ CASH',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.good,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scanează', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _openScanner,
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
