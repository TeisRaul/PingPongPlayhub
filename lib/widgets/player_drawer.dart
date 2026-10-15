import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../l10n/app_locales.dart';
import '../l10n/strings.dart';
import '../screens/language_screen.dart';
import '../services/push_service.dart';
import '../screens/privacy_data_screen.dart';
import '../widgets/theme_picker.dart';
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
import '../screens/venue_subscription_screen.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/my_stats_screen.dart';
import '../screens/trainer_dashboard.dart';
import '../screens/client_sessions_screen.dart';
import '../screens/feed_screen.dart';
import '../theme/app_theme.dart';

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
    await PushService.instance.onLogout(); // înainte de signOut, cât timp ai încă acces
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
      return Drawer(
        backgroundColor: AppColors.bg,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    final rating = isVenue ? 0 : (userData?['rating'] ?? 0);
    final username = isVenue ? (userData?['venueName'] ?? tr('drawer.fallback_venue')) : (userData?['username'] ?? tr('drawer.fallback_player'));
    final avatarUrl = isVenue ? null : userData?['avatarUrl'];

    final levelDetails = LevelUtils.getLevelDetails(rating);
    final String levelName = levelDetails['levelName'];
    final double progress = levelDetails['progress'];

    return Drawer(
      backgroundColor: AppColors.bg,
      child: Column(
        children: [
          // Drawer Header with User Profile details
          DrawerHeader(
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border(
                bottom: BorderSide(
                  color: AppColors.accent,
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
                        backgroundColor: AppColors.border,
                        color: AppColors.accent,
                        strokeWidth: 4,
                      ),
                    ),
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.border700,
                      backgroundImage: avatarUrl != null ? _getAvatarProvider(avatarUrl) : null,
                      child: avatarUrl == null
                          ? Icon(isVenue ? Icons.storefront : Icons.person, color: AppColors.text, size: 30)
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isVenue ? tr('drawer.partner_club') : levelName,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: isVenue ? 1.0 : progress,
                          backgroundColor: AppColors.border,
                          color: AppColors.accent,
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
                      title: tr('drawer.dashboard_venue'),
                      pageKey: 'dashboard',
                      onTap: () => _navigateTo('dashboard', const HomeScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.workspace_premium_outlined,
                      title: tr('drawer.subscription'),
                      pageKey: 'subscription',
                      onTap: () => _navigateTo('subscription', const VenueSubscriptionScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.forum_outlined,
                      title: tr('drawer.feed'),
                      pageKey: 'feed',
                      onTap: () => _navigateTo('feed', const FeedScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.calendar_month_outlined,
                      title: tr('drawer.tables_layout'),
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
                      title: tr('drawer.venue_profile'),
                      pageKey: 'venue_profile',
                      onTap: () => _navigateTo('venue_profile', const VenueProfileScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.emoji_events_outlined,
                      title: tr('drawer.tournaments_venue'),
                      pageKey: 'tournaments',
                      onTap: () => _navigateTo('tournaments', const TournamentsScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.monetization_on_outlined,
                      title: tr('drawer.finances'),
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
                      title: tr('drawer.dashboard'),
                      pageKey: 'dashboard',
                      onTap: () => _navigateTo('dashboard', const HomeScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.forum_outlined,
                      title: tr('drawer.feed'),
                      pageKey: 'feed',
                      onTap: () => _navigateTo('feed', const FeedScreen()),
                    ),
                    if (userData?['isTrainer'] == true)
                      _buildDrawerItem(
                        icon: Icons.sports,
                        title: tr('drawer.trainer_panel'),
                        pageKey: 'trainer_dashboard',
                        onTap: () => _navigateTo('trainer_dashboard', const TrainerDashboard()),
                      ),
                    _buildDrawerItem(
                      icon: Icons.leaderboard_outlined,
                      title: tr('drawer.leaderboard'),
                      pageKey: 'leaderboard',
                      onTap: () => _navigateTo('leaderboard', const LeaderboardScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.insights_outlined,
                      title: tr('drawer.stats'),
                      pageKey: 'stats',
                      onTap: () => _navigateTo('stats', const MyStatsScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.person_outline,
                      title: tr('drawer.profile'),
                      pageKey: 'profile',
                      onTap: () => _navigateTo('profile', const MyProfileScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.sports_tennis,
                      title: tr('drawer.find_match'),
                      pageKey: 'find_match',
                      onTap: () => _navigateTo('find_match', const FindMatchScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.add_circle_outline,
                      title: tr('drawer.create_match'),
                      pageKey: 'create_match',
                      onTap: () => _navigateTo('create_match', const CreateMatchScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.history,
                      title: tr('drawer.my_matches'),
                      pageKey: 'my_matches',
                      onTap: () => _navigateTo('my_matches', const MyMatchesScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.fitness_center_outlined,
                      title: tr('drawer.trainer_sessions'),
                      pageKey: 'client_sessions',
                      onTap: () => _navigateTo('client_sessions', const ClientSessionsScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.group_add_outlined,
                      title: tr('drawer.friends'),
                      pageKey: 'friends',
                      onTap: () => _navigateTo('friends', const FriendsScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.emoji_events_outlined,
                      title: tr('drawer.tournaments'),
                      pageKey: 'tournaments',
                      onTap: () => _navigateTo('tournaments', const TournamentsScreen()),
                    ),
                    _buildDrawerItem(
                      icon: Icons.map_outlined,
                      title: tr('drawer.venue_map'),
                      pageKey: 'venue_map',
                      onTap: () => _navigateTo('venue_map', const VenueMapScreen()),
                    ),
                  ],
            ),
          ),
          
          Divider(color: AppColors.muted, height: 1),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
            leading: Icon(Icons.language, color: AppColors.text70),
            title: Text(tr('drawer.language'), style: TextStyle(color: AppColors.text, fontSize: 16)),
            trailing: Text(
              AppLocales.byCode(AppLocales.current.value).tag,
              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            onTap: () {
              Navigator.pop(context); // închide meniul
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageScreen()));
            },
          ),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
            leading: Icon(Icons.shield_outlined, color: AppColors.text70),
            title: Text(tr('drawer.account'), style: TextStyle(color: AppColors.text, fontSize: 16)),
            onTap: () {
              Navigator.pop(context); // închide meniul
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyDataScreen()));
            },
          ),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
            leading: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (context, mode, _) => Icon(themeModeIcon(mode), color: AppColors.text70),
            ),
            title: Text(tr('drawer.theme'), style: TextStyle(color: AppColors.text, fontSize: 16)),
            trailing: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (context, mode, _) => Text(
                themeModeLabel(mode),
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            onTap: () => showThemeSheet(context),
          ),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(
              tr('drawer.logout'),
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 16),
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
        color: isSelected ? AppColors.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? AppColors.accent.withValues(alpha: 0.3) : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Icon(
          icon,
          color: isSelected ? AppColors.accent : AppColors.text70,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? AppColors.accent : AppColors.text,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 16,
          ),
        ),
        onTap: onTap,
        ),
      ),
    );
  }
}
