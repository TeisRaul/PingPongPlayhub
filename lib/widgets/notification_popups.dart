import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../screens/notifications_screen.dart';
import '../services/notification_actions.dart';
import '../theme/app_theme.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Popup în timp real: cât timp aplicația e deschisă și utilizatorul e logat, orice notificare
/// nouă apare imediat într-o fereastră (cu Acceptă / Refuză când se poate decide din ea).
class NotificationPopups {
  NotificationPopups._();
  static final NotificationPopups instance = NotificationPopups._();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  DateTime _startedAt = DateTime.now();
  final Set<String> _shown = {};

  void init() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  void _onUser(User? user) {
    _notifSub?.cancel();
    _notifSub = null;
    _startedAt = DateTime.now();
    _shown.clear();
    if (user == null) return;
    _notifSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUid', isEqualTo: user.uid)
        .snapshots()
        .listen(_onSnapshot, onError: (_) {});
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      if (change.doc.metadata.hasPendingWrites) continue;
      final data = change.doc.data();
      if (data == null || data['status'] != 'pending') continue;
      if (data['silent'] == true) continue; // ex. mesaje din chat-ul lobby-ului: doar clopoțel și push
      // Doar notificările apărute după ce te-ai logat (cele vechi se văd în clopoțel).
      final ts = data['timestamp'];
      if (ts is! Timestamp || ts.toDate().isBefore(_startedAt.subtract(const Duration(minutes: 2)))) continue;
      if (!_shown.add(change.doc.id)) continue;
      _show(change.doc.id, data);
    }
  }

  void _show(String id, Map<String, dynamic> data) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    showDialog(
      context: ctx,
      builder: (_) => _NotificationPopup(id: id, data: data),
    );
  }
}

class _NotificationPopup extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  const _NotificationPopup({required this.id, required this.data});

  @override
  State<_NotificationPopup> createState() => _NotificationPopupState();
}

class _NotificationPopupState extends State<_NotificationPopup> {
  bool _busy = false;

  Map<String, String> get _args => (widget.data['args'] is Map)
      ? Map<String, dynamic>.from(widget.data['args']).map((k, v) => MapEntry(k, '$v'))
      : <String, String>{};

  String get _title => widget.data['titleKey'] != null
      ? tr(widget.data['titleKey'], _args)
      : (widget.data['title'] ?? tr('notif.default')).toString();

  String get _body => widget.data['bodyKey'] != null
      ? tr(widget.data['bodyKey'], _args)
      : (widget.data['body'] ?? '').toString();

  Future<void> _decide(bool accept) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    String msg;
    try {
      msg = await NotificationActions.decide(widget.id, widget.data, accept: accept);
    } catch (e) {
      msg = tr('tr.error', {'error': '$e'});
    }
    nav.pop();
    if (msg.isNotEmpty) messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _dismiss() async {
    final nav = Navigator.of(context);
    try {
      await FirebaseFirestore.instance.collection('notifications').doc(widget.id).update({'status': 'read'});
    } catch (_) {}
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final bool actionable = NotificationActions.isActionable((widget.data['type'] ?? '').toString());
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      title: Row(
        children: [
          Icon(Icons.notifications_active, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(_title, style: TextStyle(color: AppColors.text, fontSize: 18))),
        ],
      ),
      content: Text(_body, style: TextStyle(color: AppColors.text70)),
      actions: _busy
          ? [Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: AppColors.accent))]
          : actionable
              ? [
                  TextButton(
                    onPressed: () => _decide(false),
                    child: Text(tr('n.decline'), style: const TextStyle(color: Colors.redAccent)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: () => _decide(true),
                    child: Text(tr('n.accept')),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      final ctx = appNavigatorKey.currentContext;
                      if (ctx != null) NotificationsDialog.show(ctx);
                    },
                    child: Text(tr('n.open_all')),
                  ),
                  ElevatedButton(onPressed: _dismiss, child: Text(tr('n.ok'))),
                ],
    );
  }
}
