import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../l10n/strings.dart';

/// Un antrenor asociat unei săli, așa cum apare în lista de alegere.
class TrainerInfo {
  final String id;
  final String name;
  final double? pricePerSession;
  final double? pricePerMonth;
  final Map<String, dynamic> data;

  const TrainerInfo({
    required this.id,
    required this.name,
    required this.pricePerSession,
    required this.pricePerMonth,
    required this.data,
  });
}

/// Statusurile unei sesiuni cu antrenor (câmpul `status` din `reservations`).
class TrainerStatus {
  static const pending = 'pending'; // așteaptă răspunsul antrenorului
  static const confirmed = 'confirmed';
  static const declined = 'declined';
  static const cancelled = 'cancelled';
  static const rescheduleRequested = 'reschedule_requested';
}

class TrainerService {
  // Cheile programului salvat de antrenor (rămân în română în Firestore).
  static const List<String> _dayKeys = ['Luni', 'Marți', 'Miercuri', 'Joi', 'Vineri', 'Sâmbătă', 'Duminică'];
  static const Map<String, String> _defaultSchedule = {
    'Luni': '08:00 - 20:00',
    'Marți': '08:00 - 20:00',
    'Miercuri': '08:00 - 20:00',
    'Joi': '08:00 - 20:00',
    'Vineri': '08:00 - 20:00',
    'Sâmbătă': 'Liber',
    'Duminică': 'Liber',
  };

  /// Linie scurtă despre tipul sesiunii (abonament lunar, grup), sau null pentru o sesiune simplă.
  static String? detailsLine(Map<String, dynamic> b) {
    final parts = <String>[];
    if (b['plan'] == 'month') parts.add(tr('tr.plan_month'));
    final int persons = (b['persons'] as num?)?.toInt() ?? 1;
    if (persons > 1) {
      final names = <String>[
        if ((b['clientName'] ?? '').toString().isNotEmpty) b['clientName'].toString(),
        ...((b['groupNames'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty),
      ];
      parts.add(tr('tr.group_line', {'n': '$persons', 'names': names.join(', ')}));
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String dayKey(DateTime d) => _dayKeys[d.weekday - 1];

  static String nameOf(Map<String, dynamic> d) {
    final full = '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
    if (full.isNotEmpty) return full;
    final u = (d['username'] ?? '').toString().trim();
    return u;
  }

  static double? _num(dynamic v) => v is num ? v.toDouble() : null;

  /// Antrenorii care lucrează la sala [venueId].
  static Future<List<TrainerInfo>> trainersForVenue(String venueId) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('isTrainer', isEqualTo: true)
        .where('trainerVenueId', isEqualTo: venueId)
        .get();
    final list = snap.docs.map((d) {
      final data = d.data();
      return TrainerInfo(
        id: d.id,
        name: nameOf(data),
        pricePerSession: _num(data['trainerPricePerSession'] ?? data['trainerPrice']),
        pricePerMonth: _num(data['trainerPricePerMonth']),
        data: data,
      );
    }).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Programul antrenorului (cel salvat sau cel implicit) permite intervalul [startHour, endHour)?
  static bool worksAt(Map<String, dynamic> trainer, DateTime date, int startHour, int endHour) {
    final raw = trainer['trainerSchedule'];
    final Map<String, dynamic> schedule = raw is Map ? Map<String, dynamic>.from(raw) : _defaultSchedule;
    final String value = (schedule[dayKey(date)] ?? '').toString();
    final m = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})').firstMatch(value);
    if (m == null) return false; // „Liber” sau text fără interval = nu lucrează
    final int from = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
    int to = int.parse(m.group(3)!) * 60 + int.parse(m.group(4)!);
    if (to == 0) to = 24 * 60;
    return startHour * 60 >= from && endHour * 60 <= to;
  }

  static String _hh(int h) => '${h.toString().padLeft(2, '0')}:00';

  static Future<void> _notify({
    required String toUid,
    required String titleKey,
    required String bodyKey,
    required Map<String, String> args,
    required String type,
    String? matchId,
    Map<String, dynamic> extra = const {},
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    final ref = FirebaseFirestore.instance.collection('notifications').doc();
    await ref.set({
      'toUid': toUid,
      'fromUid': me?.uid ?? '',
      'fromUsername': '',
      'fromAvatarUrl': '',
      'titleKey': titleKey,
      'bodyKey': bodyKey,
      'args': args,
      'title': 'Playhub',
      'body': '',
      'type': type,
      'status': 'pending',
      if (matchId != null) 'matchId': matchId,
      ...extra,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Creează cererea de sesiune către antrenor (status `pending`) și îl anunță.
  static Future<String> requestSession({
    required TrainerInfo trainer,
    required String matchId,
    required String locationId,
    required String locationName,
    required String sport,
    required DateTime date,
    required int startHour,
    required int endHour,
    String plan = 'session', // 'session' | 'month'
    int persons = 1,
    List<Map<String, String>> group = const [], // prietenii adăugați în lobby: [{uid, name}]
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw Exception('not-authenticated');
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(me.uid).get();
    final u = userDoc.data() ?? {};
    final clientName = (u['username'] ?? nameOf(u)).toString().trim().isEmpty
        ? (me.email ?? '').split('@').first
        : (u['username'] ?? nameOf(u)).toString();

    final dateLabel = DateFormat('dd.MM.yyyy').format(date);
    final timeLabel = '${_hh(startHour)} - ${_hh(endHour)}';

    final ref = FirebaseFirestore.instance.collection('reservations').doc();
    await ref.set({
      'creatorId': me.uid,
      'clientName': clientName,
      'trainerId': trainer.id,
      'trainerName': trainer.name,
      'matchId': matchId,
      'locationId': locationId,
      'locationName': locationName,
      'sport': sport,
      'date': dateLabel,
      'dateIso': DateFormat('yyyy-MM-dd').format(date),
      'time': timeLabel,
      'startHour': startHour,
      'endHour': endHour,
      'pricePerSession': trainer.pricePerSession,
      'pricePerMonth': trainer.pricePerMonth,
      'plan': plan,
      'persons': persons,
      'groupUids': group.map((g) => g['uid'] ?? '').toList(),
      'groupNames': group.map((g) => g['name'] ?? '').toList(),
      'status': TrainerStatus.pending,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await _notify(
      toUid: trainer.id,
      titleKey: 'tr.n_req_title',
      bodyKey: plan == 'month'
          ? (persons > 1 ? 'tr.n_req_body_month_group' : 'tr.n_req_body_month')
          : (persons > 1 ? 'tr.n_req_body_group' : 'tr.n_req_body'),
      args: {'client': clientName, 'date': dateLabel, 'time': timeLabel, 'venue': locationName, 'persons': '$persons'},
      type: 'trainer_request',
      matchId: matchId,
      extra: {'reservationId': ref.id},
    );
    return ref.id;
  }

  /// Antrenorul acceptă sau refuză. Aruncă `overlap` dacă are deja o sesiune confirmată în același interval.
  static Future<void> respond(Map<String, dynamic> reservation, {required bool accept}) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw Exception('not-authenticated');
    final String id = reservation['id'];

    if (accept) {
      final others = await FirebaseFirestore.instance
          .collection('reservations')
          .where('trainerId', isEqualTo: me.uid)
          .get();
      final int s = (reservation['startHour'] as num?)?.toInt() ?? -1;
      final int e = (reservation['endHour'] as num?)?.toInt() ?? -1;
      for (final d in others.docs) {
        if (d.id == id) continue;
        final o = d.data();
        if (o['status'] != TrainerStatus.confirmed && o['status'] != TrainerStatus.rescheduleRequested) continue;
        if (o['dateIso'] != reservation['dateIso'] || s < 0) continue;
        final int os = (o['startHour'] as num?)?.toInt() ?? -1;
        final int oe = (o['endHour'] as num?)?.toInt() ?? -1;
        if (os >= 0 && s < oe && os < e) throw Exception('overlap');
      }
    }

    await FirebaseFirestore.instance.collection('reservations').doc(id).update({
      'status': accept ? TrainerStatus.confirmed : TrainerStatus.declined,
      'respondedAt': FieldValue.serverTimestamp(),
    });

    final String clientId = reservation['creatorId'] ?? '';
    // Prietenii din lobby află și ei răspunsul antrenorului.
    for (final dynamic g in (reservation['groupUids'] as List?) ?? const []) {
      final String gid = g.toString();
      if (gid.isEmpty || gid == clientId) continue;
      try {
        await _notify(
          toUid: gid,
          titleKey: accept ? 'tr.n_acc_title' : 'tr.n_dec_title',
          bodyKey: accept ? 'tr.n_acc_body' : 'tr.n_dec_body',
          args: {
            'trainer': (reservation['trainerName'] ?? '').toString(),
            'date': (reservation['date'] ?? '').toString(),
            'time': (reservation['time'] ?? '').toString(),
          },
          type: 'trainer_response',
          matchId: reservation['matchId'],
        );
      } catch (_) {}
    }
    if (clientId.isNotEmpty) {
      await _notify(
        toUid: clientId,
        titleKey: accept ? 'tr.n_acc_title' : 'tr.n_dec_title',
        bodyKey: accept ? 'tr.n_acc_body' : 'tr.n_dec_body',
        args: {
          'trainer': (reservation['trainerName'] ?? '').toString(),
          'date': (reservation['date'] ?? '').toString(),
          'time': (reservation['time'] ?? '').toString(),
        },
        type: 'trainer_response',
        matchId: reservation['matchId'],
      );
    }
  }

  /// Clientul evaluează antrenorul după o sesiune. Media se ține pe profilul antrenorului
  /// (trainerRating / trainerRatingCount), recenzia în `users/{antrenor}/reviews`.
  static Future<void> reviewTrainer(Map<String, dynamic> reservation, int rating, String comment) async {
    final me = FirebaseAuth.instance.currentUser;
    final String trainerId = (reservation['trainerId'] ?? '').toString();
    final String reservationId = (reservation['id'] ?? '').toString();
    if (me == null || trainerId.isEmpty || reservationId.isEmpty) throw Exception('invalid-review');
    final db = FirebaseFirestore.instance;
    final trainerRef = db.collection('users').doc(trainerId);
    final reviewRef = trainerRef.collection('reviews').doc();
    final reservationRef = db.collection('reservations').doc(reservationId);
    final myDoc = await db.collection('users').doc(me.uid).get();
    final String author = nameOf(myDoc.data() ?? <String, dynamic>{});
    await db.runTransaction((tx) async {
      final snap = await tx.get(trainerRef);
      final d = snap.data() ?? <String, dynamic>{};
      final double total = ((d['trainerRatingTotal'] as num?)?.toDouble() ?? 0) + rating;
      final int count = ((d['trainerRatingCount'] as num?)?.toInt() ?? 0) + 1;
      tx.update(trainerRef, {
        'trainerRatingTotal': total,
        'trainerRatingCount': count,
        'trainerRating': total / count,
      });
      tx.set(reviewRef, {
        'authorId': me.uid,
        'authorUid': me.uid,
        'authorUsername': author,
        'rating': rating,
        'comment': comment,
        'reservationId': reservationId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(reservationRef, {'reviewed': true});
    });
  }

  /// Clientul anulează sesiunea (sau cererea încă neconfirmată).
  static Future<void> cancelByClient(Map<String, dynamic> reservation) async {
    await FirebaseFirestore.instance.collection('reservations').doc(reservation['id']).update({
      'status': TrainerStatus.cancelled,
      'cancelledAt': FieldValue.serverTimestamp(),
    });
    final String trainerId = reservation['trainerId'] ?? '';
    if (trainerId.isNotEmpty) {
      await _notify(
        toUid: trainerId,
        titleKey: 'tr.n_can_title',
        bodyKey: 'tr.n_can_body',
        args: {
          'client': (reservation['clientName'] ?? '').toString(),
          'date': (reservation['date'] ?? '').toString(),
          'time': (reservation['time'] ?? '').toString(),
        },
        type: 'trainer_cancelled',
        matchId: reservation['matchId'],
      );
    }
  }

  /// Când gazda își anulează meciul, sesiunile cu antrenor legate de el se anulează.
  static Future<void> cancelForMatch(String matchId) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('reservations')
        .where('creatorId', isEqualTo: me.uid)
        .where('matchId', isEqualTo: matchId)
        .get();
    for (final d in snap.docs) {
      final data = d.data();
      if (data['status'] == TrainerStatus.cancelled || data['status'] == TrainerStatus.declined) continue;
      data['id'] = d.id;
      await cancelByClient(data);
    }
  }

  /// Clientul propune o altă dată/oră; antrenorul este anunțat.
  static Future<void> requestReschedule(Map<String, dynamic> reservation, DateTime newDate, int newHour) async {
    final String requestedDate = DateFormat('dd.MM.yyyy').format(newDate);
    final String requestedTime = _hh(newHour);
    await FirebaseFirestore.instance.collection('reservations').doc(reservation['id']).update({
      'status': TrainerStatus.rescheduleRequested,
      'requestedDate': requestedDate,
      'requestedTime': requestedTime,
      'requestedDateIso': DateFormat('yyyy-MM-dd').format(newDate),
    });
    final String trainerId = reservation['trainerId'] ?? '';
    if (trainerId.isNotEmpty) {
      await _notify(
        toUid: trainerId,
        titleKey: 'tr.n_resq_title',
        bodyKey: 'tr.n_resq_body',
        args: {'client': (reservation['clientName'] ?? '').toString(), 'date': requestedDate, 'time': requestedTime},
        type: 'trainer_reschedule',
        matchId: reservation['matchId'],
      );
    }
  }

  /// Antrenorul aprobă sau respinge mutarea. La aprobare se verifică din nou suprapunerile.
  static Future<void> answerReschedule(Map<String, dynamic> reservation, {required bool approve}) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw Exception('not-authenticated');
    final String id = reservation['id'];
    final Map<String, dynamic> update = {
      'status': TrainerStatus.confirmed,
      'requestedDate': FieldValue.delete(),
      'requestedTime': FieldValue.delete(),
      'requestedDateIso': FieldValue.delete(),
    };
    String date = (reservation['requestedDate'] ?? '').toString();
    String time = (reservation['requestedTime'] ?? '').toString();

    if (approve) {
      final int oldS = (reservation['startHour'] as num?)?.toInt() ?? 0;
      final int oldE = (reservation['endHour'] as num?)?.toInt() ?? (oldS + 1);
      final int newS = int.tryParse(time.split(':').first) ?? oldS;
      final int newE = newS + (oldE - oldS).clamp(1, 12).toInt();
      String iso = (reservation['requestedDateIso'] ?? '').toString();
      if (iso.isEmpty) {
        try {
          iso = DateFormat('yyyy-MM-dd').format(DateFormat('dd.MM.yyyy').parse(date));
        } catch (_) {}
      }
      final others = await FirebaseFirestore.instance
          .collection('reservations')
          .where('trainerId', isEqualTo: me.uid)
          .get();
      for (final d in others.docs) {
        if (d.id == id) continue;
        final o = d.data();
        if (o['status'] != TrainerStatus.confirmed && o['status'] != TrainerStatus.rescheduleRequested) continue;
        if (o['dateIso'] != iso) continue;
        final int os = (o['startHour'] as num?)?.toInt() ?? -1;
        final int oe = (o['endHour'] as num?)?.toInt() ?? -1;
        if (os >= 0 && newS < oe && os < newE) throw Exception('overlap');
      }
      update['date'] = date;
      update['dateIso'] = iso;
      update['startHour'] = newS;
      update['endHour'] = newE;
      update['time'] = '${_hh(newS)} - ${_hh(newE)}';
    }
    await FirebaseFirestore.instance.collection('reservations').doc(id).update(update);

    final String clientId = reservation['creatorId'] ?? '';
    if (clientId.isNotEmpty) {
      await _notify(
        toUid: clientId,
        titleKey: approve ? 'tr.n_resok_title' : 'tr.n_resno_title',
        bodyKey: approve ? 'tr.n_resok_body' : 'tr.n_resno_body',
        args: {'trainer': (reservation['trainerName'] ?? '').toString(), 'date': date, 'time': time},
        type: 'trainer_reschedule_answer',
        matchId: reservation['matchId'],
      );
    }
  }
}
