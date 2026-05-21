import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatScreen extends StatefulWidget {
  final String? chatId;
  final String otherUid;
  final String otherUsername;
  final String? otherAvatarUrl;

  const ChatScreen({
    super.key,
    this.chatId,
    required this.otherUid,
    required this.otherUsername,
    this.otherAvatarUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _currentUser = FirebaseAuth.instance.currentUser;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late final String _resolvedChatId;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _resolvedChatId = widget.chatId ?? _generateChatId(_currentUser!.uid, widget.otherUid);
  }

  String _generateChatId(String uid1, String uid2) {
    return uid1.compareTo(uid2) < 0 ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUser == null || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final now = FieldValue.serverTimestamp();

      // Create message doc
      final messageData = {
        'senderUid': _currentUser.uid,
        'text': text,
        'timestamp': now,
      };

      // Get my user data for updating the chat doc
      final myUserDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUser.uid).get();
      final myData = myUserDoc.data() ?? {};
      final myUsername = myData['username'] ?? 'Utilizator';
      final myAvatarUrl = myData['avatarUrl'] ?? '';

      // Order parameters to save chat document correctly
      final isFirst = _currentUser.uid.compareTo(widget.otherUid) < 0;
      final uids = isFirst ? [_currentUser.uid, widget.otherUid] : [widget.otherUid, _currentUser.uid];
      final usernames = isFirst ? [myUsername, widget.otherUsername] : [widget.otherUsername, myUsername];
      final avatars = isFirst ? [myAvatarUrl, widget.otherAvatarUrl ?? ''] : [widget.otherAvatarUrl ?? '', myAvatarUrl];

      final chatDocRef = FirebaseFirestore.instance.collection('chats').doc(_resolvedChatId);

      // Batch or transaction to set/update chat and add message
      final batch = FirebaseFirestore.instance.batch();
      
      batch.set(chatDocRef, {
        'uids': uids,
        'usernames': usernames,
        'avatars': avatars,
        'lastMessage': text,
        'lastMessageTime': now,
      }, SetOptions(merge: true));

      final newMessageRef = chatDocRef.collection('messages').doc();
      batch.set(newMessageRef, messageData);

      await batch.commit();

      // Scroll to bottom
      _scrollToBottom();
    } catch (e) {
      debugPrint('Eroare la trimiterea mesajului: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF1E293B),
              backgroundImage: widget.otherAvatarUrl != null && widget.otherAvatarUrl!.isNotEmpty
                  ? NetworkImage(widget.otherAvatarUrl!)
                  : null,
              child: widget.otherAvatarUrl == null || widget.otherAvatarUrl!.isEmpty
                  ? Text(widget.otherUsername.substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.otherUsername,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF131A2A),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_resolvedChatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text('Eroare: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
                }

                final messages = snapshot.data?.docs ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Spune-i salut lui ${widget.otherUsername}!',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                // Schedule scroll to bottom once view is rendered
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data() as Map<String, dynamic>;
                    final isMe = data['senderUid'] == _currentUser?.uid;
                    final text = data['text'] ?? '';

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF00E5FF) : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                          ),
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: isMe ? Colors.black : Colors.white,
                            fontSize: 15,
                            fontWeight: isMe ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF131A2A),
              border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: 'Scrie un mesaj...',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        filled: true,
                        fillColor: Color(0xFF0A0E17),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF00E5FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.black, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
