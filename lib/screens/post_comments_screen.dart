import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../theme/app_theme.dart';

class PostCommentsScreen extends StatefulWidget {
  final String postId;

  const PostCommentsScreen({super.key, required this.postId});

  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen> {
  final TextEditingController _commentController = TextEditingController();
  final String? currentUserUid = FirebaseAuth.instance.currentUser?.uid;
  bool _isPosting = false;

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || currentUserUid == null) return;

    setState(() => _isPosting = true);
    
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUserUid).get();
      final userData = userDoc.data() ?? {};
      
      await FirebaseFirestore.instance.collection('posts').doc(widget.postId).collection('comments').add({
        'authorUid': currentUserUid,
        'authorUsername': userData['username'] ?? 'Utilizator',
        'authorAvatarUrl': userData['avatarUrl'] ?? '',
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update comments count on main post
      await FirebaseFirestore.instance.collection('posts').doc(widget.postId).update({
        'commentsCount': FieldValue.increment(1),
      });

      _commentController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
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

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return 'Acum';
    return DateFormat('HH:mm - dd MMM').format(timestamp.toDate());
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        title: Text('Comentarii', style: TextStyle(color: AppColors.text)),
        iconTheme: IconThemeData(color: AppColors.text),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .doc(widget.postId)
                  .collection('comments')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: AppColors.accent));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text('Niciun comentariu. Fii primul!', style: TextStyle(color: AppColors.muted)),
                  );
                }

                final comments = snapshot.data!.docs;

                return ListView.separated(
                  reverse: true, // Show newest at the bottom naturally if we reverse, but here we order descending so newest is at the top. Wait, if we use reverse: true, we should keep descending: true so newest is at the bottom.
                  padding: const EdgeInsets.all(16),
                  itemCount: comments.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = comments[index];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.card2,
                          backgroundImage: data['authorAvatarUrl'] != null && (data['authorAvatarUrl'] as String).isNotEmpty
                              ? _getAvatarProvider(data['authorAvatarUrl'])
                              : null,
                          child: (data['authorAvatarUrl'] == null || (data['authorAvatarUrl'] as String).isEmpty)
                              ? Icon(Icons.person, size: 16, color: AppColors.text)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      data['authorUsername'] ?? 'Utilizator',
                                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      _formatTime(data['timestamp']),
                                      style: TextStyle(color: AppColors.muted, fontSize: 10),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  data['text'] ?? '',
                                  style: TextStyle(color: AppColors.text70, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          
          // Comment Input
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.card,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    style: TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                      hintText: 'Adaugă un comentariu...',
                      hintStyle: TextStyle(color: AppColors.muted),
                      filled: true,
                      fillColor: AppColors.card2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _isPosting
                  ? Padding(padding: EdgeInsets.all(12.0), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.accent)))
                  : IconButton(
                      icon: Icon(Icons.send, color: AppColors.accent),
                      onPressed: _postComment,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
