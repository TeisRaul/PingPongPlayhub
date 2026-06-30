import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../utils/level_utils.dart';
import 'login_screen.dart';
import 'admin/admin_dashboard.dart';
import 'my_profile_screen.dart';
import 'find_match_screen.dart';
import 'my_matches_screen.dart';
import 'friends_screen.dart';
import 'notifications_screen.dart';
import 'inbox_screen.dart';
import 'tournaments_screen.dart';
import 'venue_profile_screen.dart';
import 'venue_booking_history_screen.dart';
import 'venue_tables_layout_screen.dart';
import '../widgets/player_drawer.dart';

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
  bool isAdmin = false;

  final ScrollController _newsScrollController = ScrollController();
  Timer? _newsTimer;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _startNewsAutoScroll();
  }

  void _startNewsAutoScroll() {
    _newsTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_newsScrollController.hasClients) {
        double maxScroll = _newsScrollController.position.maxScrollExtent;
        double currentScroll = _newsScrollController.position.pixels;
        double delta = 1.0; // Viteza de scroll

        if (currentScroll >= maxScroll) {
          // Resetăm scroll-ul la început discret (ideal listă infinită, dar e ok așa)
          _newsScrollController.jumpTo(0);
        } else {
          _newsScrollController.jumpTo(currentScroll + delta);
        }
      }
    });
  }

  @override
  void dispose() {
    _newsTimer?.cancel();
    _newsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Super Admin Hardcode
        final bool isSuperAdmin = (user.email == 'teisraul@yahoo.co.uk');

        // First try to load from players collection (users)
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          if (mounted) {
            setState(() {
              userData = doc.data();
              isVenue = false;
              isAdmin = isSuperAdmin || (userData?['isAdmin'] == true);
              _isLoading = false;
            });
          }
        } else {
          // If not found in users, load from venues collection
          final venueDoc = await FirebaseFirestore.instance.collection('venues').doc(user.uid).get();
          if (venueDoc.exists) {
            if (mounted) {
              setState(() {
                userData = venueDoc.data();
                isVenue = true;
                isAdmin = isSuperAdmin;
                _isLoading = false;
              });
            }
          } else {
            if (mounted) {
              isAdmin = isSuperAdmin;
              setState(() => _isLoading = false);
            }
          }
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Eroare la încărcarea datelor utilizatorului: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la încărcarea profilului: $e'), backgroundColor: Colors.red),
        );
      }
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
                  // 1. Update match status and handle refund in Firestore
                  final String paymentMethod = matchData['paymentMethod'] ?? '';
                  final String paymentStatus = matchData['paymentStatus'] ?? '';
                  final double price = (matchData['price'] as num?)?.toDouble() ?? 0.0;
                  
                  Map<String, dynamic> updates = {
                    'status': 'cancelled',
                  };

                  if (paymentMethod.contains('Card') && paymentStatus == 'confirmed') {
                    updates['paymentStatus'] = 'refunded';
                    updates['refundedAmount'] = price;
                  }

                  await FirebaseFirestore.instance.collection('matches').doc(matchId).update(updates);

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
        title: const Text('Playhub'),
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
      drawer: const PlayerDrawer(activePage: 'dashboard'),
      body: isAdmin ? const AdminDashboard() : (isVenue ? _buildVenueDashboard() : _buildPlayerBody()),
    );
  }

  Widget _buildPlayerBody() {
    final rating = userData?['rating'] ?? 0;
    final levelDetails = LevelUtils.getLevelDetails(rating);
    final String levelName = levelDetails['levelName'];
    final double progress = levelDetails['progress'];
    final int currentPoints = levelDetails['currentPointsInLevel'];
    final int pointsToNext = levelDetails['pointsToNextLevel'];

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('matches')
          .where('joinedUids', arrayContains: FirebaseAuth.instance.currentUser?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        int scheduledMatchesCount = 0;
        List<QueryDocumentSnapshot> activeMatches = [];

        if (snapshot.hasData) {
          final now = DateTime.now();
          activeMatches = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final String status = data['status'] ?? 'open';
            if (status == 'cancelled' || status == 'completed') return false;

            // Filter out past matches
            final String dateStr = data['date'] ?? '';
            final int endHour = data['endHour'] ?? 0;
            if (dateStr.isNotEmpty) {
              try {
                final parts = dateStr.split('-');
                if (parts.length == 3) {
                  final matchEnd = DateTime(
                    int.parse(parts[0]),
                    int.parse(parts[1]),
                    int.parse(parts[2]),
                    endHour,
                  );
                  if (matchEnd.isBefore(now)) return false;
                }
              } catch (_) {}
            }
            return true;
          }).toList();
          scheduledMatchesCount = activeMatches.length;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Salut, ${userData?['username'] ?? 'Jucător'}!',
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Bun venit în arena Playhub!',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 1. Rank Panel
              Card(
                elevation: 8,
                color: const Color(0xFF131A2A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.3), width: 1.5),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF131A2A),
                        const Color(0xFF0A0E17),
                        const Color(0xFF00E5FF).withValues(alpha: 0.06),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Text(
                              levelName.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'RATING JUCĂTOR',
                                style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$rating PTS',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Progres Nivel',
                            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '$currentPoints / ${currentPoints + pointsToNext} XP',
                            style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.grey[900],
                          color: const Color(0xFF00E5FF),
                          minHeight: 10,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Mai ai nevoie de $pointsToNext puncte pentru a trece la următorul nivel!',
                        style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 2. Quick Stats Grid
              Row(
                children: [
                  _buildDashboardStatCard(
                    'Meciuri Active',
                    '$scheduledMatchesCount',
                    Icons.sports_tennis,
                    const Color(0xFF00E5FF),
                  ),
                  const SizedBox(width: 12),
                  _buildDashboardStatCard(
                    'Victorii',
                    '${userData?['wins'] ?? 8}',
                    Icons.emoji_events_outlined,
                    const Color(0xFFFF0055),
                  ),
                  const SizedBox(width: 12),
                  _buildDashboardStatCard(
                    'Win Rate',
                    '${userData?['winRate'] ?? "60%"}',
                    Icons.trending_up,
                    const Color(0xFF00FF66),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 3. News & Trivia Section
              const Text(
                'Noutăți & Curiozități',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),
              _buildNewsTriviaSection(),
              
              const SizedBox(height: 24),

              // 4. My Active Matches List
              const Text(
                'Meciurile Mele Programate',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),

              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
              else if (activeMatches.isEmpty)
                Card(
                  color: const Color(0xFF131A2A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 44, color: Colors.grey[600]),
                        const SizedBox(height: 12),
                        const Text(
                          'Nu ai meciuri active programate.',
                          style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Fii primul care lansează o provocare sau alătură-te unui meci deschis în comunitate!',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const FindMatchScreen()),
                            );
                          },
                          icon: const Icon(Icons.search, size: 18, color: Colors.black),
                          label: const Text('Caută Meciuri', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E5FF),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: activeMatches.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final docId = activeMatches[index].id;
                    final matchData = activeMatches[index].data() as Map<String, dynamic>;
                    
                    final String hostName = matchData['hostUsername'] ?? 'Jucător';
                    final String date = matchData['date'] ?? '';
                    final int startHour = matchData['startHour'] ?? 0;
                    final int endHour = matchData['endHour'] ?? 0;
                    final String location = matchData['locationName'] ?? 'Sală';
                    final int tableId = matchData['tableId'] ?? 1;
                    final bool isFriendly = matchData['isFriendly'] ?? false;
                    final String status = matchData['status'] ?? 'open';
                    final List<dynamic> joined = matchData['joinedPlayers'] ?? [];
                    final String visibility = matchData['visibility'] ?? 'Public';
                    final bool isPrivate = visibility.toLowerCase() == 'private';
                    final double price = (matchData['price'] as num?)?.toDouble() ?? 0.0;

                    Color statusColor = const Color(0xFF00E5FF);
                    if (status == 'matched') {
                      statusColor = const Color(0xFF00FF66);
                    }

                    return Card(
                      color: const Color(0xFF131A2A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
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
                                  radius: 18,
                                  backgroundColor: const Color(0xFF1E293B),
                                  backgroundImage: matchData['hostAvatarUrl'] != null && (matchData['hostAvatarUrl'] as String).isNotEmpty
                                      ? _getAvatarProvider(matchData['hostAvatarUrl'])
                                      : null,
                                  child: matchData['hostAvatarUrl'] == null || (matchData['hostAvatarUrl'] as String).isEmpty
                                      ? Text(hostName.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hostName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (!((matchData['hostUid'] ?? '').toString().startsWith('offline_') ||
                                          matchData['hostLevel'] == '' ||
                                          matchData['hostLevel'] == '-' ||
                                          matchData['hostUid'] == matchData['locationId']))
                                        Text(
                                          matchData['hostLevel'] ?? 'Jucător',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: statusColor, width: 1),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.grey, height: 24),
                            Row(
                              children: [
                                const Icon(Icons.calendar_month, color: Colors.grey, size: 18),
                                const SizedBox(width: 8),
                                Text('$date  |  $startHour:00 - $endHour:00', style: const TextStyle(color: Colors.white70)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, color: Colors.grey, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    location,
                                    style: const TextStyle(color: Colors.white70),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Players Avatars Row
                            if (joined.isNotEmpty) ...[
                              Row(
                                children: [
                                  const Icon(Icons.people_outline, color: Colors.grey, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${joined.length} jucători:',
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SizedBox(
                                      height: 24,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: joined.length,
                                        itemBuilder: (context, pIdx) {
                                          final p = joined[pIdx] as Map<String, dynamic>;
                                          final pName = p['username'] ?? 'Jucător';
                                          final pAvatar = p['avatarUrl'] as String?;
                                          return Tooltip(
                                            message: pName,
                                            child: Container(
                                              margin: const EdgeInsets.only(right: 6),
                                              child: CircleAvatar(
                                                radius: 12,
                                                backgroundColor: const Color(0xFF1E293B),
                                                backgroundImage: pAvatar != null && pAvatar.isNotEmpty ? _getAvatarProvider(pAvatar) : null,
                                                child: pAvatar == null || pAvatar.isEmpty
                                                    ? Text(pName.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold))
                                                    : null,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                            // Badges Row
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildBadge(Icons.table_restaurant, 'Masa $tableId', const Color(0xFF00E5FF)),
                                _buildBadge(
                                  isPrivate ? Icons.lock_outline : Icons.public,
                                  isPrivate ? 'Meci Privat' : 'Meci Public',
                                  isPrivate ? const Color(0xFFFF0055) : const Color(0xFF00E5FF),
                                ),
                                _buildBadge(
                                  isFriendly ? Icons.favorite_border : Icons.emoji_events_outlined,
                                  isFriendly ? 'Amical' : 'Competitiv',
                                  isFriendly ? Colors.purpleAccent : const Color(0xFF00E5FF),
                                ),
                                if (price > 0)
                                  _buildBadge(
                                    Icons.payments_outlined,
                                    'De plată: ${price.toStringAsFixed(0)} RON',
                                    const Color(0xFFFFD700),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboardStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF131A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsTriviaSection() {
    final List<Map<String, dynamic>> items = [
      {
        'title': 'Știai că?',
        'subtitle': 'Viteză record de smash (Ping Pong)',
        'content': 'Cel mai rapid smash din istoria tenisului de masă a fost înregistrat la 116 km/h, reușit de Lark Brandt în 2003!',
        'icon': Icons.sports_tennis,
        'color': const Color(0xFFFF9800),
      },
      {
        'title': 'Formula 1',
        'subtitle': 'Cea mai rapidă oprire',
        'content': 'Recordul absolut pentru cel mai rapid pit stop în Formula 1 este de doar 1.80 secunde, realizat de echipa McLaren în 2023!',
        'icon': Icons.directions_car,
        'color': Colors.redAccent,
      },
      {
        'title': 'Gimnastică',
        'subtitle': 'Scorul perfect',
        'content': 'Nadia Comăneci a fost prima gimnastă din istorie care a primit nota perfectă de 10 la Jocurile Olimpice de la Montreal (1976).',
        'icon': Icons.star,
        'color': Colors.amber,
      },
      {
        'title': 'Curiozitate MMA',
        'subtitle': 'Luptă fulger',
        'content': 'Cel mai scurt meci din istoria UFC a durat doar 5 secunde, record stabilit de Jorge Masvidal împotriva lui Ben Askren!',
        'icon': Icons.sports_martial_arts,
        'color': Colors.red,
      },
      {
        'title': 'Știai că? Box',
        'subtitle': 'Legenda Neînvinsă',
        'content': 'Rocky Marciano este singurul campion mondial la categoria grea care s-a retras neînvins, cu un uimitor palmares de 49-0!',
        'icon': Icons.sports_mma,
        'color': Colors.orangeAccent,
      },
      {
        'title': 'Atletism',
        'subtitle': 'Viteza Omului',
        'content': 'Usain Bolt deține recordul mondial la 100m alergare (9.58 secunde), atingând o viteză maximă de 44.72 km/h!',
        'icon': Icons.directions_run,
        'color': Colors.yellowAccent,
      },
      {
        'title': 'Natație',
        'subtitle': 'Regele Medaliilor',
        'content': 'Michael Phelps are cele mai multe medalii olimpice câștigate vreodată de un sportiv: 28 de medalii, dintre care 23 de aur!',
        'icon': Icons.pool,
        'color': Colors.lightBlue,
      },
      {
        'title': 'Legendele Tenisului',
        'subtitle': 'Record de Grand Slam-uri',
        'content': 'Novak Djokovic deține recordul absolut pentru cele mai multe titluri de Grand Slam câștigate la simplu masculin: 24!',
        'icon': Icons.sports_tennis,
        'color': Colors.lightGreenAccent,
      },
      {
        'title': 'Fotbal',
        'subtitle': 'Cel mai vechi club',
        'content': 'Sheffield FC este recunoscut ca fiind cel mai vechi club de fotbal din lume, fiind fondat oficial în 1857.',
        'icon': Icons.sports_soccer,
        'color': Colors.greenAccent,
      },
      {
        'title': 'Baschet',
        'subtitle': '100 de puncte!',
        'content': 'Wilt Chamberlain deține recordul NBA pentru cele mai multe puncte înscrise într-un singur meci: 100 de puncte în 1962!',
        'icon': Icons.sports_basketball,
        'color': Colors.deepOrangeAccent,
      },
      {
        'title': 'Volei',
        'subtitle': 'Durată record',
        'content': 'Cel mai lung meci de volei din istorie a durat 85 de ore, jucat în 2011 de o echipă din Olanda.',
        'icon': Icons.sports_volleyball,
        'color': Colors.teal,
      },
      {
        'title': 'Golf',
        'subtitle': 'Pe Lună',
        'content': 'Golful este unul dintre cele două sporturi jucate pe Lună! Astronautul Alan Shepard a lovit două mingi de golf în 1971.',
        'icon': Icons.sports_golf,
        'color': Colors.white70,
      }
    ];

    return SizedBox(
      height: 165,
      child: ListView.builder(
        controller: _newsScrollController,
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, idx) {
          final item = items[idx];
          final Color color = item['color'];

          return Container(
            width: 280,
            margin: const EdgeInsets.only(right: 14, bottom: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF131A2A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF131A2A),
                  color.withValues(alpha: 0.05),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(item['icon'], color: color, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['title'],
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['subtitle'].toString().toUpperCase(),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      item['content'],
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.35,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
              side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.3), width: 1.5),
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
                          color: isVerified ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
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
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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
                      _buildQuickStat('Tarif de bază', '${userData?['pricePerHour'] ?? 35} RON/h'),
                    ],
                  ),
                  if (userData?['pricePerHourText'] != null && (userData?['pricePerHourText'] as String).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.sell_outlined, color: Color(0xFF00E5FF), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Schemă tarifară: ${userData!['pricePerHourText']}',
                              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                    side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.4)),
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VenueBookingHistoryScreen(
                      venueName: userData?['venueName'] ?? '',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.history_outlined, size: 20),
              label: const Text('Istoric Rezervări & Meciuri'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF131A2A),
                foregroundColor: const Color(0xFF00E5FF),
                side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
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
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
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
              
              // Filter active bookings client side (exclude completed, cancelled, and past bookings)
              final docs = rawDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final String status = data['status'] ?? 'open';
                if (status == 'completed' || status == 'cancelled') return false;
                try {
                  final dateStr = data['date'] as String;
                  final endHour = data['endHour'] as int;
                  final matchEnd = DateTime.parse('$dateStr ${endHour.toString().padLeft(2, '0')}:00:00');
                  return DateTime.now().isBefore(matchEnd);
                } catch (_) {
                  return true;
                }
              }).toList();

              // Sort by date (ascending) and hour
              docs.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final String aDate = aData['date'] ?? '';
                final String bDate = bData['date'] ?? '';
                final int aHour = aData['startHour'] ?? 0;
                final int bHour = bData['startHour'] ?? 0;

                int dateComp = aDate.compareTo(bDate);
                if (dateComp != 0) return dateComp;
                return aHour.compareTo(bHour);
              });

              // Compute Today's Occupancy
              final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
              final todayMatches = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['date'] == todayStr && data['status'] != 'cancelled';
              }).toList();

              final int todayMatchesCount = todayMatches.length;

              final List<int> todayReservedTables = todayMatches
                  .map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['tableId'] as int?;
                  })
                  .where((t) => t != null)
                  .map((t) => t!)
                  .toSet()
                  .toList()
                ..sort();

              final List<String> todayIntervals = todayMatches
                  .map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final int start = data['startHour'] ?? 0;
                    final int end = data['endHour'] ?? 0;
                    return '$start:00 - $end:00';
                  })
                  .toSet()
                  .toList()
                ..sort();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- TODAY SUMMARY CARD ---
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VenueTablesLayoutScreen(
                            venueId: FirebaseAuth.instance.currentUser!.uid,
                            venueName: userData?['venueName'] ?? 'Sală de Ping-Pong',
                            isAdmin: true,
                          ),
                        ),
                      );
                    },
                    child: Card(
                      color: const Color(0xFF0D1424),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.today, color: Color(0xFF00E5FF), size: 24),
                                const SizedBox(width: 8),
                                const Text(
                                  'ASTĂZI LA CLUB',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  DateFormat('dd MMM yyyy').format(DateTime.now()),
                                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              ],
                            ),
                            const Divider(color: Color(0xFF00E5FF), height: 24, thickness: 1),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Meciuri azi', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$todayMatchesCount',
                                        style: const TextStyle(
                                          color: Color(0xFF00E5FF),
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          shadows: [
                                            Shadow(color: Color(0xFF00E5FF), blurRadius: 8),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(width: 1, height: 40, color: Colors.grey[800]),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Mese ocupate', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                      const SizedBox(height: 6),
                                      todayReservedTables.isEmpty
                                          ? const Text('Nicio masă ocupată', style: TextStyle(color: Colors.grey, fontSize: 13))
                                          : Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: todayReservedTables.map((t) {
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFF0055).withValues(alpha: 0.15),
                                                    border: Border.all(color: const Color(0xFFFF0055), width: 1),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    'Masa $t',
                                                    style: const TextStyle(
                                                      color: Color(0xFFFF0055),
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text('Intervale active azi:', style: TextStyle(color: Colors.grey, fontSize: 11)),
                            const SizedBox(height: 6),
                            todayIntervals.isEmpty
                                ? const Text('Niciun interval rezervat', style: TextStyle(color: Colors.grey, fontSize: 13))
                                : Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: todayIntervals.map((interval) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                                          border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.5), width: 1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          interval,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Bookings List Header
                  const Text(
                    'Programări active / Rezervări mese',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 12),

                  if (docs.isEmpty)
                    Card(
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
                    )
                  else
                    ListView.separated(
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
                        final String visibility = data['visibility'] ?? 'public';
                        final bool isPrivate = visibility.toLowerCase() == 'private';
                        final String payment = data['paymentMethod'] ?? 'Cash la locație';
                        final bool isCard = payment.contains('Card');

                        final String paymentStatus = data['paymentStatus'] ?? 'pending';
                        final bool isPaid = isCard || paymentStatus == 'confirmed';
                        final double price = (data['price'] as num?)?.toDouble() ?? 0.0;
                        
                        final bool canConfirmCash = !isPaid && !isCard && status != 'cancelled';

                        Color statusColor = const Color(0xFF00E5FF);
                        if (isCancelled) {
                          statusColor = Colors.redAccent;
                        } else if (status == 'matched') {
                          statusColor = Colors.greenAccent;
                        }

                        return Card(
                          color: const Color(0xFF131A2A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isCancelled ? Colors.redAccent.withValues(alpha: 0.3) : const Color(0xFF00E5FF).withValues(alpha: 0.15),
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Gazda si Status
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: const Color(0xFF1E293B),
                                      backgroundImage: data['hostAvatarUrl'] != null && (data['hostAvatarUrl'] as String).isNotEmpty
                                          ? _getAvatarProvider(data['hostAvatarUrl'])
                                          : null,
                                      child: data['hostAvatarUrl'] == null || (data['hostAvatarUrl'] as String).isEmpty
                                          ? Text(hostName.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            hostName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (!((data['hostUid'] ?? '').toString().startsWith('offline_') ||
                                              data['hostUid'] == FirebaseAuth.instance.currentUser?.uid ||
                                              data['hostLevel'] == '' ||
                                              data['hostLevel'] == '-'))
                                            Text(
                                              data['hostLevel'] ?? 'Jucător',
                                              style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF)),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: statusColor, width: 1),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(color: Colors.grey, height: 24),
                                // Data si orele
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_month, color: Colors.grey, size: 18),
                                    const SizedBox(width: 8),
                                    Text('$date  |  $startHour:00 - $endHour:00', style: const TextStyle(color: Colors.white70)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Jucatori
                                if (joined.isNotEmpty) ...[
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.people_outline, color: Colors.grey, size: 18),
                                      const SizedBox(width: 8),
                                      Text('${joined.length} jucători înscriși:', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 32,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: joined.length,
                                      itemBuilder: (context, pIdx) {
                                        final p = joined[pIdx] as Map<String, dynamic>;
                                        final pName = p['username'] ?? 'Jucător';
                                        final pAvatar = p['avatarUrl'] as String?;
                                        return Tooltip(
                                          message: pName,
                                          child: Container(
                                            margin: const EdgeInsets.only(right: 6),
                                            child: CircleAvatar(
                                              radius: 14,
                                              backgroundColor: const Color(0xFF1E293B),
                                              backgroundImage: pAvatar != null && pAvatar.isNotEmpty ? _getAvatarProvider(pAvatar) : null,
                                              child: pAvatar == null || pAvatar.isEmpty
                                                  ? Text(pName.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold))
                                                  : null,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                // Badges
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildBadge(Icons.table_restaurant, 'Masa $tableId', const Color(0xFF00E5FF)),
                                    _buildBadge(
                                      isPrivate ? Icons.lock_outline : Icons.public,
                                      isPrivate ? 'Meci Privat' : 'Meci Public',
                                      isPrivate ? const Color(0xFFFF0055) : const Color(0xFF00E5FF),
                                    ),
                                    _buildBadge(
                                      isFriendly ? Icons.favorite_border : Icons.emoji_events_outlined,
                                      isFriendly ? 'Amical' : 'Competitiv',
                                      isFriendly ? Colors.purpleAccent : const Color(0xFF00E5FF),
                                    ),
                                    _buildBadge(
                                      isPaid ? (isCard ? Icons.credit_card : Icons.check_circle_outline) : Icons.payments_outlined,
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
                                if (!isCancelled) ...[
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (canConfirmCash) ...[
                                        ElevatedButton.icon(
                                          onPressed: () => _confirmBookingPayment(docId),
                                          icon: const Icon(Icons.check, size: 16),
                                          label: const Text('CONFIRMĂ PLATĂ CASH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF00FF66),
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.redAccent),
                                          foregroundColor: Colors.redAccent,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        ),
                                        icon: const Icon(Icons.cancel_outlined, size: 18),
                                        label: const Text('ANULEAZĂ REZERVAREA'),
                                        onPressed: () => _cancelBooking(docId, data),
                                      ),
                                    ],
                                  ),
                                ]
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
         color: color.withValues(alpha: 0.08),
         border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
         borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
           Icon(icon, color: color, size: 14),
           const SizedBox(width: 6),
           Text(
             label,
             style: TextStyle(
               color: color,
               fontSize: 11,
               fontWeight: FontWeight.bold,
             ),
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

  Future<void> _confirmBookingPayment(String docId) async {
    try {
      await FirebaseFirestore.instance.collection('matches').doc(docId).update({
        'paymentStatus': 'confirmed',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plată cash confirmată cu succes!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la confirmarea plății: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
