import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class VenueBookingHistoryScreen extends StatefulWidget {
  final String venueName;

  const VenueBookingHistoryScreen({super.key, required this.venueName});

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

  bool _isPastMatch(String dateStr, int endHour) {
    try {
      final matchEnd = DateTime.parse('$dateStr ${endHour.toString().padLeft(2, '0')}:00:00');
      return DateTime.now().isAfter(matchEnd);
    } catch (_) {
      return false;
    }
  }

  bool _isAllowedToConfirm(String dateStr, int startHour) {
    try {
      final matchStart = DateTime.parse('$dateStr ${startHour.toString().padLeft(2, '0')}:00:00');
      final allowedTime = matchStart.subtract(const Duration(minutes: 10));
      return DateTime.now().isAfter(allowedTime);
    } catch (_) {
      return true;
    }
  }

  Future<void> _processScannedCode(String docId) async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('matches').doc(docId).get();
      if (!doc.exists) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bilet invalid!'), backgroundColor: Colors.red));
        return;
      }
      
      final data = doc.data() as Map<String, dynamic>;
      if (data['locationName'] != widget.venueName) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acest bilet este pentru altă sală!'), backgroundColor: Colors.red));
        return;
      }
      
      if (data['status'] == 'cancelled') {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acest meci a fost anulat!'), backgroundColor: Colors.red));
        return;
      }

      // Show dialog to confirm
      if (mounted) {
        final hostName = data['hostUsername'] ?? 'Host';
        final price = (data['price'] as num?)?.toDouble() ?? 0.0;
        final paymentMethod = data['paymentMethod'] ?? 'Cash la locație';
        final isPaid = paymentMethod.contains('Card') || data['paymentStatus'] == 'confirmed';
        
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF131A2A),
            title: const Text('Confirmare Check-in', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Jucător: $hostName', style: const TextStyle(color: Colors.white70)),
                Text('Data: ${data['date']} | ${data['startHour']}:00 - ${data['endHour']}:00', style: const TextStyle(color: Colors.white70)),
                Text('Masa: ${data['tableId']}', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 10),
                if (!isPaid) 
                  Text('Atenție: Trebuie să încasezi ${price.toStringAsFixed(0)} RON (Cash)', style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold))
                else
                  const Text('Plata este deja achitată / confirmată.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
                onPressed: () {
                  Navigator.pop(ctx);
                  if (!isPaid) {
                    _confirmPayment(docId); // This sets paymentStatus to confirmed
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check-in realizat cu succes!'), backgroundColor: Colors.green));
                  }
                },
                child: const Text('Confirmă'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(title: const Text('Scanează Bilet'), backgroundColor: Colors.black),
          body: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                Navigator.pop(ctx);
                _processScannedCode(barcodes.first.rawValue!);
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131A2A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00E5FF)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Istoric Rezervări & Meciuri',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Filter Tabs Bar
          Container(
            color: const Color(0xFF131A2A),
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
                      color: isSelected ? const Color(0xFF00E5FF).withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF00E5FF) : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      filter,
                      style: TextStyle(
                        color: isSelected ? const Color(0xFF00E5FF) : Colors.white60,
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
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
                }

                final rawDocs = snapshot.data?.docs ?? [];
                
                // Filter matches based on past / cancelled / completed
                var filtered = rawDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final String status = data['status'] ?? 'open';
                  final String date = data['date'] ?? '';
                  final int endHour = data['endHour'] ?? 0;
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
                  final int aHour = aData['startHour'] ?? 0;
                  final int bHour = bData['startHour'] ?? 0;

                  int dateComp = bDate.compareTo(aDate);
                  if (dateComp != 0) return dateComp;
                  return bHour.compareTo(aHour);
                });

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.history_toggle_off, size: 48, color: Colors.white24),
                        const SizedBox(height: 12),
                        Text(
                          'Niciun meci în istoric (${_statusFilter.toLowerCase()}).',
                          style: const TextStyle(color: Colors.white38, fontSize: 14),
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
                    final int startHour = data['startHour'] ?? 0;
                    final int endHour = data['endHour'] ?? 0;
                    final int tableId = data['tableId'] ?? 1;
                    final bool isFriendly = data['isFriendly'] ?? false;
                    final String status = data['status'] ?? 'open';
                    
                    final String paymentMethod = data['paymentMethod'] ?? 'Cash la locație';
                    final String paymentStatus = data['paymentStatus'] ?? 'pending';
                    final bool isCard = paymentMethod.contains('Card');
                    final bool isPaid = isCard || paymentStatus == 'confirmed';
                    final double price = (data['price'] as num?)?.toDouble() ?? 0.0;

                    Color statusColor = Colors.grey;
                    String statusText = 'TRECUT';
                    if (status == 'completed') {
                      statusColor = const Color(0xFF00FF66);
                      statusText = 'FINALIZAT';
                    } else if (status == 'cancelled') {
                      statusColor = Colors.redAccent;
                      statusText = 'ANULAT';
                    }

                    final bool canConfirmCash = !isPaid && !isCard && status != 'cancelled';

                    return Card(
                      color: const Color(0xFF131A2A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: status == 'cancelled'
                              ? Colors.redAccent.withValues(alpha: 0.2)
                              : const Color(0xFF00E5FF).withValues(alpha: 0.1),
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
                                  backgroundColor: const Color(0xFF1E293B),
                                  backgroundImage: data['hostAvatarUrl'] != null && (data['hostAvatarUrl'] as String).isNotEmpty
                                      ? NetworkImage(data['hostAvatarUrl'])
                                      : null,
                                  child: data['hostAvatarUrl'] == null || (data['hostAvatarUrl'] as String).isEmpty
                                      ? Text(hostName.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    hostName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
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
                            const Divider(color: Colors.white10, height: 20),
                            Row(
                              children: [
                                const Icon(Icons.calendar_month, color: Colors.white38, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  '$date  |  $startHour:00 - $endHour:00',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildBadge(Icons.table_restaurant, 'Masa $tableId', const Color(0xFF00E5FF)),
                                _buildBadge(
                                  isFriendly ? Icons.favorite_border : Icons.emoji_events_outlined,
                                  isFriendly ? 'Amical' : 'Competitiv',
                                  isFriendly ? Colors.purpleAccent : const Color(0xFF00E5FF),
                                ),
                                _buildBadge(
                                  isPaid ? Icons.check_circle_outline : Icons.error_outline,
                                  isPaid
                                      ? (isCard ? 'Card (Achitat)' : 'Cash (Achitat)')
                                      : 'Cash (Neachitat)',
                                  isPaid ? const Color(0xFF00FF66) : Colors.orangeAccent,
                                ),
                                if (price > 0)
                                  _buildBadge(
                                    Icons.payments_outlined,
                                    'De plată: ${price.toStringAsFixed(0)} RON',
                                    const Color(0xFFFFD700),
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
                                    backgroundColor: const Color(0xFF00FF66),
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
        backgroundColor: const Color(0xFF00E5FF),
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
