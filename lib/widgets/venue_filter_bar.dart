import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/venue_filters.dart';

/// Butonul „Filtre și sortare” de deasupra listei de săli, cu fereastra de filtre.
class VenueFilterBar extends StatelessWidget {
  final VenueFilters filters;

  /// Se apelează când se alege sortarea după distanță; întoarce `true` dacă locația e disponibilă.
  final Future<bool> Function() requestLocation;
  final ValueChanged<VenueFilters> onChanged;

  const VenueFilterBar({
    super.key,
    required this.filters,
    required this.requestLocation,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showModalBottomSheet<VenueFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _FilterSheet(initial: filters.copy()),
    );
    if (result == null) return;
    if (result.sort == VenueSort.distance) {
      final ok = await requestLocation();
      if (!ok) {
        result.sort = VenueSort.recommended;
        messenger.showSnackBar(SnackBar(content: Text(tr('vf.loc_denied')), backgroundColor: Colors.orange));
      }
    }
    onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final n = filters.activeCount;
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () => _open(context),
          icon: Icon(Icons.tune, size: 18, color: AppColors.accent),
          label: Text(
            n > 0 ? '${tr('vf.filters')} ($n)' : tr('vf.filters'),
            style: TextStyle(color: AppColors.accent),
          ),
          style: OutlinedButton.styleFrom(side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6))),
        ),
        if (n > 0)
          TextButton(
            onPressed: () => onChanged(VenueFilters()),
            child: Text(tr('vf.reset'), style: TextStyle(color: AppColors.muted)),
          ),
      ],
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final VenueFilters initial;
  const _FilterSheet({required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const double _maxSlider = 200;
  late VenueFilters _f;
  late TextEditingController _query;

  @override
  void initState() {
    super.initState();
    _f = widget.initial;
    _query = TextEditingController(text: _f.query);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(text, style: TextStyle(color: AppColors.text70, fontWeight: FontWeight.w600, fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    final sortLabels = {
      VenueSort.recommended: tr('vf.sort_recommended'),
      VenueSort.distance: tr('vf.sort_distance'),
      VenueSort.price: tr('vf.sort_price'),
      VenueSort.rating: tr('vf.sort_rating'),
    };
    final priceValue = _f.maxPrice ?? _maxSlider;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(tr('vf.filters'), style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold))),
                  TextButton(
                    onPressed: () => setState(() {
                      _f = VenueFilters();
                      _query.clear();
                    }),
                    child: Text(tr('vf.reset'), style: TextStyle(color: AppColors.muted)),
                  ),
                ],
              ),
              TextField(
                controller: _query,
                style: TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  hintText: tr('vf.search_hint'),
                  prefixIcon: Icon(Icons.search, color: AppColors.accent),
                  isDense: true,
                ),
                onChanged: (v) => _f.query = v,
              ),
              _label(tr('vf.sort')),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in VenueSort.values)
                    ChoiceChip(
                      label: Text(sortLabels[s]!),
                      selected: _f.sort == s,
                      onSelected: (_) => setState(() => _f.sort = s),
                    ),
                ],
              ),
              _label(tr('vf.max_price')),
              Text(
                _f.maxPrice == null ? tr('vf.max_price_any') : tr('vf.max_price_val', {'n': _f.maxPrice!.toStringAsFixed(0)}),
                style: TextStyle(color: AppColors.accent, fontSize: 13),
              ),
              Slider(
                value: priceValue.clamp(10, _maxSlider).toDouble(),
                min: 10,
                max: _maxSlider,
                divisions: 19,
                onChanged: (v) => setState(() => _f.maxPrice = v >= _maxSlider ? null : v.roundToDouble()),
              ),
              _label(tr('vf.min_rating')),
              Wrap(
                spacing: 8,
                children: [
                  for (final r in const <double?>[null, 3.0, 4.0, 4.5])
                    ChoiceChip(
                      label: Text(r == null ? tr('vf.rating_any') : '${r.toString()}+'),
                      selected: _f.minRating == r,
                      onSelected: (_) => setState(() => _f.minRating = r),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('vf.open_now'), style: TextStyle(color: AppColors.text, fontSize: 14)),
                value: _f.openNow,
                onChanged: (v) => setState(() => _f.openNow = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('vf.with_extras'), style: TextStyle(color: AppColors.text, fontSize: 14)),
                value: _f.withExtras,
                onChanged: (v) => setState(() => _f.withExtras = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _f),
                  child: Text(tr('vf.apply')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
