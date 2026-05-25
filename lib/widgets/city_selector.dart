import 'package:flutter/material.dart';

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
      backgroundColor: const Color(0xFF131A2A),
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
        prefixIcon: const Icon(Icons.location_city, color: Color(0xFF00E5FF)),
        suffixIcon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
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
                  color: Colors.grey.shade700,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Alege Orașul',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            // Câmp de căutare
            TextField(
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Caută orașul...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00E5FF)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
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
                  ? const Center(
                      child: Text(
                        'Niciun oraș găsit',
                        style: TextStyle(color: Colors.grey),
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
                                ? const Color(0xFF00E5FF).withValues(alpha: 0.12)
                                : const Color(0xFF1E293B).withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                                  : Colors.transparent,
                            ),
                          ),
                          child: ListTile(
                            title: Text(
                              city,
                              style: TextStyle(
                                color: isSelected ? const Color(0xFF00E5FF) : Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check, color: Color(0xFF00E5FF))
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
