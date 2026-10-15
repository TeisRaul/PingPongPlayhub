import 'package:flutter/material.dart';

import '../data/sport_specs.dart';
import '../data/sports.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// Detaliile și regulile unei săli pentru un sport, așa cum le văd jucătorii.
class SportSpecsCard extends StatelessWidget {
  final String sport;
  final Map<String, dynamic>? specs;
  final String venueRules;
  final bool showTitle;
  final bool rulesOnly; // doar regulile generale ale sălii

  const SportSpecsCard({
    super.key,
    required this.sport,
    required this.specs,
    this.venueRules = '',
    this.showTitle = true,
    this.rulesOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (rulesOnly) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('spec.rules_heading'), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(venueRules.trim(), style: TextStyle(color: AppColors.text70, fontSize: 13)),
          ],
        ),
      );
    }
    final rows = SportSpecs.summary(sport, specs);
    final int minAge = SportSpecs.minAge(specs);
    final String rules = SportSpecs.rulesOf(specs);
    final bool supervised = SportSpecs.isSupervised(sport, specs);
    final int cap = ((specs?['maxPlayers'] as num?) ?? 0).toInt();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(sportLabel(sport), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          if (cap > 0 && (sport == 'mma' || sport == 'box' || sport == 'handbal'))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(tr('spec.capacity_note', {'n': '$cap'}), style: TextStyle(color: AppColors.text70, fontSize: 13)),
            ),
          ...rows.where((r) => !((sport == 'mma' || sport == 'box' || sport == 'handbal') && r.$1 == tr('spec.f.maxPlayers'))).map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(r.$1, style: TextStyle(color: AppColors.text70, fontSize: 13))),
                      const SizedBox(width: 8),
                      Text(r.$2, style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
          if (supervised)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, color: Colors.orangeAccent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(tr('spec.supervised_note'), style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
                ],
              ),
            ),
          if (minAge > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.cake_outlined, color: Colors.orangeAccent, size: 16),
                  const SizedBox(width: 6),
                  Text(tr('spec.min_age_note', {'age': '$minAge'}), style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                ],
              ),
            ),
          if (rules.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(rules, style: TextStyle(color: AppColors.text70, fontSize: 12, fontStyle: FontStyle.italic)),
            ),
          if (venueRules.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('spec.rules_heading'), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(venueRules.trim(), style: TextStyle(color: AppColors.text70, fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
