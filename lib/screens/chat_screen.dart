import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatScreen extends StatefulWidget {
  final String? chatId;
  final String? otherUid;
  final String? otherUsername;
  final String? otherAvatarUrl;
  final bool isTournamentChat;
  final String? tournamentTitle;
  final String? adminUid;

  const ChatScreen({
    super.key,
    this.chatId,
    this.otherUid,
    this.otherUsername,
    this.otherAvatarUrl,
    this.isTournamentChat = false,
    this.tournamentTitle,
    this.adminUid,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  User? get _currentUser => FirebaseAuth.instance.currentUser;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late final String _resolvedChatId;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    final user = _currentUser;
    if (widget.isTournamentChat) {
      _resolvedChatId = widget.chatId ?? 'tournament_unknown';
    } else {
      _resolvedChatId = widget.chatId ?? _generateChatId(user!.uid, widget.otherUid!);
    }
  }

  String _generateChatId(String uid1, String uid2) {
    return uid1.compareTo(uid2) < 0 ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final user = _currentUser;
    if (text.isEmpty || user == null || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final now = FieldValue.serverTimestamp();

      // Get sender info from either users or venues collection
      String myUsername = 'Utilizator';
      String myAvatarUrl = '';

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        myUsername = data['username'] ?? 'Utilizator';
        myAvatarUrl = data['avatarUrl'] ?? '';
      } else {
        final venueDoc = await FirebaseFirestore.instance.collection('venues').doc(user.uid).get();
        if (venueDoc.exists) {
          final data = venueDoc.data() ?? {};
          myUsername = data['name'] ?? 'Club';
          myAvatarUrl = data['imageUrl'] ?? '';
        }
      }

      final messageData = {
        'senderUid': user.uid,
        'senderName': myUsername,
        'text': text,
        'timestamp': now,
      };

      final chatDocRef = FirebaseFirestore.instance.collection('chats').doc(_resolvedChatId);
      final batch = FirebaseFirestore.instance.batch();

      if (widget.isTournamentChat) {
        batch.set(chatDocRef, {
          'lastMessage': text,
          'lastMessageTime': now,
        }, SetOptions(merge: true));
      } else {
        final otherUid = widget.otherUid!;
        final otherUsername = widget.otherUsername ?? 'Utilizator';
        final otherAvatarUrl = widget.otherAvatarUrl ?? '';

        final isFirst = user.uid.compareTo(otherUid) < 0;
        final uids = isFirst ? [user.uid, otherUid] : [otherUid, user.uid];
        final usernames = isFirst ? [myUsername, otherUsername] : [otherUsername, myUsername];
        final avatars = isFirst ? [myAvatarUrl, otherAvatarUrl] : [otherAvatarUrl, myAvatarUrl];

        batch.set(chatDocRef, {
          'uids': uids,
          'usernames': usernames,
          'avatars': avatars,
          'lastMessage': text,
          'lastMessageTime': now,
        }, SetOptions(merge: true));
      }

      final newMessageRef = chatDocRef.collection('messages').doc();
      batch.set(newMessageRef, messageData);

      await batch.commit();
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
    final user = _currentUser;
    final chatDocStream = FirebaseFirestore.instance.collection('chats').doc(_resolvedChatId).snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: chatDocStream,
      builder: (context, chatSnapshot) {
        final chatData = chatSnapshot.data?.data() as Map<String, dynamic>? ?? {};
        final onlyAdminCanSend = chatData['onlyAdminCanSend'] == true;
        final adminUid = chatData['adminUid'] ?? widget.adminUid;
        final isAdmin = user != null && user.uid == adminUid;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0E17),
          appBar: AppBar(
            backgroundColor: const Color(0xFF131A2A),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            titleSpacing: 0,
            title: Row(
              children: [
                widget.isTournamentChat
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.15),
                          border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.emoji_events_outlined,
                          color: Color(0xFF00E5FF),
                          size: 20,
                        ),
                      )
                    : CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFF1E293B),
                        backgroundImage: widget.otherAvatarUrl != null && widget.otherAvatarUrl!.isNotEmpty
                            ? NetworkImage(widget.otherAvatarUrl!)
                            : null,
                        child: widget.otherAvatarUrl == null || widget.otherAvatarUrl!.isEmpty
                            ? Text(
                                (widget.otherUsername ?? 'U').substring(0, 1).toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.isTournamentChat
                            ? (widget.tournamentTitle ?? 'Chat Turneu')
                            : (widget.otherUsername ?? 'Utilizator'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.isTournamentChat)
                        const Text(
                          'Grup Oficial Turneu',
                          style: TextStyle(fontSize: 11, color: Color(0xFF00E5FF), fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.isTournamentChat && isAdmin) ...[
                Row(
                  children: [
                    const Text(
                      'Doar Admin',
                      style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: onlyAdminCanSend,
                        activeColor: const Color(0xFF00E5FF),
                        activeTrackColor: const Color(0xFF00E5FF).withOpacity(0.3),
                        inactiveThumbColor: Colors.grey[400],
                        inactiveTrackColor: Colors.grey[800],
                        onChanged: (val) async {
                          try {
                            await FirebaseFirestore.instance
                                .collection('chats')
                                .doc(_resolvedChatId)
                                .update({'onlyAdminCanSend': val});
                          } catch (e) {
                            debugPrint('Eroare la schimbarea setarii: $e');
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
            ],
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
                          widget.isTournamentChat
                              ? 'Bun venit în chat-ul oficial al turneului!'
                              : 'Spune-i salut lui ${widget.otherUsername ?? 'Utilizator'}!',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final data = messages[index].data() as Map<String, dynamic>;
                        final senderUid = data['senderUid'] ?? '';
                        final isMe = senderUid == user?.uid;
                        final text = data['text'] ?? '';
                        final senderName = data['senderName'] ?? 'Utilizator';
                        final isSystem = senderUid == 'system';
                        final isMsgAdmin = senderUid == adminUid;

                        if (isSystem) {
                          return Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B).withOpacity(0.4),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF1E293B), width: 0.8),
                              ),
                              child: Text(
                                text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          );
                        }

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (!isMe && widget.isTournamentChat) ...[
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                                  child: Text(
                                    isMsgAdmin ? '[Organizator] $senderName' : senderName,
                                    style: TextStyle(
                                      color: isMsgAdmin ? const Color(0xFF00E5FF) : Colors.grey[400],
                                      fontSize: 12,
                                      fontWeight: isMsgAdmin ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? const Color(0xFF00E5FF)
                                      : (isMsgAdmin && widget.isTournamentChat)
                                          ? const Color(0xFF1E293B).withOpacity(0.8)
                                          : const Color(0xFF1E293B),
                                  border: (!isMe && widget.isTournamentChat && isMsgAdmin)
                                      ? Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1)
                                      : null,
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
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              onlyAdminCanSend && !isAdmin
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      decoration: const BoxDecoration(
                        color: Color(0xFF131A2A),
                        border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF0055).withOpacity(0.08),
                                border: Border.all(color: const Color(0xFFFF0055).withOpacity(0.3), width: 1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.lock_outline,
                                    color: Color(0xFFFF0055),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Doar administratorul turneului poate trimite mesaje în acest chat.',
                                      style: TextStyle(
                                        color: const Color(0xFFFF0055).withOpacity(0.9),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Container(
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
                                  hintStyle: TextStyle(color: Colors.grey),
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
      },
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
