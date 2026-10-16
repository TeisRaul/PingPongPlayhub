import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/sports.dart';
import '../l10n/strings.dart';
import '../screens/match_detail_screen.dart';
import '../screens/shared_match_screen.dart';
import '../utils/hour_utils.dart';
import '../widgets/notification_popups.dart';

/// Partajarea unui meci printr-un link și deschiderea lui când cineva apasă pe link.
///
/// Link-ul are forma `https://<site>/?match=<id>` și duce în versiunea web a aplicației
/// (firebase.json → hosting). Cine nu e logat se loghează întâi, apoi i se arată meciul.
class ShareService {
  ShareService._();

  /// Adresa site-ului din Firebase Hosting. Dacă ai domeniu propriu, schimbă-l aici.
  static const String baseUrl = 'https://pingpongplayhub1.web.app';

  /// Meciul din link, de arătat imediat ce ecranul principal e gata (după login).
  static String? pendingMatchId;

  /// Rezervarea proprie de deschis direct (cu biletul QR), ex. după întoarcerea de la plată: `/?booking=<id>`.
  static String? pendingBookingId;

  /// `true` cât timp ecranul principal al jucătorului e deschis.
  static bool homeReady = false;

  static String linkFor(String matchId) => '$baseUrl/?match=$matchId';

  /// La pornirea aplicației web: reține meciul din adresa din browser.
  static void captureInitialWebLink() {
    if (!kIsWeb) return;
    try {
      final id = Uri.base.queryParameters['match'];
      if (id != null && id.isNotEmpty) pendingMatchId = id;
      final booking = Uri.base.queryParameters['booking'];
      if (booking != null && booking.isNotEmpty) pendingBookingId = booking;
    } catch (_) {}
  }

  /// Extrage id-ul meciului dintr-un link: `https://.../?match=ID` sau `pingpongplayhub://match?id=ID`.
  static String? matchIdFromUri(Uri uri) {
    final fromQuery = uri.queryParameters['match'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    if (uri.scheme == 'pingpongplayhub' && uri.host == 'match') {
      final id = uri.queryParameters['id'];
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  /// Un link primit cât aplicația rulează deja.
  static void handleUri(Uri uri) {
    final booking = uri.queryParameters['booking'];
    if (booking != null && booking.isNotEmpty) {
      pendingBookingId = booking;
      if (homeReady) consumePending();
      return;
    }
    final id = matchIdFromUri(uri);
    if (id == null) return;
    pendingMatchId = id;
    if (homeReady) consumePending();
  }

  /// Deschide meciul reținut, dacă există și jucătorul e logat.
  static void consumePending() {
    final booking = pendingBookingId;
    if (booking != null && FirebaseAuth.instance.currentUser != null) {
      final nav = appNavigatorKey.currentState;
      if (nav != null) {
        pendingBookingId = null;
        nav.push(MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: booking, mode: MatchDetailMode.player)));
        return;
      }
    }
    final id = pendingMatchId;
    if (id == null || FirebaseAuth.instance.currentUser == null) return;
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    pendingMatchId = null;
    nav.push(MaterialPageRoute(builder: (_) => SharedMatchScreen(matchId: id)));
  }

  static String shareText(String matchId, Map<String, dynamic> m) {
    return tr('share.text', {
      'sport': sportLabel((m['sport'] ?? '').toString()),
      'venue': (m['locationName'] ?? '').toString(),
      'date': (m['date'] ?? '').toString(),
      'time': '${formatHour(m['startHour'])} - ${formatHour(m['endHour'])}',
      'link': linkFor(matchId),
    });
  }

  /// Deschide meniul de partajare al telefonului; pe web copiază textul cu link în clipboard.
  static Future<void> shareMatch(BuildContext context, String matchId, Map<String, dynamic> m) async {
    final text = shareText(matchId, m);
    final messenger = ScaffoldMessenger.of(context);
    if (!kIsWeb) {
      try {
        await Share.share(text, subject: tr('share.subject'));
        return;
      } catch (_) {
        // cădem pe copierea în clipboard
      }
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(tr('share.copied'))));
  }
}
