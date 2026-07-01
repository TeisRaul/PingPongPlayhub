import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class PublicProfileScreen extends StatefulWidget {
  final String uid;

  const PublicProfileScreen({
    super.key,
    required this.uid,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  final String? currentUserUid = FirebaseAuth.instance.currentUser?.uid;
  Map<String, dynamic>? userData;
  bool _isLoading = true;
  bool _isFriend = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
      if (doc.exists) {
        bool friendFound = false;
        if (currentUserUid != null) {
          final snap = await FirebaseFirestore.instance
              .collection('friendships')
              .where('uids', arrayContains: currentUserUid)
              .get();
          for (var fDoc in snap.docs) {
            final uids = List<String>.from(fDoc.data()['uids'] ?? []);
            if (uids.contains(widget.uid)) {
              friendFound = true;
              break;
            }
          }
        }

        if (mounted) {
          setState(() {
            userData = doc.data();
            _isFriend = friendFound;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (currentUserUid == null || userData == null) return;
    
    // Simplistic Follow System:
    // Update target's followers list
    final targetRef = FirebaseFirestore.instance.collection('users').doc(widget.uid);
    final targetDoc = await targetRef.get();
    
    // Update current user's following list
    final currentUserRef = FirebaseFirestore.instance.collection('users').doc(currentUserUid);
    final currentUserDoc = await currentUserRef.get();
    
    if (!targetDoc.exists || !currentUserDoc.exists) return;

    final targetData = targetDoc.data()!;
    final currentUserData = currentUserDoc.data()!;

    final List<dynamic> targetFollowers = targetData['followers'] ?? [];
    final List<dynamic> myFollowing = currentUserData['following'] ?? [];

    final isFollowing = targetFollowers.contains(currentUserUid);
    final isPrivate = targetData['isPrivate'] ?? false;
    final List<dynamic> followRequests = targetData['followRequests'] ?? [];
    final hasRequested = followRequests.contains(currentUserUid);

    if (isFollowing) {
      // Unfollow
      await targetRef.update({'followers': FieldValue.arrayRemove([currentUserUid])});
      await currentUserRef.update({'following': FieldValue.arrayRemove([widget.uid])});
      
      setState(() {
        if (userData!['followers'] != null) {
           (userData!['followers'] as List).remove(currentUserUid);
        }
      });
    } else {
      if (isPrivate) {
        if (hasRequested) {
          // Cancel request
          await targetRef.update({'followRequests': FieldValue.arrayRemove([currentUserUid])});
          setState(() {
             if (userData!['followRequests'] != null) {
               (userData!['followRequests'] as List).remove(currentUserUid);
             }
          });
        } else {
          // Send request
          await targetRef.update({'followRequests': FieldValue.arrayUnion([currentUserUid])});
          setState(() {
             userData!['followRequests'] ??= [];
             (userData!['followRequests'] as List).add(currentUserUid);
          });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cerere trimisă!'), backgroundColor: Colors.green));
        }
      } else {
        // Follow
        await targetRef.update({'followers': FieldValue.arrayUnion([currentUserUid])});
        await currentUserRef.update({'following': FieldValue.arrayUnion([widget.uid])});
        
        setState(() {
           userData!['followers'] ??= [];
           (userData!['followers'] as List).add(currentUserUid);
        });
      }
    }
  }

  ImageProvider? _getAvatarProvider(String? url) {
    if (url == null || url.isEmpty) return null;
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
        backgroundColor: Color(0xFF0D1424),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
      );
    }

    if (userData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1424),
        appBar: AppBar(backgroundColor: const Color(0xFF131A2A)),
        body: const Center(child: Text('Utilizatorul nu a fost găsit.', style: TextStyle(color: Colors.white))),
      );
    }

    final String username = userData!['username'] ?? 'Utilizator';
    final String avatarUrl = userData!['avatarUrl'] ?? '';
    final String bio = userData!['bio'] ?? 'Niciun bio adăugat.';
    final int rating = userData!['rating'] ?? 0;
    
    final List<dynamic> followers = userData!['followers'] ?? [];
    final List<dynamic> following = userData!['following'] ?? [];
    final bool isFollowing = followers.contains(currentUserUid);
    final bool isMe = currentUserUid == widget.uid;
    final bool isTrainer = userData!['isTrainer'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1424),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131A2A),
        title: Text(username, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFF1E293B),
                    backgroundImage: avatarUrl.isNotEmpty ? _getAvatarProvider(avatarUrl) : null,
                    child: avatarUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    username,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  if (isTrainer)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Antrenor Personal', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                    )
                  else
                    Text(
                      'Rating: $rating puncte',
                      style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 14),
                    ),
                  const SizedBox(height: 16),
                  
                  // Followers / Following Stats
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatColumn('Urmăritori', followers.length.toString()),
                      const SizedBox(width: 32),
                      _buildStatColumn('Urmărește', following.length.toString()),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Bio
                  Text(
                    bio,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  if (!isMe)
                    Builder(
                      builder: (context) {
                        bool isPrivate = userData?['isPrivate'] ?? false;
                        bool hasRequested = (userData?['followRequests'] as List?)?.contains(currentUserUid) ?? false;
                        
                        String buttonText = 'Urmărește';
                        bool btnInactive = isFollowing || hasRequested;

                        if (isFollowing) {
                          buttonText = 'Urmărești';
                        } else if (isPrivate && hasRequested) {
                          buttonText = 'Cerere Trimisă';
                        } else if (isPrivate) {
                          buttonText = 'Cere Urmărire';
                        }

                        return Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _toggleFollow,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: btnInactive ? const Color(0xFF1E293B) : const Color(0xFF00E5FF),
                                  foregroundColor: btnInactive ? Colors.white : Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: Text(buttonText, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat in constructie')));
                                },
                                icon: const Icon(Icons.message, size: 18),
                                label: const Text('Mesaj'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.grey),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                    ),
                ],
              ),
            ),
          ),

          // Packages Section (If Trainer)
          if (isTrainer)
             SliverToBoxAdapter(
               child: Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     const Text('Pachete Antrenament', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                     const SizedBox(height: 12),
                     Card(
                       color: const Color(0xFF131A2A),
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.orange.withValues(alpha: 0.3))),
                       child: ListTile(
                         leading: const Icon(Icons.star, color: Colors.orange),
                         title: const Text('10 Ședințe', style: TextStyle(color: Colors.white)),
                         subtitle: const Text('Pachet complet pentru începători', style: TextStyle(color: Colors.grey)),
                         trailing: Text('${(userData!['trainerPricePerSession'] ?? userData!['trainerPrice'] ?? 0) * 10} RON', style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                       ),
                     ),
                   ],
                 ),
               ),
             ),

          // User's Posts Feed
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text('Postări', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          
          Builder(
            builder: (context) {
              bool isPrivate = userData?['isPrivate'] ?? false;
              bool isFollowing = (userData?['followers'] as List?)?.contains(currentUserUid) ?? false;
              bool isMe = widget.uid == currentUserUid;

              if (isPrivate && !isFollowing && !isMe) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Column(
                        children: [
                          Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Acest cont este privat.',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Urmărește pentru a-i vedea postările.',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('posts')
                .where('authorUid', isEqualTo: widget.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))));
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text('Nicio postare.', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                );
              }

              final allDocs = snapshot.data!.docs.toList();
              allDocs.sort((a, b) {
                final t1 = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                final t2 = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                if (t1 == null && t2 == null) return 0;
                if (t1 == null) return 1;
                if (t2 == null) return -1;
                return t2.compareTo(t1); // descending
              });

              final posts = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final visibility = data['visibility'] ?? 'public';
                final allowedCloseFriends = List<String>.from(data['allowedCloseFriends'] ?? []);

                if (widget.uid == currentUserUid) return true;

                if (visibility == 'public') return true;
                if (visibility == 'friends') return _isFriend;
                if (visibility == 'close_friends') return allowedCloseFriends.contains(currentUserUid);

                return false;
              }).toList();

              if (posts.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text('Nicio postare vizibilă.', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final doc = posts[index];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    final content = data['content'] ?? '';
                    final imageBase64 = data['imageBase64'] as String?;
                    final timestamp = data['timestamp'] as Timestamp?;
                    
                    final visibility = data['visibility'] ?? 'public';
                    IconData visibilityIcon;
                    Color visibilityColor;
                    if (visibility == 'close_friends') {
                      visibilityIcon = Icons.star;
                      visibilityColor = Colors.amber;
                    } else if (visibility == 'friends') {
                      visibilityIcon = Icons.group;
                      visibilityColor = Colors.greenAccent;
                    } else {
                      visibilityIcon = Icons.public;
                      visibilityColor = Colors.grey;
                    }
                    
                    return Card(
                      color: const Color(0xFF131A2A),
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
                      ),
                      elevation: 4,
                      shadowColor: Colors.black45,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  userData?['username'] ?? 'Utilizator',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                Icon(visibilityIcon, size: 14, color: visibilityColor),
                              ],
                            ),
                            Text(
                              _timeAgo(timestamp),
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            if (content.isNotEmpty)
                              Text(content, style: const TextStyle(color: Colors.white, fontSize: 15)),
                            if (imageBase64 != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                constraints: BoxConstraints(
                                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                                ),
                                width: double.infinity,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    base64Decode(imageBase64.split(',').last),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ]
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: posts.length,
                ),
              ); // end SliverList
            },
          ); // end StreamBuilder
        },
      ), // end Builder
      
      const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  String _timeAgo(Timestamp? timestamp) {
    if (timestamp == null) return 'Acum câteva secunde';
    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return DateFormat('dd MMM yyyy').format(date);
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'zi' : 'zile'}';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'oră' : 'ore'}';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'min' : 'min'}';
    } else {
      return 'Acum';
    }
  }
}
