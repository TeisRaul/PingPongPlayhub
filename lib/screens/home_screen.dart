import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/level_utils.dart';
import 'login_screen.dart';
import 'avatar_screen.dart';
import 'my_profile_screen.dart';
import 'find_match_screen.dart';
import 'my_matches_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          userData = doc.data();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
      );
    }

    final rating = userData?['rating'] ?? 0;
    final username = userData?['username'] ?? 'Jucător';
    final avatarUrl = userData?['avatarUrl'];

    final levelDetails = LevelUtils.getLevelDetails(rating);
    final String levelName = levelDetails['levelName'];
    final double progress = levelDetails['progress'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 70, // Slightly wider to accommodate the parallelogram
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
                    child: avatarUrl == null
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
      ),
      drawer: _buildDrawer(username, levelName, progress, avatarUrl),
      body: Center(
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
                        value: progress,
                        backgroundColor: Colors.grey[800],
                        color: const Color(0xFF00E5FF),
                        strokeWidth: 4,
                      ),
                    ),
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.grey[700],
                      backgroundImage: _getAvatarProvider(avatarUrl),
                      child: avatarUrl == null
                          ? const Icon(Icons.person, color: Colors.white, size: 30)
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
                        levelName,
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
                          value: progress,
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
              children: [
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
                _buildDrawerItem(Icons.calendar_month_outlined, 'Schedule a Table', onTap: () {
                  Navigator.pop(context);
                }),
                _buildDrawerItem(Icons.group_add_outlined, 'Play with a Friend', onTap: () {
                  Navigator.pop(context);
                }),
                _buildDrawerItem(Icons.emoji_events_outlined, 'Tournaments', onTap: () {
                  Navigator.pop(context);
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
