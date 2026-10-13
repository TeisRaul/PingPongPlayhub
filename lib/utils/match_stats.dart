/// Statistici derivate din documentele `matches`.
///
/// Un meci confirmat salvează câștigătorul în `winnerUid` (1v1) sau în
/// `winnerUids` (2v2). Un meci egal nu are câștigător.
bool didUserWinMatch(Map<String, dynamic> match, String uid) {
  if (match['winnerUid'] == uid) return true;
  final winners = match['winnerUids'];
  return winners is List && winners.contains(uid);
}

/// Procentul de victorii, ex. "60%" sau "33.3%". "0%" dacă nu sunt meciuri.
String formatWinRate(int wins, int total) {
  if (total <= 0) return '0%';
  final pct = wins / total * 100;
  final text = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
  return '$text%';
}
