import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/reminder_config.dart';

/// Citește / salvează setările de reminder.
/// - generale: `users/{uid}.reminderPrefs`
/// - pentru un meci: `match_reminders/{matchId}_{uid}` (au prioritate)
/// Notificările în sine le trimite funcția programată din functions/reminders.js.
class ReminderService {
  ReminderService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _matchRef(String matchId, String uid) =>
      _db.collection('match_reminders').doc('${matchId}_$uid');

  static Future<ReminderConfig> loadDefault(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    return ReminderConfig.fromMap(snap.data()?['reminderPrefs']);
  }

  static Future<void> saveDefault(String uid, ReminderConfig config) {
    return _db.collection('users').doc(uid).set({'reminderPrefs': config.toMap()}, SetOptions(merge: true));
  }

  /// Setările proprii ale meciului sau null dacă se folosesc cele generale.
  static Future<ReminderConfig?> loadForMatch(String matchId, String uid) async {
    final snap = await _matchRef(matchId, uid).get();
    if (!snap.exists) return null;
    return ReminderConfig.fromMap(snap.data());
  }

  static Future<void> saveForMatch(String matchId, String uid, ReminderConfig config) {
    return _matchRef(matchId, uid).set({
      'matchId': matchId,
      'uid': uid,
      ...config.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> clearForMatch(String matchId, String uid) => _matchRef(matchId, uid).delete();
}
