import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// Nota medie (★ 4.6 (12)) afișată la alegerea unei săli sau a unui antrenor.
/// Fără recenzii apare „Nou”.
class RatingBadge extends StatelessWidget {
  final double? rating;
  final int count;
  final double size;

  const RatingBadge({super.key, required this.rating, required this.count, this.size = 13});

  @override
  Widget build(BuildContext context) {
    if (count <= 0 || rating == null) {
      return Text(tr('rev.new'), style: TextStyle(color: AppColors.muted, fontSize: size - 1));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, color: AppColors.gold, size: size + 3),
        const SizedBox(width: 2),
        Text(
          rating!.toStringAsFixed(1),
          style: TextStyle(color: AppColors.text, fontSize: size, fontWeight: FontWeight.bold),
        ),
        Text(' ($count)', style: TextStyle(color: AppColors.muted, fontSize: size - 1)),
      ],
    );
  }
}
