import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'create_match_for_friends_screen.dart';
import '../utils/level_utils.dart';
import '../widgets/player_drawer.dart';
import '../l10n/strings.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  User? get _currentUser => FirebaseAuth.instance.currentUser;
  final _searchController = TextEditingController();
  
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  String? _searchError;
  // uid -> 'friend' | 'sent' | 'received' (relația cu rezultatele căutării)
  Map<String, String> _relations = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- Search & Add Friends ---
  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    final user = _currentUser;
    if (query.isEmpty || user == null) return;

    setState(() {
      _isSearching = true;
      _searchResults.clear();
      _searchError = null;
    });

    try {
      // We will perform three independent queries in parallel to support search by username, email, or phone number
      final usersCollection = FirebaseFirestore.instance.collection('users');

      final queries = await Future.wait([
        usersCollection.where('username', isEqualTo: query).get(),
        usersCollection.where('email', isEqualTo: query).get(),
        usersCollection.where('phone', isEqualTo: query).get(),
      ]);

      final Set<String> uniqueUids = {};
      final List<Map<String, dynamic>> results = [];

      for (var qSnap in queries) {
        for (var doc in qSnap.docs) {
          final data = doc.data();
          final uid = data['uid'] ?? '';
          if (uid.isNotEmpty && uid != user.uid && !uniqueUids.contains(uid)) {
            uniqueUids.add(uid);
            results.add(data);
          }
        }
      }

      final db = FirebaseFirestore.instance;
      final Map<String, String> relations = {};
      for (final r in results) {
        final String tu = r['uid'];
        final String fid = user.uid.compareTo(tu) < 0 ? '${user.uid}_$tu' : '${tu}_${user.uid}';
        if ((await db.collection('friendships').doc(fid).get()).exists) {
          relations[tu] = 'friend';
          continue;
        }
        final sent = await db.collection('friend_requests')
            .where('fromUid', isEqualTo: user.uid).where('toUid', isEqualTo: tu).where('status', isEqualTo: 'pending').get();
        if (sent.docs.isNotEmpty) {
          relations[tu] = 'sent';
          continue;
        }
        final recv = await db.collection('friend_requests')
            .where('fromUid', isEqualTo: tu).where('toUid', isEqualTo: user.uid).where('status', isEqualTo: 'pending').get();
        if (recv.docs.isNotEmpty) relations[tu] = 'received';
      }

      setState(() {
        _searchResults = results;
        _relations = relations;
        if (results.isEmpty) {
          _searchError = tr('friends.not_found');
        }
      });
    } catch (e) {
      setState(() => _searchError = tr('friends.search_error', {'error': '$e'}));
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _sendFriendRequest(Map<String, dynamic> targetUser) async {
    final user = _currentUser;
    if (user == null) return;

    final targetUid = targetUser['uid'];
    final targetUsername = targetUser['username'] ?? tr('friends.user');
    final targetAvatarUrl = targetUser['avatarUrl'] ?? '';

    try {
      // 1. Verificare anti-spam: sunt deja prieteni?
      final String friendshipId = user.uid.compareTo(targetUid) < 0
          ? '${user.uid}_$targetUid'
          : '${targetUid}_${user.uid}';

      final friendshipDoc = await FirebaseFirestore.instance.collection('friendships').doc(friendshipId).get();
      if (friendshipDoc.exists) {
        _showDialogMessage(tr('friends.already_title'), tr('friends.already_body'));
        return;
      }

      // 2. Verificare anti-spam: există deja o cerere pending de la mine la ei?
      final sentRequestQuery = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: user.uid)
          .where('toUid', isEqualTo: targetUid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (sentRequestQuery.docs.isNotEmpty) {
        _showDialogMessage(tr('friends.sent_title'), tr('friends.sent_body'));
        return;
      }

      // 3. Verificare anti-spam: există deja o cerere pending de la ei la mine?
      final receivedRequestQuery = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: targetUid)
          .where('toUid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (receivedRequestQuery.docs.isNotEmpty) {
        _showDialogMessage(tr('friends.pending_title'), tr('friends.pending_body'));
        return;
      }

      // Get my details for the request
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final myData = myDoc.data() ?? {};
      final myUsername = myData['username'] ?? 'Utilizator';
      final myAvatarUrl = myData['avatarUrl'] ?? '';

      // Save friend request doc
      await FirebaseFirestore.instance.collection('friend_requests').add({
        'fromUid': user.uid,
        'fromUsername': myUsername,
        'fromAvatarUrl': myAvatarUrl,
        'toUid': targetUid,
        'toUsername': targetUsername,
        'toAvatarUrl': targetAvatarUrl,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      await NotificationService.send(
        toUid: targetUid,
        type: 'friend_request',
        titleKey: 'n.friend_req_title',
        bodyKey: 'n.friend_req_body',
        args: {'player': '$myUsername'},
      );

      if (mounted) {
        setState(() => _relations[targetUid] = 'sent');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('friends.sent_snack', {'name': '$targetUsername'})), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('friends.send_error', {'error': '$e'})), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showDialogMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(title, style: TextStyle(color: AppColors.text)),
        content: Text(message, style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  // --- Friend Requests Popup Dialog (Received requests) ---
  void _showReceivedRequestsDialog() {
    final user = _currentUser;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('friends.requests'), style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(
                icon: Icon(Icons.close, color: AppColors.muted),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('friend_requests')
                  .where('toUid', isEqualTo: user?.uid)
                  .where('status', isEqualTo: 'pending')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(tr('friends.error', {'error': '${snapshot.error}'}), style: const TextStyle(color: Colors.redAccent)));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: AppColors.accent));
                }

                final requests = snapshot.data?.docs ?? [];

                if (requests.isEmpty) {
                  return Center(
                    child: Text(tr('friends.no_requests'), style: TextStyle(color: AppColors.muted), textAlign: TextAlign.center),
                  );
                }

                return ListView.separated(
                  itemCount: requests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final reqDoc = requests[idx];
                    final reqData = reqDoc.data() as Map<String, dynamic>;
                    final fromUsername = reqData['fromUsername'] ?? 'Utilizator';
                    final fromAvatar = reqData['fromAvatarUrl'] ?? '';

                    return Card(
                      color: AppColors.card2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.card,
                              backgroundImage: fromAvatar.isNotEmpty ? NetworkImage(fromAvatar) : null,
                              child: fromAvatar.isEmpty
                                  ? Text(fromUsername.substring(0, 1).toUpperCase(), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold))
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(fromUsername, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text), overflow: TextOverflow.ellipsis),
                            ),
                            IconButton(
                              icon: const Icon(Icons.check_circle, color: Colors.green),
                              onPressed: () async {
                                Navigator.pop(dialogContext); // Close dialog
                                await _acceptFriendRequest(reqDoc.id, reqData);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.redAccent),
                              onPressed: () async {
                                Navigator.pop(dialogContext); // Close dialog
                                await _declineFriendRequest(reqDoc.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _acceptFriendRequest(String requestId, Map<String, dynamic> reqData) async {
    final user = _currentUser;
    if (user == null) return;
    
    final fromUid = reqData['fromUid'];
    final fromUsername = reqData['fromUsername'] ?? 'Utilizator';
    final fromAvatar = reqData['fromAvatarUrl'] ?? '';

    try {
      // Get my details
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final myData = myDoc.data() ?? {};
      final myUsername = myData['username'] ?? 'Utilizator';
      final myAvatar = myData['avatarUrl'] ?? '';

      // Generate friendship ID
      final String friendshipId = user.uid.compareTo(fromUid) < 0
          ? '${user.uid}_$fromUid'
          : '${fromUid}_${user.uid}';

      final isFirst = user.uid.compareTo(fromUid) < 0;
      final uids = isFirst ? [user.uid, fromUid] : [fromUid, user.uid];
      final usernames = isFirst ? [myUsername, fromUsername] : [fromUsername, myUsername];
      final avatars = isFirst ? [myAvatar, fromAvatar] : [fromAvatar, myAvatar];

      final batch = FirebaseFirestore.instance.batch();

      // Delete request
      batch.delete(FirebaseFirestore.instance.collection('friend_requests').doc(requestId));

      // Create mutual friendship
      batch.set(FirebaseFirestore.instance.collection('friendships').doc(friendshipId), {
        'uids': uids,
        'usernames': usernames,
        'avatars': avatars,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('friends.now_friends', {'name': '$fromUsername'})), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('friends.accept_error', {'error': '$e'})), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _declineFriendRequest(String requestId) async {
    try {
      await FirebaseFirestore.instance.collection('friend_requests').doc(requestId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('friends.declined')), backgroundColor: Colors.orangeAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('friends.error', {'error': '$e'})), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('friends.title'))),
        body: Center(child: Text(tr('friends.not_logged'))),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const PlayerDrawer(activePage: 'friends'),
        appBar: AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              icon: Icon(Icons.menu, color: AppColors.accent),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ),
          title: Text(tr('friends.title')),
          backgroundColor: AppColors.card,
          elevation: 0,
          bottom: TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.muted,
            tabs: [
              Tab(text: tr('friends.tab_mine')),
              Tab(text: tr('friends.tab_search')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: Friends List
            _buildFriendsTab(),

            // TAB 2: Search Tab
            _buildSearchTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsTab() {
    final user = _currentUser;
    return Column(
      children: [
        // Cereri Primite Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: AppColors.card,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('friends.manage'), style: TextStyle(color: AppColors.muted, fontSize: 14)),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('friend_requests')
                    .where('toUid', isEqualTo: user?.uid)
                    .where('status', isEqualTo: 'pending')
                    .snapshots(),
                builder: (context, snapshot) {
                  int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                  return ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: count > 0 ? Colors.redAccent : AppColors.card2,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: Icon(count > 0 ? Icons.notification_important : Icons.people_outline, size: 18),
                    label: Text(count > 0 ? tr('friends.requests_n', {'count': '$count'}) : tr('friends.requests')),
                    onPressed: _showReceivedRequestsDialog,
                  );
                },
              ),
            ],
          ),
        ),

        // Friends Stream
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
            builder: (context, userSnapshot) {
              List<dynamic> closeFriends = [];
              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                closeFriends = userData['closeFriends'] ?? [];
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('friendships')
                    .where('uids', arrayContains: user?.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text(tr('friends.load_error', {'error': '${snapshot.error}'}), style: const TextStyle(color: Colors.redAccent)));
                  }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator(color: AppColors.accent));
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 64, color: AppColors.muted),
                        SizedBox(height: 16),
                        Text(tr('friends.none'), style: TextStyle(color: AppColors.muted, fontSize: 16, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text(tr('friends.none_hint'), style: TextStyle(color: AppColors.muted, fontSize: 12), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final friendshipData = docs[index].data() as Map<String, dynamic>;
                  final friendshipId = docs[index].id;
                  
                  final List<dynamic> uids = friendshipData['uids'] ?? [];
                  final List<dynamic> usernames = friendshipData['usernames'] ?? [];
                  final List<dynamic> avatars = friendshipData['avatars'] ?? [];

                  int otherIdx = uids.indexOf(user?.uid) == 0 ? 1 : 0;
                  if (uids.length < 2) return const SizedBox();

                  final String otherUid = uids[otherIdx];
                  final String otherUsername = (usernames.length > otherIdx) ? usernames[otherIdx] : tr('friends.user');
                  final String? otherAvatar = (avatars.length > otherIdx) ? avatars[otherIdx] : null;

                  final bool isCloseFriend = closeFriends.contains(otherUid);

                  return Card(
                    color: AppColors.card,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.card2,
                        backgroundImage: otherAvatar != null && otherAvatar.isNotEmpty ? NetworkImage(otherAvatar) : null,
                        child: otherAvatar == null || otherAvatar.isEmpty
                            ? Text(otherUsername.substring(0, 1).toUpperCase(), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold))
                            : null,
                      ),
                      title: Text(otherUsername, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      subtitle: Text(isCloseFriend ? tr('friends.close') : tr('friends.mutual'), style: TextStyle(color: isCloseFriend ? Colors.amber : AppColors.muted, fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(isCloseFriend ? Icons.star : Icons.star_border, color: isCloseFriend ? Colors.amber : AppColors.muted),
                            onPressed: () => _toggleCloseFriend(otherUid, isCloseFriend),
                          ),
                          IconButton(
                            icon: Icon(Icons.chat_bubble_outline, color: AppColors.accent),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    chatId: friendshipId,
                                    otherUid: otherUid,
                                    otherUsername: otherUsername,
                                    otherAvatarUrl: otherAvatar,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    ),

        // Action Button: Create Match
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border(top: BorderSide(color: AppColors.card2, width: 1)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateMatchForFriendsScreen()),
                );
              },
              child: Text(tr('friends.create_match')),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleCloseFriend(String friendUid, bool isCurrentlyClose) async {
    final user = _currentUser;
    if (user == null) return;
    
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      if (isCurrentlyClose) {
        await docRef.update({
          'closeFriends': FieldValue.arrayRemove([friendUid])
        });
      } else {
        await docRef.update({
          'closeFriends': FieldValue.arrayUnion([friendUid])
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('friends.error', {'error': '$e'}))));
      }
    }
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        // Search Input Bar
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.card,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: tr('friends.search_hint'),
                    prefixIcon: Icon(Icons.search, color: AppColors.muted),
                  ),
                  onSubmitted: (_) => _searchUsers(),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _searchUsers,
                child: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ),

        // Results or Loading
        Expanded(
          child: _isSearching
              ? Center(child: CircularProgressIndicator(color: AppColors.accent))
              : _searchError != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_searchError!, style: TextStyle(color: AppColors.muted), textAlign: TextAlign.center)))
                  : _searchResults.isEmpty
                      ? Center(child: Text(tr('friends.search_prompt'), style: TextStyle(color: AppColors.muted)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final user = _searchResults[index];
                            final username = user['username'] ?? tr('friends.user');
                            final String relation = _relations[user['uid']] ?? '';
                            final avatarUrl = user['avatarUrl'] ?? '';
                            final rating = user['rating'] ?? 0;
                            final levelName = LevelUtils.getLevelDetails(rating)['levelName'];

                            return Card(
                              color: AppColors.card,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: AppColors.accent.withValues(alpha: 0.2)),
                              ),
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: AppColors.card2,
                                      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                                      child: avatarUrl.isEmpty
                                          ? Text(username.substring(0, 1).toUpperCase(), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 18))
                                          : null,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(username, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.text)),
                                          Text(tr('friends.level', {'level': '$levelName', 'points': '$rating'}), style: TextStyle(color: AppColors.accent, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      ),
                                      onPressed: relation.isEmpty ? () => _sendFriendRequest(user) : null,
                                      child: Text(relation == 'friend'
                                          ? tr('friends.btn_friend')
                                          : relation == 'sent'
                                              ? tr('friends.btn_sent')
                                              : relation == 'received'
                                                  ? tr('friends.btn_received')
                                                  : tr('friends.btn_add')),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
