import '../services/account_lookup.dart';
import '../services/push_service.dart';
import 'dart:convert';
import '../utils/hour_utils.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../l10n/app_locales.dart';
import '../l10n/strings.dart';
import '../utils/level_utils.dart';
import 'language_screen.dart';
import '../utils/match_stats.dart';
import 'check_in_flow.dart';
import '../services/trainer_service.dart';
import '../services/notification_service.dart';
import 'match_detail_screen.dart';
import 'admin/admin_dashboard.dart';
import 'find_match_screen.dart';
import 'notifications_screen.dart';
import 'inbox_screen.dart';
import 'tournaments_screen.dart';
import 'venue_booking_history_screen.dart';
import 'venue_tables_layout_screen.dart';
import 'venue_calendar_screen.dart';
import 'venue_mass_cancel_screen.dart';
import 'venue_pricing_screen.dart';
import 'venue_vouchers_screen.dart';
import '../widgets/player_drawer.dart';
import '../theme/app_theme.dart';

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
      ..color = AppColors.accent
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
    AccountLookup.ensureForCurrentUser();
    PushService.instance.onLogin();
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

  bool _languagePromptShown = false;

  /// Folosește limba salvată pe cont; dacă nu există (primul login), cere alegerea ei o singură dată.
  void _applyUserLanguage() {
    // Limba aleasă înainte de login are prioritate și se salvează pe cont.
    if (AppLocales.chosenBeforeLogin) {
      AppLocales.chosenBeforeLogin = false;
      AppLocales.saveForCurrentUser(AppLocales.current.value);
      return;
    }
    final dynamic lang = userData?['language'];
    if (lang is String && AppLocales.isSupported(lang)) {
      if (AppLocales.current.value != lang) AppLocales.apply(lang);
      return;
    }
    if (_languagePromptShown) return;
    _languagePromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LanguageScreen(firstTime: true)),
      );
    });
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
            _applyUserLanguage();
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
              _applyUserLanguage();
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

  Future<void> _scanCheckInQR() async {
    await CheckInFlow.scan(context, venueId: FirebaseAuth.instance.currentUser?.uid);
  }

  Future<void> _markNoShow(String docId, String hostUid) async {
    try {
      await FirebaseFirestore.instance.collection('matches').doc(docId).update({
        'status': 'cancelled',
        'cancellationReason': 'No-Show raportat de sală',
      });
      if (hostUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(hostUid).update({
          'trustScore': FieldValue.increment(-5),
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jucător marcat ca absent (No-Show). Penalizare aplicată.'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare: $e')));
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
            colorScheme: AppColors.scheme(
              primary: AppColors.accent,
              onPrimary: AppColors.onAccent,
              surface: AppColors.card,
              onSurface: AppColors.text,
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
              backgroundColor: AppColors.card,
              title: Text('Deblocare Dată', style: TextStyle(color: AppColors.text)),
              content: Text('Dorești să deblochezi data de $dateStr pentru rezervări standard?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Anulează', style: TextStyle(color: AppColors.muted)),
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
                  child: Text('Deblochează', style: TextStyle(color: AppColors.accent)),
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
    final double startHour = hourValue(matchData['startHour']);
    final List<dynamic> joinedUids = matchData['joinedUids'] ?? [];

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Text('Anulează Rezervarea', style: TextStyle(color: AppColors.text)),
            ],
          ),
          content: Text(
            'Sigur dorești să anulezi acest meci programat în data de $date la ora ${formatHour(startHour)}?\n\nToți jucătorii înscriși vor fi notificați automat.',
            style: TextStyle(color: AppColors.text70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Înapoi', style: TextStyle(color: AppColors.muted)),
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
                  try {
                    await TrainerService.cancelForMatch(matchId);
                  } catch (e) {
                    debugPrint('Anulare sesiune antrenor: $e');
                  }

                  // 2. Toți jucătorii înscriși primesc notificare (popup + email)
                  await NotificationService.matchCancelled(matchId, {...matchData, 'locationName': matchData['locationName'] ?? venueName}, byName: venueName);

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
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    final avatarUrl = isVenue ? null : userData?['avatarUrl'];

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
                    color: AppColors.card,
                    child: isVenue
                      ? Center(child: Icon(Icons.storefront, color: AppColors.accent, size: 24))
                      : avatarUrl == null
                        ? Center(child: Icon(Icons.person, color: AppColors.text, size: 28))
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
              icon: Icon(Icons.mail_outline, color: AppColors.text),
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
                      icon: Icon(Icons.notifications_none, color: AppColors.text),
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
                            border: Border.all(color: AppColors.bg, width: 1.5),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: TextStyle(
                              color: AppColors.text,
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
        int completedCount = 0;
        int winsCount = 0;

        if (snapshot.hasData) {
          final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
          for (final doc in snapshot.data!.docs) {
            final m = doc.data() as Map<String, dynamic>;
            if (m['status'] == 'completed') {
              completedCount++;
              if (didUserWinMatch(m, myUid)) winsCount++;
            }
          }
          final now = DateTime.now();
          activeMatches = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final String status = data['status'] ?? 'open';
            if (status == 'cancelled' || status == 'completed') return false;

            // Filter out past matches
            final String dateStr = data['date'] ?? '';
            final double endHour = hourValue(data['endHour']);
            if (dateStr.isNotEmpty) {
              try {
                final parts = dateStr.split('-');
                if (parts.length == 3) {
                  final matchEnd = dateAtHour(dateStr, endHour);
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
                          tr('home.greeting', {'name': (userData?['username'] ?? tr('drawer.fallback_player')).toString()}),
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.text),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr('home.welcome'),
                          style: TextStyle(color: AppColors.muted, fontSize: 14),
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
                color: AppColors.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3), width: 1.5),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.card,
                        AppColors.bg,
                        AppColors.accent.withValues(alpha: 0.06),
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
                              color: AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.accent, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Text(
                              levelName.toUpperCase(),
                              style: TextStyle(
                                color: AppColors.accent,
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
                              Text(
                                tr('home.rating_label'),
                                style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$rating PTS',
                                style: TextStyle(
                                  color: AppColors.text,
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
                          Text(
                            tr('home.level_progress'),
                            style: TextStyle(color: AppColors.text70, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '$currentPoints / ${currentPoints + pointsToNext} XP',
                            style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: AppColors.card2,
                          color: AppColors.accent,
                          minHeight: 10,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr('home.next_level', {'points': '$pointsToNext'}),
                        style: TextStyle(color: AppColors.muted, fontSize: 12, fontStyle: FontStyle.italic),
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
                    tr('home.stat_active'),
                    '$scheduledMatchesCount',
                    Icons.sports_tennis,
                    AppColors.accent,
                  ),
                  const SizedBox(width: 12),
                  _buildDashboardStatCard(
                    tr('home.stat_wins'),
                    '${completedCount > 0 ? winsCount : (userData?['wins'] ?? 0)}',
                    Icons.emoji_events_outlined,
                    AppColors.bad,
                  ),
                  const SizedBox(width: 12),
                  _buildDashboardStatCard(
                    tr('home.stat_winrate'),
                    completedCount > 0 ? formatWinRate(winsCount, completedCount) : '${userData?['winRate'] ?? "0%"}',
                    Icons.trending_up,
                    AppColors.good,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 3. News & Trivia Section
              Text(
                tr('home.news'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
              ),
              const SizedBox(height: 12),
              _buildNewsTriviaSection(),
              
              const SizedBox(height: 24),

              // 4. My Active Matches List
              Text(
                tr('home.my_scheduled'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
              ),
              const SizedBox(height: 12),

              if (snapshot.connectionState == ConnectionState.waiting)
                Center(child: CircularProgressIndicator(color: AppColors.accent))
              else if (activeMatches.isEmpty)
                Card(
                  color: AppColors.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 44, color: AppColors.muted2),
                        const SizedBox(height: 12),
                        Text(
                          tr('home.no_active'),
                          style: TextStyle(color: AppColors.text70, fontSize: 15, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr('home.no_active_sub'),
                          style: TextStyle(color: AppColors.muted, fontSize: 13),
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
                          label: Text(tr('home.find_matches'), style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
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
                    final matchData = activeMatches[index].data() as Map<String, dynamic>;
                    
                    final String hostName = matchData['hostUsername'] ?? 'Jucător';
                    final String date = matchData['date'] ?? '';
                    final double startHour = hourValue(matchData['startHour']);
                    final double endHour = hourValue(matchData['endHour']);
                    final String location = matchData['locationName'] ?? 'Sală';
                    final int tableId = matchData['tableId'] ?? 1;
                    final bool isFriendly = matchData['isFriendly'] ?? false;
                    final String status = matchData['status'] ?? 'open';
                    final List<dynamic> joined = matchData['joinedPlayers'] ?? [];
                    final String visibility = matchData['visibility'] ?? 'Public';
                    final bool isPrivate = visibility.toLowerCase() == 'private';
                    final double price = (matchData['price'] as num?)?.toDouble() ?? 0.0;

                    Color statusColor = AppColors.accent;
                    if (status == 'matched') {
                      statusColor = AppColors.good;
                    }

                    return GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MatchDetailScreen(matchId: activeMatches[index].id, mode: MatchDetailMode.player),
    ),
  ),
  child: Card(
                      color: AppColors.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: AppColors.accent.withValues(alpha: 0.15),
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
                                  backgroundColor: AppColors.card2,
                                  backgroundImage: matchData['hostAvatarUrl'] != null && (matchData['hostAvatarUrl'] as String).isNotEmpty
                                      ? _getAvatarProvider(matchData['hostAvatarUrl'])
                                      : null,
                                  child: matchData['hostAvatarUrl'] == null || (matchData['hostAvatarUrl'] as String).isEmpty
                                      ? Text(hostName.substring(0, 1).toUpperCase(), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold))
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hostName,
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.text),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (!((matchData['hostUid'] ?? '').toString().startsWith('offline_') ||
                                          matchData['hostLevel'] == '' ||
                                          matchData['hostLevel'] == '-' ||
                                          matchData['hostUid'] == matchData['locationId']))
                                        Text(
                                          matchData['hostLevel'] ?? 'Jucător',
                                          style: TextStyle(fontSize: 12, color: AppColors.accent),
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
                            Divider(color: AppColors.muted, height: 24),
                            Row(
                              children: [
                                Icon(Icons.calendar_month, color: AppColors.muted, size: 18),
                                const SizedBox(width: 8),
                                Text('$date  |  ${formatHour(startHour)} - ${formatHour(endHour)}', style: TextStyle(color: AppColors.text70)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined, color: AppColors.muted, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    location,
                                    style: TextStyle(color: AppColors.text70),
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
                                  Icon(Icons.people_outline, color: AppColors.muted, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    tr('home.players_count', {'count': '${joined.length}'}),
                                    style: TextStyle(color: AppColors.muted, fontSize: 12),
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
                                                backgroundColor: AppColors.card2,
                                                backgroundImage: pAvatar != null && pAvatar.isNotEmpty ? _getAvatarProvider(pAvatar) : null,
                                                child: pAvatar == null || pAvatar.isEmpty
                                                    ? Text(pName.substring(0, 1).toUpperCase(), style: TextStyle(fontSize: 8, color: AppColors.text, fontWeight: FontWeight.bold))
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
                                _buildBadge(Icons.table_restaurant, 'Masa $tableId', AppColors.accent),
                                _buildBadge(
                                  isPrivate ? Icons.lock_outline : Icons.public,
                                  isPrivate ? tr('home.match_private') : tr('home.match_public'),
                                  isPrivate ? AppColors.bad : AppColors.accent,
                                ),
                                _buildBadge(
                                  isFriendly ? Icons.favorite_border : Icons.emoji_events_outlined,
                                  isFriendly ? tr('match.friendly') : tr('match.competitive'),
                                  isFriendly ? Colors.purpleAccent : AppColors.accent,
                                ),
                                if (price > 0)
                                  _buildBadge(
                                    Icons.payments_outlined,
                                    tr('home.to_pay', {'amount': price.toStringAsFixed(0)}),
                                    AppColors.gold,
                                  ),
                              ],
                            ),
                          ],
                        ),
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
          color: AppColors.card,
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
              style: TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: AppColors.muted,
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
        'color': AppColors.text70,
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
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.card,
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
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      item['content'],
                      style: TextStyle(
                        color: AppColors.text70,
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
            color: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3), width: 1.5),
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
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.text),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text('Cont de Sală / Partener', style: TextStyle(color: AppColors.accent, fontSize: 14)),
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
                        color: AppColors.accent.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.sell_outlined, color: AppColors.accent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Schemă tarifară: ${userData!['pricePerHourText']}',
                              style: TextStyle(color: AppColors.text, fontSize: 13, height: 1.3),
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
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.text,
                    side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
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
                    backgroundColor: AppColors.accent,
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
                backgroundColor: AppColors.card,
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => VenueCalendarScreen(venueId: FirebaseAuth.instance.currentUser!.uid, venueName: userData?['venueName'] ?? '')),
                    ).then((_) => _loadUserData());
                  },
                  icon: const Icon(Icons.calendar_view_day_outlined, size: 20),
                  label: const Text('Calendar pe zile (mută rezervări)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.accent,
                    side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => VenueMassCancelScreen(venueId: FirebaseAuth.instance.currentUser!.uid, venueName: userData?['venueName'] ?? '')),
                    ).then((_) => _loadUserData());
                  },
                  icon: const Icon(Icons.event_busy_outlined, size: 20),
                  label: const Text('Anulare în masă'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.accent,
                    side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => VenuePricingScreen(venueId: FirebaseAuth.instance.currentUser!.uid)),
                    ).then((_) => _loadUserData());
                  },
                  icon: const Icon(Icons.sell_outlined, size: 20),
                  label: const Text('Prețuri'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.accent,
                    side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                )),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const VenueVouchersScreen()));
              },
              icon: const Icon(Icons.confirmation_number_outlined, size: 20),
              label: const Text('Vouchere / coduri de reducere'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),

          if (blockedDates.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Zile blocate pentru public:', style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
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
                return Center(child: CircularProgressIndicator(color: AppColors.accent));
              }

              final rawDocs = snapshot.data?.docs ?? [];
              
              // Filter active bookings client side (exclude completed, cancelled, and past bookings)
              final docs = rawDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final String status = data['status'] ?? 'open';
                if (status == 'completed' || status == 'cancelled') return false;
                try {
                  final dateStr = data['date'] as String;
                  final endHour = hourValue(data['endHour']);
                  final matchEnd = dateAtHour(dateStr, endHour);
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
                final double aHour = hourValue(aData['startHour']);
                final double bHour = hourValue(bData['startHour']);

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
                    final double start = hourValue(data['startHour']);
                    final double end = hourValue(data['endHour']);
                    return '${formatHour(start)} - ${formatHour(end)}';
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
                      color: AppColors.bgDeep,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: AppColors.accent, width: 1.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.today, color: AppColors.accent, size: 24),
                                const SizedBox(width: 8),
                                Text(
                                  'ASTĂZI LA CLUB',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  DateFormat('dd MMM yyyy').format(DateTime.now()),
                                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                                ),
                              ],
                            ),
                            Divider(color: AppColors.accent, height: 24, thickness: 1),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Meciuri azi', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$todayMatchesCount',
                                        style: TextStyle(
                                          color: AppColors.accent,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          shadows: [
                                            Shadow(color: AppColors.accent, blurRadius: 8),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(width: 1, height: 40, color: AppColors.border),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Mese ocupate', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                                      const SizedBox(height: 6),
                                      todayReservedTables.isEmpty
                                          ? Text('Nicio masă ocupată', style: TextStyle(color: AppColors.muted, fontSize: 13))
                                          : Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: todayReservedTables.map((t) {
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.bad.withValues(alpha: 0.15),
                                                    border: Border.all(color: AppColors.bad, width: 1),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    'Masa $t',
                                                    style: TextStyle(
                                                      color: AppColors.bad,
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
                            Text('Intervale active azi:', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                            const SizedBox(height: 6),
                            todayIntervals.isEmpty
                                ? Text('Niciun interval rezervat', style: TextStyle(color: AppColors.muted, fontSize: 13))
                                : Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: todayIntervals.map((interval) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent.withValues(alpha: 0.1),
                                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.5), width: 1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          interval,
                                          style: TextStyle(
                                            color: AppColors.text70,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Programări active / Rezervări mese',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _scanCheckInQR(),
                        icon: const Icon(Icons.qr_code_scanner, color: Colors.black, size: 18),
                        label: const Text('SCAN QR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (docs.isEmpty)
                    Card(
                      color: AppColors.card,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 48, color: AppColors.muted),
                            SizedBox(height: 12),
                            Text('Nicio programare activă.', style: TextStyle(color: AppColors.muted, fontSize: 15)),
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
                        final double startHour = hourValue(data['startHour']);
                        final double endHour = hourValue(data['endHour']);
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

                        Color statusColor = AppColors.accent;
                        if (isCancelled) {
                          statusColor = Colors.redAccent;
                        } else if (status == 'matched') {
                          statusColor = Colors.greenAccent;
                        }

                        return GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MatchDetailScreen(matchId: docId, mode: MatchDetailMode.venue),
    ),
  ),
  child: Card(
                          color: AppColors.card,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isCancelled ? Colors.redAccent.withValues(alpha: 0.3) : AppColors.accent.withValues(alpha: 0.15),
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
                                      backgroundColor: AppColors.card2,
                                      backgroundImage: data['hostAvatarUrl'] != null && (data['hostAvatarUrl'] as String).isNotEmpty
                                          ? _getAvatarProvider(data['hostAvatarUrl'])
                                          : null,
                                      child: data['hostAvatarUrl'] == null || (data['hostAvatarUrl'] as String).isEmpty
                                          ? Text(hostName.substring(0, 1).toUpperCase(), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold))
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            hostName,
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.text),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (!((data['hostUid'] ?? '').toString().startsWith('offline_') ||
                                              data['hostUid'] == FirebaseAuth.instance.currentUser?.uid ||
                                              data['hostLevel'] == '' ||
                                              data['hostLevel'] == '-'))
                                            Text(
                                              data['hostLevel'] ?? 'Jucător',
                                              style: TextStyle(fontSize: 12, color: AppColors.accent),
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
                                Divider(color: AppColors.muted, height: 24),
                                // Data si orele
                                Row(
                                  children: [
                                    Icon(Icons.calendar_month, color: AppColors.muted, size: 18),
                                    const SizedBox(width: 8),
                                    Text('$date  |  ${formatHour(startHour)} - ${formatHour(endHour)}', style: TextStyle(color: AppColors.text70)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Jucatori
                                if (joined.isNotEmpty) ...[
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Icon(Icons.people_outline, color: AppColors.muted, size: 18),
                                      const SizedBox(width: 8),
                                      Text('${joined.length} jucători înscriși:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
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
                                              backgroundColor: AppColors.card2,
                                              backgroundImage: pAvatar != null && pAvatar.isNotEmpty ? _getAvatarProvider(pAvatar) : null,
                                              child: pAvatar == null || pAvatar.isEmpty
                                                  ? Text(pName.substring(0, 1).toUpperCase(), style: TextStyle(fontSize: 10, color: AppColors.text, fontWeight: FontWeight.bold))
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
                                    _buildBadge(Icons.table_restaurant, 'Masa $tableId', AppColors.accent),
                                    _buildBadge(
                                      isPrivate ? Icons.lock_outline : Icons.public,
                                      isPrivate ? tr('home.match_private') : tr('home.match_public'),
                                      isPrivate ? AppColors.bad : AppColors.accent,
                                    ),
                                    _buildBadge(
                                      isFriendly ? Icons.favorite_border : Icons.emoji_events_outlined,
                                      isFriendly ? tr('match.friendly') : tr('match.competitive'),
                                      isFriendly ? Colors.purpleAccent : AppColors.accent,
                                    ),
                                    _buildBadge(
                                      isPaid ? (isCard ? Icons.credit_card : Icons.check_circle_outline) : Icons.payments_outlined,
                                      isPaid
                                          ? (isCard ? 'Card (Achitat)' : 'Cash (Achitat)')
                                          : 'Cash (Neachitat)',
                                      isPaid ? AppColors.good : Colors.orangeAccent,
                                    ),
                                    if (price > 0)
                                      _buildBadge(
                                        Icons.payments_outlined,
                                        tr('home.to_pay', {'amount': price.toStringAsFixed(0)}),
                                        AppColors.gold,
                                      ),
                                  ],
                                ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.end,
                                    children: [
                                      if (canConfirmCash)
                                        ElevatedButton.icon(
                                          onPressed: () => _confirmBookingPayment(docId),
                                          icon: const Icon(Icons.check, size: 16),
                                          label: const Text('CONFIRMĂ PLATĂ CASH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.good,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                        ),
                                      if (!isCancelled && !(data['checkedIn'] == true))
                                        ElevatedButton.icon(
                                          onPressed: () => CheckInFlow.processCode(
                                            context,
                                            docId,
                                            venueId: FirebaseAuth.instance.currentUser?.uid,
                                          ),
                                          icon: const Icon(Icons.how_to_reg, size: 16),
                                          label: Text(
                                            data['waiting'] == true ? 'CHECK-IN (AȘTEAPTĂ)' : 'CHECK-IN',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.accent,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                        ),
                                      if (!isCancelled && !(data['checkedIn'] == true))
                                        ElevatedButton.icon(
                                          onPressed: () => _markNoShow(docId, data['hostUid'] ?? ''),
                                          icon: const Icon(Icons.person_off, size: 16),
                                          label: const Text('NO-SHOW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                        ),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.redAccent),
                                          foregroundColor: Colors.redAccent,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                        icon: const Icon(Icons.cancel_outlined, size: 16),
                                        label: const Text('ANULEAZĂ', style: TextStyle(fontSize: 11)),
                                        onPressed: () => _cancelBooking(docId, data),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
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
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.card2),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: AppColors.muted, fontSize: 11), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
      ),
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
