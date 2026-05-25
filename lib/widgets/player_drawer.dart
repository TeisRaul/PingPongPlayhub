import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/level_utils.dart';
import '../screens/home_screen.dart';
import '../screens/my_profile_screen.dart';
import '../screens/find_match_screen.dart';
import '../screens/create_match_screen.dart';
import '../screens/my_matches_screen.dart';
import '../screens/friends_screen.dart';
import '../screens/tournaments_screen.dart';
import '../screens/venue_profile_screen.dart';
import '../screens/login_screen.dart';
import '../screens/venue_map_screen.dart';
import '../screens/venue_tables_layout_screen.dart';
import '../screens/venue_finances_screen.dart';

class PlayerDrawer extends StatefulWidget {
  final String activePage;

  const PlayerDrawer({
    super.key,
    required this.activePage,
  });

  @override
  State<PlayerDrawer> createState() => _PlayerDrawerState();
}

class _PlayerDrawerState extends State<PlayerDrawer> {
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
      try {
        // First try to load from players collection (users)
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          if (mounted) {
            setState(() {
              userData = doc.data();
              isVenue = false;
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
                _isLoading = false;
              });
            }
          } else {
            if (mounted) setState(() => _isLoading = false);
          }
        }
      } catch (e) {
        debugPrint('Error loading user data for drawer: $e');
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
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

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _navigateTo(String targetPage, Widget destination) {
    Navigator.pop(context); // Close Drawer
    if (widget.activePage == targetPage) {
      return; // Already on this page
    }

    if (targetPage == 'dashboard') {
      // Pop all secondary screens to return to HomeScreen root
      Navigator.popUntil(context, (route) => route.isFirst);
    } else {
      // If we are currently on the dashboard, we push the secondary screen
      if (widget.activePage == 'dashboard') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => destination),
        );
      } else {
        // If we are on another secondary screen, replace it to keep a flat navigation history
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => destination),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Drawer(
        backgroundColor: Color(0xFF0A0E17),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
        ),
      );
    }

    final rating = isVenue ? 0 : (userData?['rating'] ?? 0);
    final username = isVenue ? (userData?['venueName'] ?? 'Sală') : (userData?['username'] ?? 'Jucător');
    final avatarUrl = isVenue ? null : userData?['avatarUrl'];

    final levelDetails = LevelUtils.getLevelDetails(rating);
    final String levelName = levelDetails['levelName'];
    final double progress = levelDetails['progress'];

    return Drawer(
      backgroundColor: const Color(0xFF0A0E17),
      child: Column(
        children: [
          // Drawer Header with User Profile details
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF131A2A),
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF00E5FF),
                  width: 1.5,
                ),
              ),
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

          // Drawer Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: isVenue
                ? [
                    _buildDrawerItem(
                      icon: Icons.storefront_outlined,
                      title: 'Dashboard Sală',
                      pageKey: 'dashboard',
                      onTap: () => _navigateTo('dashboard', const HomeScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.calendar_month_outlined,
                      title: 'Plan Cameră & Rezervări',
                      pageKey: 'tables_layout',
                      onTap: () => _navigateTo(
                        'tables_layout',
                        VenueTablesLayoutScreen(
                          venueId: FirebaseAuth.instance.currentUser!.uid,
                          venueName: userData?['venueName'] ?? 'Sală de Ping-Pong',
                          isAdmin: true,
                          showBackButton: false,
                        ),
                      ),
                    ),
                    _buildDrawerItem(
                      icon: Icons.business_outlined,
                      title: 'Profilul Sălii',
                      pageKey: 'venue_profile',
                      onTap: () => _navigateTo('venue_profile', const VenueProfileScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.emoji_events_outlined,
                      title: 'Turneele Noastre',
                      pageKey: 'tournaments',
                      onTap: () => _navigateTo('tournaments', const TournamentsScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.monetization_on_outlined,
                      title: 'Panou Financiar',
                      pageKey: 'venue_finances',
                      onTap: () => _navigateTo(
                        'venue_finances',
                        VenueFinancesScreen(
                          venueId: FirebaseAuth.instance.currentUser!.uid,
                        ),
                      ),
                    ),
                  ]
                : [
                    _buildDrawerItem(
                      icon: Icons.dashboard_outlined,
                      title: 'Dashboard',
                      pageKey: 'dashboard',
                      onTap: () => _navigateTo('dashboard', const HomeScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.person_outline,
                      title: 'Profilul Meu',
                      pageKey: 'profile',
                      onTap: () => _navigateTo('profile', const MyProfileScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.sports_tennis,
                      title: 'Găsește un Meci',
                      pageKey: 'find_match',
                      onTap: () => _navigateTo('find_match', const FindMatchScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.add_circle_outline,
                      title: 'Creează un Meci',
                      pageKey: 'create_match',
                      onTap: () => _navigateTo('create_match', const CreateMatchScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.history,
                      title: 'Meciurile Mele',
                      pageKey: 'my_matches',
                      onTap: () => _navigateTo('my_matches', const MyMatchesScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.group_add_outlined,
                      title: 'Joacă cu un Prieten',
                      pageKey: 'friends',
                      onTap: () => _navigateTo('friends', const FriendsScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.emoji_events_outlined,
                      title: 'Turnee',
                      pageKey: 'tournaments',
                      onTap: () => _navigateTo('tournaments', const TournamentsScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.map_outlined,
                      title: 'Harta Sălilor',
                      pageKey: 'venue_map',
                      onTap: () => _navigateTo('venue_map', const VenueMapScreen()),
                    ),
                  ],
            ),
          ),
          
          const Divider(color: Colors.grey, height: 1),
          
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Deconectare',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 16),
            ),
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

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required String pageKey,
    required VoidCallback onTap,
  }) {
    final bool isSelected = widget.activePage == pageKey;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF00E5FF).withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? const Color(0xFF00E5FF).withOpacity(0.3) : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Icon(
          icon,
          color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? const Color(0xFF00E5FF) : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 16,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
