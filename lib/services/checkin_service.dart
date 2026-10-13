import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../utils/hour_utils.dart';

enum CheckInStatus {
  ok,
  invalidCode,
  notFound,
  wrongVenue,
  cancelled,
  finished,
  alreadyCheckedIn,
  notToday,
  ended,
}

class CheckInLookup {
  final CheckInStatus status;
  final String? matchId;
  final Map<String, dynamic>? data;

  /// Cu câte minute înainte de începutul rezervării a venit jucătorul (0 = la timp).
  final int minutesEarly;

  /// Cu câte minute după începutul rezervării a venit jucătorul (0 = la timp).
  final int minutesLate;

  /// Minutele rămase din rezervare în momentul sosirii.
  final int minutesLeft;

  /// Alte rezervări active pe aceeași masă care se suprapun cu momentul sosirii.
  final List<Map<String, dynamic>> overlaps;

  const CheckInLookup(
    this.status, {
    this.matchId,
    this.data,
    this.minutesEarly = 0,
    this.minutesLate = 0,
    this.minutesLeft = 0,
    this.overlaps = const [],
  });

  /// O rezervare anterioară pe aceeași masă are deja check-in => masa e probabil ocupată.
  bool get tableLikelyBusy => overlaps.any((m) => m['checkedIn'] == true);
}

/// Check-in la sală pe baza codului QR al jucătorului (codul este id-ul meciului).
class CheckInService {
  CheckInService._();

  // Cod scurt de bilet: 6 caractere ușor de dictat (fără 0/O, 1/I/L), derivat din
  // id-ul meciului. Calculul rămâne sub 2^53, deci dă același rezultat pe web și mobil.
  static const String _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // 31 de caractere
  static const int _codeLength = 6;
  static const int _codeModulus = 887503681; // 31^6

  /// Codul scurt al biletului, ex. `AV5T7D`.
  static String shortCode(String matchId) {
    var h = 7;
    for (final unit in matchId.codeUnits) {
      h = (h * 131 + unit) % _codeModulus;
    }
    var out = '';
    var n = h;
    for (var i = 0; i < _codeLength; i++) {
      out = _codeAlphabet[n % 31] + out;
      n ~/= 31;
    }
    return out;
  }

  /// Codul scurt afișat jucătorului, ex. `AV5-T7D`.
  static String formatShortCode(String code) =>
      code.length == _codeLength ? '${code.substring(0, 3)}-${code.substring(3)}' : code;

  /// Returnează codul scurt normalizat (majuscule, fără spații/cratime) sau `null`
  /// dacă textul nu arată ca un cod scurt.
  static String? normalizeShortCode(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.length != _codeLength) return null;
    for (final ch in cleaned.split('')) {
      if (!_codeAlphabet.contains(ch)) return null;
    }
    return cleaned;
  }

  /// Caută meciul de azi (al sălii, dacă [venueId] e dat) care are acest cod scurt.
  static Future<String?> _findByShortCode(String code, {String? venueId}) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('matches').where('date', isEqualTo: today);
    if (venueId != null) query = query.where('locationId', isEqualTo: venueId);
    final snap = await query.get();
    for (final d in snap.docs) {
      if (shortCode(d.id) == code) return d.id;
    }
    return null;
  }

  static String messageFor(CheckInStatus status, [Map<String, dynamic>? data]) {
    switch (status) {
      case CheckInStatus.ok:
        return 'Bilet valid.';
      case CheckInStatus.invalidCode:
        return 'Cod invalid!';
      case CheckInStatus.notFound:
        return 'Niciun bilet găsit pentru acest cod (verifică dacă e pentru azi și pentru această sală).';
      case CheckInStatus.wrongVenue:
        return 'Acest bilet este pentru altă sală!';
      case CheckInStatus.cancelled:
        return 'Acest meci a fost anulat!';
      case CheckInStatus.finished:
        return 'Acest meci este deja finalizat.';
      case CheckInStatus.alreadyCheckedIn:
        return 'Check-in deja efectuat pentru acest meci.';
      case CheckInStatus.notToday:
        return 'Biletul este pentru ${data?['date'] ?? 'altă zi'}, nu pentru azi.';
      case CheckInStatus.ended:
        return 'Intervalul rezervat s-a terminat la ${formatHour(data?['endHour'])}.';
    }
  }

  /// Extrage id-ul meciului din textul scanat sau introdus de mână.
  static String parseCode(String raw) {
    final code = raw.trim();
    // Un id de document Firestore nu poate conține '/'.
    if (code.isEmpty || code.contains('/')) return '';
    return code;
  }

  /// Citește meciul și îl validează.
  ///
  /// [venueId] = sala care face check-in. Adminul (`isAdmin`) poate face
  /// check-in la orice sală și în orice zi.
  static Future<CheckInLookup> lookup(
    String rawCode, {
    String? venueId,
    bool isAdmin = false,
  }) async {
    final short = normalizeShortCode(rawCode);
    final String matchId;
    if (short != null) {
      final found = await _findByShortCode(short, venueId: isAdmin ? null : venueId);
      if (found == null) return const CheckInLookup(CheckInStatus.notFound);
      matchId = found;
    } else {
      matchId = parseCode(rawCode);
      if (matchId.isEmpty) return const CheckInLookup(CheckInStatus.invalidCode);
    }

    final doc = await FirebaseFirestore.instance.collection('matches').doc(matchId).get();
    if (!doc.exists) return const CheckInLookup(CheckInStatus.notFound);

    final data = doc.data() ?? <String, dynamic>{};

    CheckInLookup fail(CheckInStatus s) => CheckInLookup(s, matchId: matchId, data: data);

    if (!isAdmin && venueId != null && data['locationId'] != venueId) {
      return fail(CheckInStatus.wrongVenue);
    }
    if (data['status'] == 'cancelled') return fail(CheckInStatus.cancelled);
    if (data['status'] == 'completed') return fail(CheckInStatus.finished);
    if (data['checkedIn'] == true) return fail(CheckInStatus.alreadyCheckedIn);

    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    if (!isAdmin && data['date'] != today) return fail(CheckInStatus.notToday);

    var minutesEarly = 0;
    var minutesLate = 0;
    var minutesLeft = 0;
    final overlaps = <Map<String, dynamic>>[];

    if (data['date'] == today) {
      final start = hourValue(data['startHour']);
      final end = hourValue(data['endHour']);
      final nowHour = now.hour + now.minute / 60;

      if (!isAdmin && nowHour >= end) return fail(CheckInStatus.ended);
      if (nowHour < start) minutesEarly = ((start - nowHour) * 60).round();
      if (nowHour > start) minutesLate = ((nowHour - start) * 60).round();
      minutesLeft = ((end - (nowHour < start ? start : nowHour)) * 60).round();

      // Cine mai are masa în intervalul [sosire, sfârșit)? Sala decide dacă o poate da.
      final tableId = data['tableId'];
      final locationId = (data['locationId'] ?? '').toString();
      if (tableId != null && locationId.isNotEmpty) {
        final from = nowHour < start ? nowHour : start;
        final snap = await FirebaseFirestore.instance
            .collection('matches')
            .where('locationId', isEqualTo: locationId)
            .where('date', isEqualTo: today)
            .get();
        for (final d in snap.docs) {
          if (d.id == matchId) continue;
          final m = d.data();
          if (m['status'] == 'cancelled' || m['status'] == 'completed') continue;
          if (m['tableId'] != tableId) continue;
          final s = hourValue(m['startHour']);
          final e = hourValue(m['endHour']);
          if (e > from && s < end) overlaps.add({...m, 'id': d.id});
        }
      }
    }

    return CheckInLookup(
      CheckInStatus.ok,
      matchId: matchId,
      data: data,
      minutesEarly: minutesEarly,
      minutesLate: minutesLate,
      minutesLeft: minutesLeft,
      overlaps: overlaps,
    );
  }

  /// Marchează meciul ca prezent. [markPaid] confirmă și plata cash încasată.
  /// [minutesLate] se salvează dacă jucătorul a întârziat; [approvedDespiteBusy]
  /// notează că sala a aprobat intrarea deși masa părea ocupată.
  static Future<void> confirm(
    String matchId, {
    bool markPaid = false,
    int minutesLate = 0,
    bool approvedDespiteBusy = false,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return FirebaseFirestore.instance.collection('matches').doc(matchId).update({
      'checkedIn': true,
      'checkedInAt': FieldValue.serverTimestamp(),
      if (uid != null) 'checkedInBy': uid,
      if (markPaid) 'paymentStatus': 'confirmed',
      if (minutesLate > 0) 'lateMinutes': minutesLate,
      if (approvedDespiteBusy) 'approvedDespiteBusy': true,
      'waiting': false,
      'waitingSince': FieldValue.delete(),
    });
  }

  /// Jucătorul e la sală, dar masa nu e liberă încă: rămâne la așteptare.
  static Future<void> hold(String matchId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return FirebaseFirestore.instance.collection('matches').doc(matchId).update({
      'waiting': true,
      'waitingSince': FieldValue.serverTimestamp(),
      if (uid != null) 'waitingBy': uid,
    });
  }

  /// Jucătorul nu s-a prezentat: rezervarea se anulează și gazda pierde 5 puncte de încredere.
  static Future<void> markNoShow(String matchId, String hostUid) {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.update(db.collection('matches').doc(matchId), {
      'status': 'cancelled',
      'cancellationReason': 'No-Show raportat de sală',
    });
    if (hostUid.isNotEmpty) {
      batch.update(db.collection('users').doc(hostUid), {
        'trustScore': FieldValue.increment(-5),
      });
    }
    return batch.commit();
  }
}
