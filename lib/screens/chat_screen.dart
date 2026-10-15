import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/strings.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  final String? chatId;
  final String? otherUid;
  final String? otherUsername;
  final String? otherAvatarUrl;
  final bool isTournamentChat;
  /// Chat-ul lobby-ului unui meci (chatId = `match_` + id-ul meciului).
  final bool isMatchChat;
  final String? matchTitle;
  final String? tournamentTitle;
  final String? adminUid;

  const ChatScreen({
    super.key,
    this.chatId,
    this.otherUid,
    this.otherUsername,
    this.otherAvatarUrl,
    this.isTournamentChat = false,
    this.isMatchChat = false,
    this.matchTitle,
    this.tournamentTitle,
    this.adminUid,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  User? get _currentUser => FirebaseAuth.instance.currentUser;
  bool get _isGroup => widget.isTournamentChat || widget.isMatchChat;
  String get _title => widget.isMatchChat
      ? (widget.matchTitle ?? tr('chat.lobby_title'))
      : widget.isTournamentChat
          ? (widget.tournamentTitle ?? 'Chat Turneu')
          : (widget.otherUsername ?? 'Utilizator');
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late final String _resolvedChatId;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    final user = _currentUser;
    if (_isGroup) {
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

      if (_isGroup) {
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
      if (widget.isMatchChat) _notifyLobby(myUsername, text);
      _scrollToBottom();
    } catch (e) {
      debugPrint('Eroare la trimiterea mesajului: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Anunță ceilalți jucători din lobby (fără popup, fără email: doar clopoțel și push).
  Future<void> _notifyLobby(String myName, String text) async {
    try {
      final matchId = _resolvedChatId.replaceFirst('match_', '');
      final snap = await FirebaseFirestore.instance.collection('matches').doc(matchId).get();
      final m = snap.data();
      if (m == null) return;
      final preview = text.length > 120 ? '${text.substring(0, 120)}…' : text;
      for (final uid in List<dynamic>.from(m['joinedUids'] ?? [])) {
        await NotificationService.send(
          toUid: uid.toString(),
          type: 'lobby_chat',
          titleKey: 'n.lobby_chat_title',
          bodyKey: 'n.lobby_chat_body',
          args: {'name': myName, 'text': preview, 'venue': (m['locationName'] ?? '').toString()},
          matchId: matchId,
          extra: {'silent': true, 'skipEmail': true},
        );
      }
    } catch (_) {
      // notificarea ratată nu strică mesajul
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
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.card,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: AppColors.text),
              onPressed: () => Navigator.pop(context),
            ),
            titleSpacing: 0,
            title: Row(
              children: [
                _isGroup
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.15),
                          border: Border.all(color: AppColors.accent, width: 1.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isMatchChat ? Icons.groups : Icons.emoji_events_outlined,
                          color: AppColors.accent,
                          size: 20,
                        ),
                      )
                    : CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.card2,
                        backgroundImage: widget.otherAvatarUrl != null && widget.otherAvatarUrl!.isNotEmpty
                            ? NetworkImage(widget.otherAvatarUrl!)
                            : null,
                        child: widget.otherAvatarUrl == null || widget.otherAvatarUrl!.isEmpty
                            ? Text(
                                (widget.otherUsername ?? 'U').substring(0, 1).toUpperCase(),
                                style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold),
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
                        _title,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.isMatchChat)
                        Text(
                          tr('chat.lobby_sub'),
                          style: TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w500),
                        ),
                      if (widget.isTournamentChat)
                        Text(
                          'Grup Oficial Turneu',
                          style: TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w500),
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
                    Text(
                      'Doar Admin',
                      style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: onlyAdminCanSend,
                        activeThumbColor: AppColors.accent,
                        activeTrackColor: AppColors.accent.withValues(alpha: 0.3),
                        inactiveThumbColor: AppColors.muted,
                        inactiveTrackColor: AppColors.border,
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
                      return Center(child: CircularProgressIndicator(color: AppColors.accent));
                    }

                    final messages = snapshot.data?.docs ?? [];

                    if (messages.isEmpty) {
                      return Center(
                        child: Text(
                          widget.isMatchChat
                              ? tr('chat.lobby_hello')
                              : widget.isTournamentChat
                                  ? 'Bun venit în chat-ul oficial al turneului!'
                                  : 'Spune-i salut lui ${widget.otherUsername ?? 'Utilizator'}!',
                          style: TextStyle(color: AppColors.muted),
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
                                color: AppColors.card2.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.card2, width: 0.8),
                              ),
                              child: Text(
                                text,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.muted,
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
                              if (!isMe && _isGroup) ...[
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                                  child: Text(
                                    isMsgAdmin ? '[Organizator] $senderName' : senderName,
                                    style: TextStyle(
                                      color: isMsgAdmin ? AppColors.accent : AppColors.muted,
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
                                      ? AppColors.accent
                                      : (isMsgAdmin && widget.isTournamentChat)
                                          ? AppColors.card2.withValues(alpha: 0.8)
                                          : AppColors.card2,
                                  border: (!isMe && widget.isTournamentChat && isMsgAdmin)
                                      ? Border.all(color: AppColors.accent.withValues(alpha: 0.3), width: 1)
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
                                    color: isMe ? AppColors.onAccent : AppColors.text,
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
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border(top: BorderSide(color: AppColors.card2, width: 1)),
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              decoration: BoxDecoration(
                                color: AppColors.bad.withValues(alpha: 0.08),
                                border: Border.all(color: AppColors.bad.withValues(alpha: 0.3), width: 1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.lock_outline,
                                    color: AppColors.bad,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Doar administratorul turneului poate trimite mesaje în acest chat.',
                                      style: TextStyle(
                                        color: AppColors.bad.withValues(alpha: 0.9),
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
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border(top: BorderSide(color: AppColors.card2, width: 1)),
                      ),
                      child: SafeArea(
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                textCapitalization: TextCapitalization.sentences,
                                maxLines: null,
                                decoration: InputDecoration(
                                  hintText: 'Scrie un mesaj...',
                                  hintStyle: TextStyle(color: AppColors.muted),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  filled: true,
                                  fillColor: AppColors.bg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(24)),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                style: TextStyle(color: AppColors.text),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _sendMessage,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
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
