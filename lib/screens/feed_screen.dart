import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'create_post_screen.dart';
import 'public_profile_screen.dart';
import 'post_comments_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final String? currentUserUid = FirebaseAuth.instance.currentUser?.uid;
  List<String> _myFriends = [];
  bool _isLoadingFriends = true;

  String _selectedCity = 'Toată România';
  final List<String> _cities = [
    'Toată România',
    'București',
    'Cluj-Napoca',
    'Timișoara',
    'Iași',
    'Constanța',
    'Brașov',
    'Sibiu',
    'Oradea',
    'Craiova',
    'Galați',
  ];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    if (currentUserUid == null) {
      if (mounted) setState(() => _isLoadingFriends = false);
      return;
    }
    
    try {
      final snap = await FirebaseFirestore.instance
          .collection('friendships')
          .where('uids', arrayContains: currentUserUid)
          .get();
      
      final friends = <String>[];
      for (var doc in snap.docs) {
        final uids = List<String>.from(doc.data()['uids'] ?? []);
        for (var uid in uids) {
          if (uid != currentUserUid) friends.add(uid);
        }
      }
      
      if (mounted) {
        setState(() {
          _myFriends = friends;
          _isLoadingFriends = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingFriends = false);
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

  Future<void> _toggleLike(String postId, List<dynamic> likedBy) async {
    if (currentUserUid == null) return;
    
    final isLiked = likedBy.contains(currentUserUid);
    final docRef = FirebaseFirestore.instance.collection('posts').doc(postId);

    if (isLiked) {
      await docRef.update({
        'likedBy': FieldValue.arrayRemove([currentUserUid]),
        'likesCount': FieldValue.increment(-1),
      });
    } else {
      await docRef.update({
        'likedBy': FieldValue.arrayUnion([currentUserUid]),
        'likesCount': FieldValue.increment(1),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1424),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131A2A),
        title: const Text('Comunitate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _isLoadingFriends) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'Nicio postare în comunitate încă.\nFii primul care postează ceva!',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            );
          }

          final posts = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final authorUid = data['authorUid'] ?? '';
            final visibility = data['visibility'] ?? 'public';
            final allowedCloseFriends = List<String>.from(data['allowedCloseFriends'] ?? []);
            final postCity = data['city'] ?? 'Necunoscut';

            if (_selectedCity != 'Toată România' && postCity != _selectedCity) return false;

            if (authorUid == currentUserUid) return true;

            if (visibility == 'public') return true;
            if (visibility == 'friends') return _myFriends.contains(authorUid);
            if (visibility == 'close_friends') return allowedCloseFriends.contains(currentUserUid);

            return false;
          }).toList();

          if (posts.isEmpty) {
            return const Center(
              child: Text(
                'Nicio postare vizibilă încă.\nFii primul care postează ceva!',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            );
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF131A2A),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: const Color(0xFF1E293B),
                    value: _selectedCity,
                    icon: const Icon(Icons.location_on, color: Color(0xFF00E5FF), size: 20),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    items: _cities.map((String city) {
                      return DropdownMenuItem<String>(
                        value: city,
                        child: Text(city),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedCity = newValue;
                        });
                      }
                    },
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
              final doc = posts[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final authorUid = data['authorUid'] ?? '';
              final authorUsername = data['authorUsername'] ?? 'Utilizator';
              final authorAvatarUrl = data['authorAvatarUrl'] as String?;
              final content = data['content'] ?? '';
              final imageBase64 = data['imageBase64'] as String?;
              final timestamp = data['timestamp'] as Timestamp?;
              final likedBy = data['likedBy'] as List<dynamic>? ?? [];
              final likesCount = data['likesCount'] ?? 0;
              final commentsCount = data['commentsCount'] ?? 0;
              
              final isLiked = likedBy.contains(currentUserUid);

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
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    // Header: Avatar, Name, Time
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (authorUid.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PublicProfileScreen(uid: authorUid),
                                ),
                              );
                            }
                          },
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF1E293B),
                            backgroundImage: authorAvatarUrl != null && authorAvatarUrl.isNotEmpty
                                ? _getAvatarProvider(authorAvatarUrl)
                                : null,
                            child: authorAvatarUrl == null || authorAvatarUrl.isEmpty
                                ? const Icon(Icons.person, color: Colors.white)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (authorUid.isNotEmpty) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PublicProfileScreen(uid: authorUid),
                                  ),
                                );
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      authorUsername,
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
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Content
                    if (content.isNotEmpty)
                      Text(
                        content,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    
                    if (content.isNotEmpty && imageBase64 != null)
                      const SizedBox(height: 12),
                      
                    if (imageBase64 != null && imageBase64.isNotEmpty)
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
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                          ),
                        ),
                      ),
                      
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFF1E293B)),
                    
                    // Actions: Like, Comment
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _toggleLike(doc.id, likedBy),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isLiked ? Icons.favorite : Icons.favorite_border,
                                    color: isLiked ? Colors.redAccent : Colors.grey,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    likesCount > 0 ? '$likesCount' : 'Îmi place',
                                    style: TextStyle(color: isLiked ? Colors.redAccent : Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PostCommentsScreen(postId: doc.id),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    commentsCount > 0 ? '$commentsCount' : 'Comentează',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
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
  },
),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF00E5FF),
        child: const Icon(Icons.edit, color: Colors.black),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          );
        },
      ),
    );
  }
}
