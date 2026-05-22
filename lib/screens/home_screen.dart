import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils/level_utils.dart';
import 'login_screen.dart';
import 'my_profile_screen.dart';
import 'find_match_screen.dart';
import 'my_matches_screen.dart';
import 'friends_screen.dart';
import 'notifications_screen.dart';
import 'inbox_screen.dart';
import 'tournaments_screen.dart';
import 'venue_profile_screen.dart';

class ParallelogramClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    double skew = size.width * 0.2;
    path.moveTo(skew, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width - skew, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class ParallelogramBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    double skew = size.width * 0.2;
    Path path = Path();
    path.moveTo(skew, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width - skew, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? userData;
  bool _isLoading = true;
  bool isVenue = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // First try to load from players collection (users)
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          userData = doc.data();
          isVenue = false;
          _isLoading = false;
        });
      } else {
        // If not found in users, load from venues collection
        final venueDoc = await FirebaseFirestore.instance.collection('venues').doc(user.uid).get();
        if (venueDoc.exists) {
          setState(() {
            userData = venueDoc.data();
            isVenue = true;
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  ImageProvider? _getAvatarProvider(String? url) {
    if (url == null) return null;
    if (url.startsWith('data:image')) {
      return MemoryImage(base64Decode(url.split(',').last));
    }
    if (url.startsWith('assets/')) {
      return AssetImage(url);
    }
    return NetworkImage(url);
  }

  Future<void> _blockDate(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || userData == null) return;

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
      final List<dynamic> blockedDates = List.from(userData!['blockedDates'] ?? []);

      if (blockedDates.contains(dateStr)) {
        // Ask to unblock
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF131A2A),
              title: const Text('Deblocare Dată', style: TextStyle(color: Colors.white)),
              content: Text('Dorești să deblochezi data de $dateStr pentru rezervări standard?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    blockedDates.remove(dateStr);
                    await FirebaseFirestore.instance.collection('venues').doc(user.uid).update({
                      'blockedDates': blockedDates,
                    });
                    _loadUserData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Data $dateStr a fost deblocată!'), backgroundColor: Colors.green),
                      );
                    }
                  },
                  child: const Text('Deblochează', style: TextStyle(color: Color(0xFF00E5FF))),
                ),
              ],
            ),
          );
        }
      } else {
        // Block date
        blockedDates.add(dateStr);
        await FirebaseFirestore.instance.collection('venues').doc(user.uid).update({
          'blockedDates': blockedDates,
        });
        _loadUserData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Data $dateStr a fost blocată pentru turneu / eveniment!'), backgroundColor: Colors.orangeAccent),
          );
        }
      }
    }
  }

  Future<void> _cancelBooking(String matchId, Map<String, dynamic> matchData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || userData == null) return;

    final String venueName = userData!['venueName'] ?? 'Sală';
    final String date = matchData['date'] ?? '';
    final int startHour = matchData['startHour'] ?? 0;
    final List<dynamic> joinedUids = matchData['joinedUids'] ?? [];

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF131A2A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Text('Anulează Rezervarea', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            'Sigur dorești să anulezi acest meci programat în data de $date la ora $startHour:00?\n\nToți jucătorii înscriși vor fi notificați automat.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Înapoi', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  // 1. Update match status in Firestore
                  await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
                    'status': 'cancelled',
                  });

                  // 2. Send notifications to all participants
                  final batch = FirebaseFirestore.instance.batch();
                  for (var playerUid in joinedUids) {
                    if (playerUid != user.uid) {
                      final notifyRef = FirebaseFirestore.instance.collection('notifications').doc();
                      batch.set(notifyRef, {
                        'toUid': playerUid,
                        'fromUid': user.uid,
                        'fromUsername': venueName,
                        'title': 'Meci Anulat de Club',
                        'body': 'Meciul tău din $date de la ora $startHour:00 de la $venueName a fost anulat din motive administrative.',
                        'type': 'match_cancel',
                        'status': 'pending',
                        'timestamp': FieldValue.serverTimestamp(),
                      });
                    }
                  }
                  await batch.commit();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Rezervarea a fost anulată cu succes!'), backgroundColor: Colors.redAccent),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Eroare la anulare: $e'), backgroundColor: Colors.redAccent),
                    );
                  }
                }
              },
              child: const Text('ANULEAZĂ REZERVAREA', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
      );
    }

    final rating = isVenue ? 0 : (userData?['rating'] ?? 0);
    final username = isVenue ? (userData?['venueName'] ?? 'Sală') : (userData?['username'] ?? 'Jucător');
    final avatarUrl = isVenue ? null : userData?['avatarUrl'];

    final levelDetails = LevelUtils.getLevelDetails(rating);
    final String levelName = levelDetails['levelName'];
    final double progress = levelDetails['progress'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 70,
        leading: Builder(
          builder: (context) => GestureDetector(
            onTap: () {
              Scaffold.of(context).openDrawer();
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
              child: CustomPaint(
                painter: ParallelogramBorderPainter(),
                child: ClipPath(
                  clipper: ParallelogramClipper(),
                  child: Container(
                    width: 50,
                    height: 50,
                    color: const Color(0xFF131A2A),
                    child: isVenue
                      ? const Center(child: Icon(Icons.storefront, color: Color(0xFF00E5FF), size: 24))
                      : avatarUrl == null
                        ? const Center(child: Icon(Icons.person, color: Colors.white, size: 28))
                        : Image(
                            image: _getAvatarProvider(avatarUrl)!,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        title: const Text('PingPong Playhub'),
        centerTitle: true,
        actions: [
          if (!isVenue) ...[
            IconButton(
              icon: const Icon(Icons.mail_outline, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InboxScreen()),
                );
              },
            ),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('toUid', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                int count = 0;
                if (snapshot.hasData) {
                  count = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['status'] == 'pending' && data['type'] != 'friend_request';
                  }).length;
                }
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none, color: Colors.white),
                      onPressed: () {
                        NotificationsDialog.show(context);
                      },
                    ),
                    if (count > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF0A0E17), width: 1.5),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(width: 8),
          ]
        ],
      ),
      drawer: _buildDrawer(username, levelName, progress, avatarUrl),
      body: isVenue ? _buildVenueDashboard() : _buildPlayerBody(username, levelName),
    );
  }

  Widget _buildPlayerBody(String username, String levelName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Salut, $username!',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Nivel curent: $levelName',
            style: const TextStyle(fontSize: 18, color: Color(0xFF00E5FF)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Acesta este ecranul principal. Folosește meniul din stânga sus (Avatar) pentru a naviga.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildVenueDashboard() {
    final bool isVerified = userData?['isVerified'] ?? false;
    final List<dynamic> blockedDates = userData?['blockedDates'] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Welcome Card
          Card(
            color: const Color(0xFF131A2A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userData?['venueName'] ?? 'Club Tenis',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            const Text('Cont de Sală / Partener', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 14)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isVerified ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isVerified ? Colors.green : Colors.orange, width: 1),
                        ),
                        child: Text(
                          isVerified ? 'VERIFICATĂ' : 'NEVERIFICATĂ',
                          style: TextStyle(
                            color: isVerified ? Colors.greenAccent : Colors.orangeAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!isVerified)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orangeAccent, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Contul este în curs de verificare. Nu vei apărea în listele sau pe hărțile jucătorilor până când nu este aprobat manual.',
                              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  // General stats
                  Row(
                    children: [
                      _buildQuickStat('Mese Indoor', '${userData?['indoorTables'] ?? 0}'),
                      const SizedBox(width: 12),
                      _buildQuickStat('Mese Outdoor', '${userData?['outdoorTables'] ?? 0}'),
                      const SizedBox(width: 12),
                      _buildQuickStat('Preț estimativ', '${userData?['pricePerHour'] ?? 35} RON/h'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Actions
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _blockDate(context),
                  icon: const Icon(Icons.block_outlined, size: 20),
                  label: const Text('Blochează Dată'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF131A2A),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TournamentsScreen()),
                    );
                  },
                  icon: const Icon(Icons.emoji_events_outlined, size: 20),
                  label: const Text('Turneele Noastre'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          if (blockedDates.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Zile blocate pentru public:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: blockedDates.length,
                itemBuilder: (context, index) {
                  final String blockedDate = blockedDates[index];
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(blockedDate, style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () async {
                            final List<dynamic> updated = List.from(blockedDates);
                            updated.remove(blockedDate);
                            await FirebaseFirestore.instance.collection('venues').doc(FirebaseAuth.instance.currentUser!.uid).update({
                              'blockedDates': updated,
                            });
                            _loadUserData();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Data $blockedDate a fost deblocată!'), backgroundColor: Colors.green),
                            );
                          },
                          child: const Icon(Icons.cancel, color: Colors.orangeAccent, size: 16),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Bookings List Header
          const Text(
            'Programări active / Rezervări mese',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),

          // Bookings Stream
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('matches')
                .where('locationName', isEqualTo: userData?['venueName'])
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Eroare la încărcarea programărilor: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
              }

              final rawDocs = snapshot.data?.docs ?? [];
              
              // Filter and sort client side
              final docs = rawDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                // show open/matched active bookings
                return data['status'] != 'completed';
              }).toList();

              docs.sort((a, b) {
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

              if (docs.isEmpty) {
                return Card(
                  color: const Color(0xFF131A2A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('Nicio programare activă.', style: TextStyle(color: Colors.grey, fontSize: 15)),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final docId = docs[index].id;
                  final data = docs[index].data() as Map<String, dynamic>;
                  final String hostName = data['hostUsername'] ?? 'Host';
                  final String date = data['date'] ?? '';
                  final int startHour = data['startHour'] ?? 0;
                  final int endHour = data['endHour'] ?? 0;
                  final int tableId = data['tableId'] ?? 1;
                  final bool isFriendly = data['isFriendly'] ?? false;
                  final String status = data['status'] ?? 'open';
                  final List<dynamic> joined = data['joinedPlayers'] ?? [];
                  
                  final bool isCancelled = status == 'cancelled';

                  Color statusColor = const Color(0xFF00E5FF);
                  if (isCancelled) statusColor = Colors.redAccent;
                  else if (status == 'matched') statusColor = Colors.greenAccent;

                  return Card(
                    color: const Color(0xFF131A2A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isCancelled ? Colors.redAccent.withOpacity(0.3) : const Color(0xFF00E5FF).withOpacity(0.15),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Gazdă: $hostName',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.calendar_month, color: Colors.grey, size: 18),
                              const SizedBox(width: 6),
                              Text('$date  |  $startHour:00 - $endHour:00', style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.table_restaurant, color: Colors.grey, size: 18),
                              const SizedBox(width: 6),
                              Text('Masa $tableId', style: const TextStyle(color: Colors.white70)),
                              const SizedBox(width: 24),
                              Icon(isFriendly ? Icons.emoji_emotions_outlined : Icons.emoji_events_outlined, color: Colors.grey, size: 18),
                              const SizedBox(width: 6),
                              Text(isFriendly ? 'Amical' : 'Competitiv', style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.people_outline, color: Colors.grey, size: 18),
                              const SizedBox(width: 6),
                              Text('Jucători: ${joined.length} înscriși', style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                          if (!isCancelled) ...[
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.redAccent),
                                  foregroundColor: Colors.redAccent,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                ),
                                icon: const Icon(Icons.cancel_outlined, size: 18),
                                label: const Text('ANULEAZĂ REZERVAREA'),
                                onPressed: () => _cancelBooking(docId, data),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E17),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(String username, String levelName, double progress, String? avatarUrl) {
    return Drawer(
      backgroundColor: const Color(0xFF0A0E17),
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF131A2A),
            ),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 65,
                      height: 65,
                      child: CircularProgressIndicator(
                        value: isVenue ? 1.0 : progress,
                        backgroundColor: Colors.grey[800],
                        color: const Color(0xFF00E5FF),
                        strokeWidth: 4,
                      ),
                    ),
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.grey[700],
                      backgroundImage: avatarUrl != null ? _getAvatarProvider(avatarUrl) : null,
                      child: avatarUrl == null
                          ? Icon(isVenue ? Icons.storefront : Icons.person, color: Colors.white, size: 30)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        username,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isVenue ? 'Partener Club' : levelName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF00E5FF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: isVenue ? 1.0 : progress,
                          backgroundColor: Colors.grey[800],
                          color: const Color(0xFF00E5FF),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: isVenue
                ? [
                    _buildDrawerItem(Icons.storefront_outlined, 'Dashboard Sală', onTap: () {
                      Navigator.pop(context);
                    }),
                    _buildDrawerItem(Icons.business_outlined, 'Profilul Sălii', onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const VenueProfileScreen()),
                      ).then((_) => _loadUserData());
                    }),
                    _buildDrawerItem(Icons.emoji_events_outlined, 'Turneele Noastre', onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TournamentsScreen()),
                      );
                    }),
                  ]
                : [
                    _buildDrawerItem(Icons.person_outline, 'My Profile', onTap: () {
                      Navigator.pop(context); // Close Drawer
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MyProfileScreen()),
                      ).then((_) => _loadUserData()); // Refresh on return
                    }),
                    _buildDrawerItem(Icons.sports_tennis, 'Find a Match', onTap: () {
                      Navigator.pop(context); // Close Drawer
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FindMatchScreen()),
                      );
                    }),
                    _buildDrawerItem(Icons.history, 'My Matches', onTap: () {
                      Navigator.pop(context); // Close Drawer
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MyMatchesScreen()),
                      ).then((_) => _loadUserData()); // Refresh on return
                    }),
                    _buildDrawerItem(Icons.group_add_outlined, 'Play with a Friend', onTap: () {
                      Navigator.pop(context); // Close Drawer
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FriendsScreen()),
                      );
                    }),
                    _buildDrawerItem(Icons.emoji_events_outlined, 'Tournaments', onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TournamentsScreen()),
                      );
                    }),
                  ],
            ),
          ),
          const Divider(color: Colors.grey),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Deconectare', style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              Navigator.pop(context);
              _logout();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, {required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      onTap: onTap,
    );
  }
}
