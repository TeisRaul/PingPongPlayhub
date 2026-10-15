import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/sports.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/hour_utils.dart';
import '../utils/match_stats.dart';

class _Entry {
  final DateTime when;
  final String venue;
  final String sport;
  final bool hasWinner;
  final bool won;
  final int? ratingBefore;
  final int? ratingAfter;
  final List<({String uid, String username})> others;

  _Entry({
    required this.when,
    required this.venue,
    required this.sport,
    required this.hasWinner,
    required this.won,
    required this.ratingBefore,
    required this.ratingAfter,
    required this.others,
  });

  int? get delta => (ratingBefore != null && ratingAfter != null) ? ratingAfter! - ratingBefore! : null;
}

class _Partner {
  final String username;
  int count = 0;
  int wins = 0;
  int losses = 0;
  _Partner(this.username);
}

/// Statistici personale: istoric, evoluția ratingului, jucătorii cu care joci cel mai des.
class MyStatsScreen extends StatefulWidget {
  const MyStatsScreen({super.key});

  @override
  State<MyStatsScreen> createState() => _MyStatsScreenState();
}

class _MyStatsScreenState extends State<MyStatsScreen> {
  bool _loading = true;
  bool _error = false;
  int _rating = 0;
  List<_Entry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      final db = FirebaseFirestore.instance;
      final userDoc = await db.collection('users').doc(me.uid).get();
      final snap = await db.collection('matches').where('joinedUids', arrayContains: me.uid).get();
      final entries = <_Entry>[];
      for (final d in snap.docs) {
        final m = d.data();
        if (m['status'] != 'completed') continue;
        DateTime when;
        try {
          when = dateAtHour((m['date'] ?? '').toString(), m['startHour']);
        } catch (_) {
          continue;
        }
        final winners = m['winnerUids'];
        final hasWinner = m['winnerUid'] != null || (winners is List && winners.isNotEmpty);
        int? before;
        int? after;
        final rc = m['ratingChanges'];
        if (rc is Map && rc[me.uid] is Map) {
          before = (rc[me.uid]['before'] as num?)?.toInt();
          after = (rc[me.uid]['after'] as num?)?.toInt();
        }
        final others = <({String uid, String username})>[];
        for (final p in (m['joinedPlayers'] as List?) ?? const []) {
          if (p is Map && p['uid'] != null && p['uid'].toString() != me.uid) {
            others.add((uid: p['uid'].toString(), username: (p['username'] ?? '').toString()));
          }
        }
        entries.add(_Entry(
          when: when,
          venue: (m['locationName'] ?? '-').toString(),
          sport: (m['sport'] ?? 'ping_pong').toString(),
          hasWinner: hasWinner,
          won: didUserWinMatch(m, me.uid),
          ratingBefore: before,
          ratingAfter: after,
          others: others,
        ));
      }
      entries.sort((a, b) => a.when.compareTo(b.when));
      if (!mounted) return;
      setState(() {
        _rating = (userDoc.data()?['rating'] as num?)?.toInt() ?? 0;
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  int get _wins => _entries.where((e) => e.won).length;

  int get _bestStreak {
    int best = 0, cur = 0;
    for (final e in _entries) {
      if (e.won) {
        cur++;
        if (cur > best) best = cur;
      } else if (e.hasWinner) {
        cur = 0;
      }
    }
    return best;
  }

  Widget _card(String title, Widget child) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _tile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _ratingChart() {
    final withRating = _entries.where((e) => e.ratingAfter != null).toList();
    if (withRating.isEmpty) {
      return Text(tr('stats.not_enough'), style: TextStyle(color: AppColors.muted));
    }
    final values = <double>[
      (withRating.first.ratingBefore ?? withRating.first.ratingAfter!).toDouble(),
      for (final e in withRating) e.ratingAfter!.toDouble(),
    ];
    final spots = [for (int i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])];
    final minY = values.reduce((a, b) => a < b ? a : b) - 20;
    final maxY = values.reduce((a, b) => a > b ? a : b) + 20;
    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: AppColors.text12, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, meta) => Text(
                  v.toInt().toString(),
                  style: TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: values.length > 1 ? (values.length - 1).toDouble() : 1.0,
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.accent,
              barWidth: 3,
              dotData: FlDotData(show: values.length <= 30),
              belowBarData: BarAreaData(show: true, color: AppColors.accent.withValues(alpha: 0.12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rankedList(List<MapEntry<String, String>> rows) {
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(child: Text(r.key, style: TextStyle(color: AppColors.text), overflow: TextOverflow.ellipsis)),
                Text(r.value, style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _history() {
    final recent = _entries.reversed.take(20).toList();
    return Column(
      children: [
        for (final e in recent)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 78,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: (!e.hasWinner ? AppColors.muted : (e.won ? AppColors.good : AppColors.bad)).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    !e.hasWinner ? tr('stats.draw') : (e.won ? tr('stats.win') : tr('stats.loss')),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: !e.hasWinner ? AppColors.muted : (e.won ? AppColors.good : AppColors.bad),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.venue, style: TextStyle(color: AppColors.text), overflow: TextOverflow.ellipsis),
                      Text(
                        '${e.when.year}-${e.when.month.toString().padLeft(2, '0')}-${e.when.day.toString().padLeft(2, '0')} · ${sportLabel(e.sport)}',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (e.delta != null)
                  Text(
                    e.delta! > 0 ? '+${e.delta}' : '${e.delta}',
                    style: TextStyle(
                      color: e.delta! > 0 ? AppColors.good : (e.delta! < 0 ? AppColors.bad : AppColors.muted),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _content() {
    final total = _entries.length;
    final partners = <String, _Partner>{};
    final venues = <String, int>{};
    final sports = <String, int>{};
    for (final e in _entries) {
      venues[e.venue] = (venues[e.venue] ?? 0) + 1;
      sports[e.sport] = (sports[e.sport] ?? 0) + 1;
      for (final o in e.others) {
        final p = partners.putIfAbsent(o.uid, () => _Partner(o.username.isEmpty ? tr('common.unknown_player') : o.username));
        p.count++;
        if (e.hasWinner) {
          if (e.won) {
            p.wins++;
          } else {
            p.losses++;
          }
        }
      }
    }
    final topPartners = partners.values.toList()..sort((a, b) => b.count.compareTo(a.count));
    final topVenues = venues.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topSports = sports.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return [
      Row(
        children: [
          _tile(tr('stats.played'), '$total', AppColors.accent),
          _tile(tr('stats.wins'), '$_wins', AppColors.good),
          _tile(tr('stats.winrate'), formatWinRate(_wins, total), AppColors.gold),
          _tile(tr('stats.streak'), '$_bestStreak', AppColors.accent2),
        ],
      ),
      const SizedBox(height: 16),
      _card(
        '${tr('stats.rating_title')} · $_rating',
        _ratingChart(),
      ),
      if (topPartners.isNotEmpty)
        _card(
          tr('stats.partners'),
          _rankedList([
            for (final p in topPartners.take(5))
              MapEntry(
                p.username,
                '${tr('stats.matches_n', {'n': '${p.count}'})} · ${tr('stats.record', {'w': '${p.wins}', 'l': '${p.losses}'})}',
              ),
          ]),
        ),
      if (topVenues.isNotEmpty)
        _card(
          tr('stats.venues'),
          _rankedList([
            for (final v in topVenues.take(3)) MapEntry(v.key, tr('stats.matches_n', {'n': '${v.value}'})),
          ]),
        ),
      if (topSports.isNotEmpty)
        _card(
          tr('stats.sports'),
          _rankedList([
            for (final s in topSports) MapEntry(sportLabel(s.key), tr('stats.matches_n', {'n': '${s.value}'})),
          ]),
        ),
      _card(tr('stats.history'), _history()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('stats.title'))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _error
              ? Center(child: Text(tr('stats.error'), style: TextStyle(color: AppColors.muted)))
              : _entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(tr('stats.empty'), style: TextStyle(color: AppColors.muted), textAlign: TextAlign.center),
                      ),
                    )
                  : ListView(padding: const EdgeInsets.all(16), children: _content()),
    );
  }
}
