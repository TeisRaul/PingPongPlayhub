import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CitySelectorField extends StatelessWidget {
  final String? selectedCity;
  final List<String> cityOptions;
  final String labelText;
  final ValueChanged<String> onCitySelected;
  final String? Function(String?)? validator;

  const CitySelectorField({
    super.key,
    required this.selectedCity,
    required this.cityOptions,
    required this.onCitySelected,
    this.labelText = 'Oraș',
    this.validator,
  });

  void _showSearchBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _CitySearchBottomSheet(
          cityOptions: cityOptions,
          onCitySelected: onCitySelected,
          initialSelection: selectedCity,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      controller: TextEditingController(text: selectedCity ?? ''),
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(Icons.location_city, color: AppColors.accent),
        suffixIcon: Icon(Icons.keyboard_arrow_down, color: AppColors.muted),
      ),
      validator: validator,
      onTap: () => _showSearchBottomSheet(context),
    );
  }
}

class _CitySearchBottomSheet extends StatefulWidget {
  final List<String> cityOptions;
  final ValueChanged<String> onCitySelected;
  final String? initialSelection;

  const _CitySearchBottomSheet({
    required this.cityOptions,
    required this.onCitySelected,
    this.initialSelection,
  });

  @override
  State<_CitySearchBottomSheet> createState() => _CitySearchBottomSheetState();
}

class _CitySearchBottomSheetState extends State<_CitySearchBottomSheet> {
  late List<String> _filteredCities;

  @override
  void initState() {
    super.initState();
    _filteredCities = List.from(widget.cityOptions);
  }

  void _filterCities(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCities = List.from(widget.cityOptions);
      } else {
        _filteredCities = widget.cityOptions
            .where((city) => city.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mâner de glisare
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border700,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Alege Orașul',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 16),
            // Câmp de căutare
            TextField(
              autofocus: true,
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Caută orașul...',
                hintStyle: TextStyle(color: AppColors.muted),
                prefixIcon: Icon(Icons.search, color: AppColors.accent),
                filled: true,
                fillColor: AppColors.card2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: _filterCities,
            ),
            const SizedBox(height: 12),
            // Listă orașe
            Expanded(
              child: _filteredCities.isEmpty
                  ? Center(
                      child: Text(
                        'Niciun oraș găsit',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredCities.length,
                      itemBuilder: (context, index) {
                        final city = _filteredCities[index];
                        final isSelected = widget.initialSelection == city;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accent.withValues(alpha: 0.12)
                                : AppColors.card2.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.accent.withValues(alpha: 0.5)
                                  : Colors.transparent,
                            ),
                          ),
                          child: ListTile(
                            title: Text(
                              city,
                              style: TextStyle(
                                color: isSelected ? AppColors.accent : AppColors.text,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check, color: AppColors.accent)
                                : null,
                            onTap: () {
                              widget.onCitySelected(city);
                              Navigator.pop(context);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
