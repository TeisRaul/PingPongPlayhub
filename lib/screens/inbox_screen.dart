import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'chat_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  User? get _currentUser => FirebaseAuth.instance.currentUser;

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return DateFormat('HH:mm').format(date);
    }
    return DateFormat('dd.MM.yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mesaje'),
          backgroundColor: const Color(0xFF131A2A),
        ),
        body: const Center(child: Text('Trebuie să fii autentificat!')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesaje'),
        backgroundColor: const Color(0xFF131A2A),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('uids', arrayContains: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // Important: Show full Firestore error with index link in case it hasn't been created yet
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: SelectableText(
                    'Eroare: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
          }

          final rawDocs = snapshot.data?.docs ?? [];
          final docs = List<QueryDocumentSnapshot>.from(rawDocs);
          
          // Sort client-side by lastMessageTime descending to completely bypass composite index requirement
          docs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final Timestamp? aTime = aData['lastMessageTime'] as Timestamp?;
            final Timestamp? bTime = bData['lastMessageTime'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Nicio conversație activă.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  SizedBox(height: 8),
                  Text('Trimite un mesaj prietenilor din lista de prieteni!', style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final chatId = docs[index].id;
              final bool isTournamentChat = data['isTournamentChat'] ?? false;

              String chatTitle = '';
              Widget leadingWidget;

              if (isTournamentChat) {
                chatTitle = data['title'] ?? 'Chat Turneu';
                leadingWidget = Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                  ),
                  child: const Icon(Icons.emoji_events_outlined, color: Color(0xFF00E5FF), size: 20),
                );
              } else {
                // Find other participant's data
                final List<dynamic> uids = data['uids'] ?? [];
                final List<dynamic> usernames = data['usernames'] ?? [];
                final List<dynamic> avatars = data['avatars'] ?? [];

                int otherIndex = uids.indexOf(user.uid) == 0 ? 1 : 0;
                if (uids.length < 2) return const SizedBox(); // safety check

                final String otherUid = uids[otherIndex];
                final String otherUsername = usernames.length > otherIndex ? usernames[otherIndex] : 'Utilizator';
                final String? otherAvatarUrl = avatars.length > otherIndex ? avatars[otherIndex] : null;

                chatTitle = otherUsername;
                leadingWidget = CircleAvatar(
                  backgroundColor: const Color(0xFF1E293B),
                  backgroundImage: otherAvatarUrl != null && otherAvatarUrl.isNotEmpty
                      ? NetworkImage(otherAvatarUrl)
                      : null,
                  child: otherAvatarUrl == null || otherAvatarUrl.isEmpty
                      ? Text(otherUsername.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                      : null,
                );
              }

              final String lastMsg = data['lastMessage'] ?? 'Niciun mesaj';
              final Timestamp? lastTime = data['lastMessageTime'];

              return Card(
                color: const Color(0xFF131A2A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.2)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: leadingWidget,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          chatTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_formatTime(lastTime), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      lastMsg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                  onTap: () {
                    if (isTournamentChat) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            chatId: chatId,
                            isTournamentChat: true,
                            tournamentTitle: chatTitle,
                            adminUid: data['adminUid'],
                          ),
                        ),
                      );
                    } else {
                      final List<dynamic> uids = data['uids'] ?? [];
                      int otherIndex = uids.indexOf(user.uid) == 0 ? 1 : 0;
                      final String otherUid = uids[otherIndex];
                      final List<dynamic> usernames = data['usernames'] ?? [];
                      final String otherUsername = usernames.length > otherIndex ? usernames[otherIndex] : 'Utilizator';
                      final List<dynamic> avatars = data['avatars'] ?? [];
                      final String? otherAvatarUrl = avatars.length > otherIndex ? avatars[otherIndex] : null;

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            chatId: chatId,
                            otherUid: otherUid,
                            otherUsername: otherUsername,
                            otherAvatarUrl: otherAvatarUrl,
                          ),
                        ),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
