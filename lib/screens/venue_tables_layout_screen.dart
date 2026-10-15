import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/player_drawer.dart';
import '../utils/level_utils.dart';
import '../theme/app_theme.dart';


class VenueTablesLayoutScreen extends StatefulWidget {
  final String venueId;
  final String venueName;
  final bool isAdmin;
  final bool showBackButton;

  const VenueTablesLayoutScreen({
    super.key,
    required this.venueId,
    required this.venueName,
    required this.isAdmin,
    this.showBackButton = true,
  });

  @override
  State<VenueTablesLayoutScreen> createState() => _VenueTablesLayoutScreenState();
}

class _VenueTablesLayoutScreenState extends State<VenueTablesLayoutScreen> {
  bool _isEditing = false;
  bool _loading = true;
  bool _saving = false;

  // Visual grid size: 5 rows x 5 columns
  final int _gridRows = 5;
  final int _gridCols = 5;

  List<String> _supportedSports = ['ping_pong'];
  String _selectedSport = 'ping_pong';
  String _selectedEnvironment = 'indoor'; // 'indoor' or 'outdoor'
  Map<String, List<Map<String, dynamic>>> _layouts = {};

  List<Map<String, dynamic>> get _customTables => _layouts[_selectedSport] ?? [];

  Map<String, dynamic> _trainingConfig = {
    'enabled': false,
    'startHour': 17,
    'endHour': 19,
    'weekdays': [1, 2, 3, 4, 5], // Luni - Vineri
  };
  Map<String, dynamic>? _venueData;

  DateTime _selectedDate = DateTime.now();
  int _selectedHour = DateTime.now().hour;
  List<Map<String, dynamic>> _matchesToday = [];

  // Moving table temporary state
  Map<String, dynamic>? _movingTable;

  @override
  void initState() {
    super.initState();
    _loadVenuePlan();
  }

  Future<void> _loadVenuePlan() async {
    setState(() => _loading = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        _venueData = data;
        
        _supportedSports = List<String>.from(data['supportedSports'] ?? ['ping_pong']);
        if (_supportedSports.isEmpty) _supportedSports = ['ping_pong'];
        _selectedSport = _supportedSports.first;

        if (data.containsKey('layouts')) {
          final l = data['layouts'] as Map<String, dynamic>;
          _layouts = {};
          l.forEach((k, v) {
            _layouts[k] = List<Map<String, dynamic>>.from(v as List);
          });
        } else {
          // Fallback to customTables or resource counts
          _layouts = {};
          if (data.containsKey('customTables')) {
            _layouts['ping_pong'] = List<Map<String, dynamic>>.from(data['customTables'] ?? []);
          } else {
            Map<String, dynamic> rps = data['resourcesPerSport'] ?? {};
            for (String s in _supportedSports) {
              int indoor = rps[s]?['indoor'] ?? 4;
              int outdoor = rps[s]?['outdoor'] ?? 0;
              _initializeDefaultTables(indoor, outdoor, s);
            }
          }
        }

        if (data.containsKey('trainingConfig')) {
          _trainingConfig = Map<String, dynamic>.from(data['trainingConfig'] ?? {});
        }
      } else {
        // Fallback for new venues
        _supportedSports = ['ping_pong'];
        _selectedSport = 'ping_pong';
        _layouts = {};
        _initializeDefaultTables(4, 0, 'ping_pong');
      }

      await _loadBookings();
    } catch (e) {
      debugPrint('Eroare la incarcarea planului: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _initializeDefaultTables(int indoor, int outdoor, [String? sport]) {
    final s = sport ?? _selectedSport;
    final list = <Map<String, dynamic>>[];
    int logicalId = 1;
    // Lay out indoor tables
    for (int i = 0; i < indoor; i++) {
      int row = i ~/ 4;
      int col = i % 4;
      list.add({
        'tableId': logicalId++,
        'name': 'Teren/Masă ${i + 1}',
        'type': 'indoor',
        'x': col,
        'y': row,
      });
    }
    // Lay out outdoor tables (on their own grid)
    for (int i = 0; i < outdoor; i++) {
      int row = i ~/ 4;
      int col = i % 4;
      list.add({
        'tableId': logicalId++,
        'name': 'Teren/Masă ${i + 1} Out',
        'type': 'outdoor',
        'x': col,
        'y': row,
      });
    }
    _layouts[s] = list;
  }

  Future<void> _loadBookings() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('matches')
          .where('locationId', isEqualTo: widget.venueId)
          .where('date', isEqualTo: dateStr)
          .get();

      _matchesToday = snap.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Eroare incarcare rezervari: $e');
    }
  }

  Future<void> _saveVenuePlan() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('venues').doc(widget.venueId).update({
        'layouts': _layouts,
        'trainingConfig': _trainingConfig,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Planul sălii a fost salvat cu succes!'), backgroundColor: Colors.green),
        );
        setState(() => _isEditing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la salvare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic>? _getTableAt(int x, int y) {
    for (var table in _customTables) {
      if (table['x'] == x && table['y'] == y) {
        // 'training' tables are usually indoor.
        bool isIndoorType = table['type'] == 'indoor' || table['type'] == 'training';
        bool isOutdoorType = table['type'] == 'outdoor';
        
        if (_selectedEnvironment == 'indoor' && isIndoorType) return table;
        if (_selectedEnvironment == 'outdoor' && isOutdoorType) return table;
      }
    }
    return null;
  }

  bool _isTableOccupied(int tableId, int hour) {
    for (var match in _matchesToday) {
      final String matchSport = match['sport'] ?? 'ping_pong';
      if (matchSport != _selectedSport) continue;

      final int start = match['startHour'] ?? 0;
      final int end = match['endHour'] ?? 0;
      final int tId = match['tableId'] ?? -1;
      final String status = match['status'] ?? 'open';
      if (tId == tableId && status != 'cancelled' && hour >= start && hour < end) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic>? _getBookingForTable(int tableId, int hour) {
    for (var match in _matchesToday) {
      final String matchSport = match['sport'] ?? 'ping_pong';
      if (matchSport != _selectedSport) continue;

      final int start = match['startHour'] ?? 0;
      final int end = match['endHour'] ?? 0;
      final int tId = match['tableId'] ?? -1;
      final String status = match['status'] ?? 'open';
      if (tId == tableId && status != 'cancelled' && hour >= start && hour < end) {
        return match;
      }
    }
    return null;
  }

  bool _isTrainingHour(int hour) {
    if (_trainingConfig['enabled'] == false) return false;
    final int weekday = _selectedDate.weekday; // 1 = Monday, 7 = Sunday
    final List<dynamic> days = _trainingConfig['weekdays'] ?? [];
    if (!days.contains(weekday)) return false;

    final int start = _trainingConfig['startHour'] ?? 17;
    final int end = _trainingConfig['endHour'] ?? 19;
    return hour >= start && hour < end;
  }

  void _showAddTableDialog(int x, int y) {
    final String entityName = _selectedSport == 'ping_pong' ? 'Masa' : 'Teren';
    final String entityNameDiacritics = _selectedSport == 'ping_pong' ? 'Masă' : 'Teren';
    final String entityNameNew = _selectedSport == 'ping_pong' ? 'Masă Nouă' : 'Teren Nou';
    
    final nameController = TextEditingController(text: '$entityName ${_customTables.length + 1}');
    String tableType = 'indoor';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.card,
            title: Text('Adaugă $entityNameNew', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    labelText: 'Denumire / Număr $entityNameDiacritics',
                    labelStyle: TextStyle(color: AppColors.text54),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: tableType,
                  dropdownColor: AppColors.card,
                  style: TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    labelText: 'Tip $entityNameDiacritics',
                    labelStyle: TextStyle(color: AppColors.text54),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'indoor', child: Text('Indoor')),
                    DropdownMenuItem(value: 'outdoor', child: Text('Outdoor')),
                    DropdownMenuItem(value: 'training', child: Text('Antrenament Copii')),
                  ],
                  onChanged: (val) => setDialogState(() => tableType = val ?? 'indoor'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Anulează', style: TextStyle(color: AppColors.text54)),
              ),
              ElevatedButton(
                onPressed: () {
                  // Find next unique logical ID
                  int nextId = 1;
                  if (_customTables.isNotEmpty) {
                    nextId = _customTables.map((t) => t['tableId'] as int).reduce((a, b) => a > b ? a : b) + 1;
                  }

                  setState(() {
                    _customTables.add({
                      'tableId': nextId,
                      'name': nameController.text.trim(),
                      'type': tableType,
                      'x': x,
                      'y': y,
                    });
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                child: const Text('Adaugă'),
              )
            ],
          );
        });
      },
    );
  }

  void _showEditTableDialog(Map<String, dynamic> table) {
    final String entityNameDiacritics = _selectedSport == 'ping_pong' ? 'Masă' : 'Teren';
    final String entityNameLowercase = _selectedSport == 'ping_pong' ? 'masa' : 'terenul';
    
    final nameController = TextEditingController(text: table['name']);
    String tableType = table['type'] ?? 'indoor';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.card,
            title: Text('Editează ${table['name']}', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    labelText: 'Denumire $entityNameDiacritics',
                    labelStyle: TextStyle(color: AppColors.text54),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: tableType,
                  dropdownColor: AppColors.card,
                  style: TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    labelText: 'Tip $entityNameDiacritics',
                    labelStyle: TextStyle(color: AppColors.text54),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'indoor', child: Text('Indoor')),
                    DropdownMenuItem(value: 'outdoor', child: Text('Outdoor')),
                    DropdownMenuItem(value: 'training', child: Text('Antrenament Copii')),
                  ],
                  onChanged: (val) => setDialogState(() => tableType = val ?? 'indoor'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // Șterge masa
                  setState(() {
                    _customTables.removeWhere((t) => t['tableId'] == table['tableId']);
                  });
                  Navigator.pop(context);
                },
                child: const Text('Șterge', style: TextStyle(color: Colors.redAccent)),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  // Mută masa (inițiază modul mutare)
                  setState(() {
                    _movingTable = table;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Atinge o căsuță liberă din cameră pentru a muta ${table['name']}.'),
                      backgroundColor: AppColors.accent,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                },
                child: Text('Mută $entityNameLowercase', style: TextStyle(color: AppColors.accent)),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    table['name'] = nameController.text.trim();
                    table['type'] = tableType;
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                child: const Text('Salvează'),
              )
            ],
          );
        });
      },
    );
  }

  void _showTrainingConfigDialog() {
    bool enabled = _trainingConfig['enabled'] ?? false;
    int start = _trainingConfig['startHour'] ?? 17;
    int end = _trainingConfig['endHour'] ?? 19;
    List<int> weekdays = List<int>.from(_trainingConfig['weekdays'] ?? [1, 2, 3, 4, 5]);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.card,
            title: Text('Configurare Antrenamente Copii', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mesele de tip „Antrenament Copii” vor fi marcate automat ca rezervate/ocupate în intervalele declarate aici.',
                    style: TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text('Activează Automat', style: TextStyle(color: AppColors.text, fontSize: 14)),
                    subtitle: Text('Rezervă mesele în timpul orelor de antrenament', style: TextStyle(color: AppColors.text54, fontSize: 11)),
                    value: enabled,
                    activeThumbColor: AppColors.accent,
                    onChanged: (val) => setDialogState(() => enabled = val),
                  ),
                  Divider(color: AppColors.text24),
                  const SizedBox(height: 8),
                  Text('Interval orar antrenament:', style: TextStyle(color: AppColors.text70, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: start,
                          dropdownColor: AppColors.card,
                          style: TextStyle(color: AppColors.text),
                          decoration: const InputDecoration(labelText: 'De la ora'),
                          items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text('$i:00'))),
                          onChanged: (val) => setDialogState(() => start = val ?? 17),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: end,
                          dropdownColor: AppColors.card,
                          style: TextStyle(color: AppColors.text),
                          decoration: const InputDecoration(labelText: 'Până la ora'),
                          items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text('$i:00'))),
                          onChanged: (val) => setDialogState(() => end = val ?? 19),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Zilele săptămânii cu antrenament:', style: TextStyle(color: AppColors.text70, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      {'id': 1, 'name': 'Lu'},
                      {'id': 2, 'name': 'Ma'},
                      {'id': 3, 'name': 'Mi'},
                      {'id': 4, 'name': 'Jo'},
                      {'id': 5, 'name': 'Vi'},
                      {'id': 6, 'name': 'Sâ'},
                      {'id': 7, 'name': 'Du'},
                    ].map((day) {
                      final int dayId = day['id'] as int;
                      final isSelected = weekdays.contains(dayId);
                      return FilterChip(
                        label: Text(day['name'] as String),
                        selected: isSelected,
                        selectedColor: AppColors.accent,
                        labelStyle: TextStyle(color: isSelected ? AppColors.onAccent : AppColors.text, fontSize: 11),
                        onSelected: (selected) {
                          setDialogState(() {
                            if (selected) {
                              weekdays.add(dayId);
                            } else {
                              weekdays.remove(dayId);
                            }
                          });
                        },
                      );
                    }).toList(),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Anulează', style: TextStyle(color: AppColors.text54)),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _trainingConfig = {
                      'enabled': enabled,
                      'startHour': start,
                      'endHour': end,
                      'weekdays': weekdays,
                    };
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                child: const Text('Salvează'),
              )
            ],
          );
        });
      },
    );
  }

  void _showBookingDetailsDialog(Map<String, dynamic> booking, String tableName) {
    final String host = booking['hostUsername'] ?? 'Jucător';
    final String date = booking['date'] ?? '';
    final int start = booking['startHour'] ?? 0;
    final int end = booking['endHour'] ?? 0;
    final List<dynamic> joined = booking['joinedPlayers'] ?? [];
    final bool isPrivate = (booking['visibility'] ?? 'public').toString().toLowerCase() == 'private';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(
            'Detalii Ocupare - $tableName',
            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rezervat de: $host', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              Text('Data: $date', style: TextStyle(color: AppColors.text70, fontSize: 13)),
              Text('Interval: $start:00 - $end:00', style: TextStyle(color: AppColors.text70, fontSize: 13)),
              Text('Tip Meci: ${isPrivate ? "Privat" : "Public"}', style: TextStyle(color: AppColors.text70, fontSize: 13)),
              const SizedBox(height: 12),
              Text('Jucători înscriși (${joined.length}):', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              ...joined.map((p) {
                final pData = p as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    children: [
                      Icon(Icons.person, color: AppColors.text38, size: 14),
                      const SizedBox(width: 6),
                      Text(pData['username'] ?? 'Player', style: TextStyle(color: AppColors.text70, fontSize: 12)),
                    ],
                  ),
                );
              }),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
              child: const Text('Închide'),
            )
          ],
        );
      },
    );
  }

  void _showOfflineBookingDialog(Map<String, dynamic> table) {
    final nameController = TextEditingController();
    
    final bool allowHalfHour = _venueData?['allowHalfHour'] ?? false;
    final double step = allowHalfHour ? 0.5 : 1.0;
    
    num startHour = _selectedHour.toDouble();
    num endHour = _selectedHour + 1.0;
    String paymentStatus = 'pending'; // Default is pending (unpaid) as requested!

    final int open = 0;
    final int close = 24;

    List<num> dropdownHours = [];
    for (double h = open.toDouble(); h <= close.toDouble(); h += step) {
      dropdownHours.add(h);
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.accent, width: 1.5),
            ),
            title: Row(
              children: [
                Icon(Icons.phone_in_talk, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rezervare Rapidă - ${table['name']}',
                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Adaugă o programare rapidă primită prin apel telefonic sau direct la sală.',
                    style: TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: AppColors.text, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Nume Client / Detalii Telefon',
                      labelStyle: TextStyle(color: AppColors.text54, fontSize: 12),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.text24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<num>(
                          initialValue: startHour,
                          dropdownColor: AppColors.card,
                          style: TextStyle(color: AppColors.text, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'De la ora',
                            labelStyle: TextStyle(color: AppColors.text54, fontSize: 11),
                          ),
                          items: dropdownHours.where((h) => h < close).map((h) {
                            return DropdownMenuItem(value: h, child: Text(_formatHour(h)));
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              startHour = val ?? startHour;
                              if (endHour <= startHour) {
                                endHour = startHour + step;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<num>(
                          initialValue: endHour,
                          dropdownColor: AppColors.card,
                          style: TextStyle(color: AppColors.text, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Până la ora',
                            labelStyle: TextStyle(color: AppColors.text54, fontSize: 11),
                          ),
                          items: dropdownHours.where((h) => h > startHour).map((h) {
                            return DropdownMenuItem(value: h, child: Text(_formatHour(h)));
                          }).toList(),
                          onChanged: (val) => setDialogState(() => endHour = val ?? endHour),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: paymentStatus,
                    dropdownColor: AppColors.card,
                    style: TextStyle(color: AppColors.text, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Status Plată',
                      labelStyle: TextStyle(color: AppColors.text54, fontSize: 11),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'pending', child: Text('Neplătit (În așteptare)')),
                      DropdownMenuItem(value: 'confirmed', child: Text('Plătit (Cash / Offline)')),
                    ],
                    onChanged: (val) => setDialogState(() => paymentStatus = val ?? paymentStatus),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Anulează', style: TextStyle(color: AppColors.text54)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final String name = nameController.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Te rugăm să introduci numele clientului.'), backgroundColor: Colors.redAccent),
                    );
                    return;
                  }

                  Navigator.pop(context);
                  setState(() => _loading = true);

                  try {
                    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

                    // Preluăm orașul sălii pentru consistentă în meci
                    final venueDoc = await FirebaseFirestore.instance
                        .collection('venues')
                        .doc(widget.venueId)
                        .get();
                    final venueData = venueDoc.data() ?? {};
                    final String city = venueData['city'] ?? 'Oradea';

                    // Calculăm prețul slot-by-slot folosind noile setări structurate ale sălii
                    final double totalPrice = LevelUtils.calculateVenueBookingPrice(
                      venueData: venueData,
                      startHour: startHour,
                      endHour: endHour,
                      date: _selectedDate,
                    );

                    final Map<String, dynamic> offlineHost = {
                      'uid': 'offline_${DateTime.now().millisecondsSinceEpoch}',
                      'username': name,
                      'avatarUrl': null,
                      'rating': 1000,
                      'level': '',
                      'role': 'host'
                    };

                    await FirebaseFirestore.instance.collection('matches').add({
                      'hostUid': widget.venueId,
                      'hostUsername': name,
                      'hostAvatarUrl': null,
                      'hostRating': 1000,
                      'hostLevel': '',
                      'joinedPlayers': [offlineHost],
                      'joinedUids': [offlineHost['uid']],
                      'maxPlayers': 2,
                      'visibility': 'private',
                      'isFriendly': true,
                      'city': city,
                      'sport': _selectedSport,
                      'locationId': widget.venueId,
                      'locationName': widget.venueName,
                      'date': dateStr,
                      'startHour': startHour,
                      'endHour': endHour,
                      'tableId': table['tableId'],
                      'tableType': table['type'] ?? 'indoor',
                      'paymentMethod': 'Cash la locație',
                      'paymentSplit': 'Achitat integral',
                      'paymentStatus': paymentStatus,
                      'status': 'open',
                      'price': totalPrice,
                      'createdAt': FieldValue.serverTimestamp(),
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Rezervare adăugată cu succes pentru $name!'), backgroundColor: Colors.green),
                    );

                    await _loadBookings();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Eroare la adăugarea rezervării: $e'), backgroundColor: Colors.redAccent),
                    );
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                child: const Text('Creează'),
              )
            ],
          );
        });
      },
    );
  }

  String _formatHour(num hour) {
    final int h = hour.toInt();
    final int m = ((hour - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmBookingPayment(String matchId) async {
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.collection('matches').doc(matchId).update({
        'paymentStatus': 'confirmed',
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plata a fost confirmată cu succes!'), backgroundColor: Colors.green),
      );
      await _loadBookings();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la confirmarea plății: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelBooking(String matchId, Map<String, dynamic> matchData) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Anulează Rezervarea', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        content: Text('Ești sigur că vrei să anulezi această rezervare?', style: TextStyle(color: AppColors.text70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Nu', style: TextStyle(color: AppColors.text54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Da, Anulează'),
          )
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final String paymentMethod = matchData['paymentMethod'] ?? '';
      final String paymentStatus = matchData['paymentStatus'] ?? '';
      final double price = (matchData['price'] as num?)?.toDouble() ?? 0.0;
      
      Map<String, dynamic> updates = {
        'status': 'cancelled',
      };

      if (paymentMethod.contains('Card') && paymentStatus == 'confirmed') {
        updates['paymentStatus'] = 'refunded';
        updates['refundedAmount'] = price;
      }

      await FirebaseFirestore.instance.collection('matches').doc(matchId).update(updates);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rezervarea a fost anulată.'), backgroundColor: Colors.orange),
      );
      await _loadBookings();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la anularea rezervării: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: AppColors.bg,
      drawer: widget.isAdmin && !widget.showBackButton
          ? const PlayerDrawer(activePage: 'tables_layout')
          : null,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        leading: widget.showBackButton
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.accent),
                onPressed: () => Navigator.pop(context),
              )
            : Builder(
                builder: (context) => IconButton(
                  icon: Icon(Icons.menu, color: AppColors.accent),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        title: Text(
          widget.venueName,
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          if (widget.isAdmin && !_isEditing)
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: Icon(Icons.edit, color: AppColors.accent, size: 18),
              label: Text('Aranjează', style: TextStyle(color: AppColors.accent)),
            )
          else if (widget.isAdmin && _isEditing) ...[
            TextButton(
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _movingTable = null;
                });
                _loadVenuePlan(); // Reload saved
              },
              child: Text('Anulează', style: TextStyle(color: AppColors.text54)),
            ),
            TextButton(
              onPressed: _saveVenuePlan,
              child: _saving
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                  : Text('Salvează', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
            ),
          ]
        ],
        bottom: !_isEditing
            ? TabBar(
                indicatorColor: AppColors.accent,
                labelColor: AppColors.accent,
                unselectedLabelColor: AppColors.text54,
                tabs: [
                  Tab(icon: Icon(Icons.calendar_today), text: 'Programări Astăzi'),
                  Tab(icon: Icon(Icons.room), text: 'Plan Cameră & Mese'),
                ],
              )
            : null,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(
              children: [
                _buildSportSelector(),
                Expanded(
                  child: _isEditing
                      ? _buildEditPlanView()
                      : TabBarView(
                          children: [
                            _buildBookingsTab(),
                            _buildRoomLayoutTab(),
                          ],
                        ),
                ),
              ],
            ),
    );

    return _isEditing
        ? scaffold
        : DefaultTabController(
            length: 2,
            child: scaffold,
          );
  }

  Widget _buildSportSelector() {
    if (_supportedSports.length <= 1) return const SizedBox.shrink();

    final Map<String, String> names = {
      'ping_pong': 'Ping Pong',
      'padel': 'Padel',
      'tenis': 'Tenis',
      'fotbal': 'Fotbal',
      'handbal': 'Handbal',
      'baschet': 'Baschet',
    };

    return Container(
      width: double.infinity,
      color: AppColors.card,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: _supportedSports.map((s) {
            final isSelected = s == _selectedSport;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(names[s] ?? s, style: TextStyle(color: isSelected ? AppColors.onAccent : AppColors.text)),
                selected: isSelected,
                selectedColor: AppColors.accent,
                backgroundColor: AppColors.card2,
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _selectedSport = s;
                      _movingTable = null; // reset move mode
                    });
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBookingsTab() {
    final activeBookings = _matchesToday.where((m) {
      final String matchSport = m['sport'] ?? 'ping_pong';
      return m['status'] != 'cancelled' && matchSport == _selectedSport;
    }).toList();
    // Sort by start hour
    activeBookings.sort((a, b) => (a['startHour'] as num).compareTo(b['startHour'] as num));

    if (activeBookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, color: AppColors.text24, size: 64),
            const SizedBox(height: 16),
            Text(
              'Nu există programări active pentru astăzi',
              style: TextStyle(color: AppColors.text54, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: activeBookings.length,
      itemBuilder: (context, index) {
        final booking = activeBookings[index];
        final String matchId = booking['docId'] ?? '';
        final String clientName = booking['hostUsername'] ?? 'Client';
        final num start = booking['startHour'] ?? 0;
        final num end = booking['endHour'] ?? 0;
        final int tableId = booking['tableId'] ?? -1;
        final String paymentStatus = booking['paymentStatus'] ?? 'pending';
        final double price = (booking['price'] as num?)?.toDouble() ?? 0.0;
        final String hostLevel = booking['hostLevel'] ?? '';

        final bool isOffline = (booking['hostUid'] ?? '').toString().startsWith('offline_') ||
            booking['hostUid'] == widget.venueId ||
            hostLevel == '' ||
            hostLevel == '-';
            
        final String? hostAvatar = booking['hostAvatarUrl'];

        // Find table name
        String tableName = '${_selectedSport == 'ping_pong' ? 'Masa' : 'Teren'} $tableId';
        for (var t in _customTables) {
          if (t['tableId'] == tableId) {
            tableName = t['name'] ?? tableName;
            break;
          }
        }

        final bool isPaid = paymentStatus == 'confirmed';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPaid ? Colors.greenAccent.withValues(alpha: 0.3) : AppColors.bad.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.card2,
                      backgroundImage: (hostAvatar != null && hostAvatar.isNotEmpty) ? NetworkImage(hostAvatar) : null,
                      child: (hostAvatar == null || hostAvatar.isEmpty) ? Icon(Icons.person, color: AppColors.muted, size: 20) : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clientName,
                            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.bg,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.text12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.table_restaurant, color: AppColors.accent, size: 10),
                                    const SizedBox(width: 4),
                                    Text(
                                      tableName,
                                      style: TextStyle(color: AppColors.text70, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.bg,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.text12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.access_time, color: AppColors.accent, size: 10),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_formatHour(start)} - ${_formatHour(end)}',
                                      style: TextStyle(color: AppColors.text70, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (price > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.gold, width: 1),
                        ),
                        child: Text(
                          '${price.toStringAsFixed(0)} RON',
                          style: TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                if (!isOffline && hostLevel.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.emoji_events, color: AppColors.gold, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'Nivel: $hostLevel',
                        style: TextStyle(color: AppColors.text70, fontSize: 10),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isPaid ? Icons.check_circle : Icons.error_outline,
                      color: isPaid ? AppColors.good : AppColors.bad,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isPaid ? 'Plată Confirmată' : 'Plată Neconfirmată',
                      style: TextStyle(
                        color: isPaid ? AppColors.good : AppColors.bad,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (widget.isAdmin) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _cancelBooking(matchId, booking),
                        icon: const Icon(Icons.cancel, size: 12),
                        label: const Text('Anulează', style: TextStyle(fontSize: 10)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.bad,
                          side: BorderSide(color: AppColors.bad),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                        ),
                      ),
                      if (!isPaid) ...[
                        const SizedBox(width: 6),
                        ElevatedButton.icon(
                          onPressed: () => _confirmBookingPayment(matchId),
                          icon: const Icon(Icons.payments, size: 12),
                          label: const Text('Confirmă', style: TextStyle(fontSize: 10)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.good,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            textStyle: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoomLayoutTab() {
    return Column(
      children: [
        // Plan View Header / Selectors
        Container(
          color: AppColors.card,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month, color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  Text('Data:', style: TextStyle(color: AppColors.muted, fontSize: 14)),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () async {
                      final res = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (res != null) {
                        setState(() => _selectedDate = res);
                        await _loadBookings();
                        setState(() {});
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        DateFormat('dd MMM yyyy').format(_selectedDate),
                        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.access_time, color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  Text('Interval orar:', style: TextStyle(color: AppColors.muted, fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _selectedHour,
                      dropdownColor: AppColors.card,
                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 10),
                        border: InputBorder.none,
                      ),
                      items: List.generate(24, (i) {
                        return DropdownMenuItem(
                          value: i,
                          child: Text('$i:00 - ${i + 1}:00'),
                        );
                      }),
                      onChanged: (val) => setState(() => _selectedHour = val ?? 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Grid Legends
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendItem('Liberă', AppColors.good),
              _buildBadgeLegend('Ocupată', AppColors.bad),
              _buildLegendItem('Antrenament', Colors.purpleAccent),
            ],
          ),
        ),

        // 2D ROOM LAYOUT VIEW
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.card2, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.05),
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PLAN CAMERĂ CLUB',
                      style: TextStyle(color: AppColors.text38, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 2),
                    ),
                    const SizedBox(height: 12),
                    // Environment Toggle
                    ToggleButtons(
                      isSelected: [_selectedEnvironment == 'indoor', _selectedEnvironment == 'outdoor'],
                      onPressed: (index) {
                        setState(() {
                          _selectedEnvironment = index == 0 ? 'indoor' : 'outdoor';
                        });
                      },
                      color: AppColors.text54,
                      selectedColor: Colors.black,
                      fillColor: AppColors.accent,
                      borderColor: AppColors.card2,
                      selectedBorderColor: AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Indoor', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Outdoor', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // The 2D Grid
                    Table(
                      defaultColumnWidth: const FixedColumnWidth(70),
                      children: List.generate(_gridRows, (y) {
                        return TableRow(
                          children: List.generate(_gridCols, (x) {
                            final table = _getTableAt(x, y);
                            return _buildGridCell(x, y, table);
                          }),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditPlanView() {
    return Column(
      children: [
        // Edit Header
        Container(
          width: double.infinity,
          color: AppColors.card,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MOD EDITARE SALĂ / CAMERĂ',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2),
              ),
              const SizedBox(height: 4),
              Text(
                '• Atinge un spațiu liber pentru a adăuga un element.\n• Atinge un element pentru a-l edita, șterge sau a-i schimba poziția.',
                style: TextStyle(color: AppColors.text54, fontSize: 11),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showTrainingConfigDialog,
                  icon: const Icon(Icons.settings_suggest, size: 16),
                  label: const Text('Configurare Antrenamente Copii', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purpleAccent.withValues(alpha: 0.1),
                    foregroundColor: Colors.purpleAccent,
                    side: const BorderSide(color: Colors.purpleAccent),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              )
            ],
          ),
        ),

        const SizedBox(height: 12),
        // Environment Toggle for Edit Mode
        ToggleButtons(
          isSelected: [_selectedEnvironment == 'indoor', _selectedEnvironment == 'outdoor'],
          onPressed: (index) {
            setState(() {
              _selectedEnvironment = index == 0 ? 'indoor' : 'outdoor';
            });
          },
          color: AppColors.text54,
          selectedColor: Colors.black,
          fillColor: AppColors.accent,
          borderColor: AppColors.card2,
          selectedBorderColor: AppColors.accent,
          borderRadius: BorderRadius.circular(8),
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Indoor', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Outdoor', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),

        // 2D ROOM LAYOUT VIEW IN EDIT MODE
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.card2, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.05),
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PLAN CAMERĂ CLUB (EDITARE)',
                      style: TextStyle(color: AppColors.text38, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 2),
                    ),
                    const SizedBox(height: 12),
                    // The 2D Grid
                    Table(
                      defaultColumnWidth: const FixedColumnWidth(70),
                      children: List.generate(_gridRows, (y) {
                        return TableRow(
                          children: List.generate(_gridCols, (x) {
                            final table = _getTableAt(x, y);
                            return _buildGridCell(x, y, table);
                          }),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridCell(int x, int y, Map<String, dynamic>? table) {
    if (_isEditing) {
      if (table != null) {
        // Table cell in edit mode
        final bool isMoving = _movingTable != null && _movingTable!['tableId'] == table['tableId'];
        IconData icon = Icons.table_restaurant;
        if (table['type'] == 'outdoor') {
          icon = Icons.wb_sunny;
        } else if (table['type'] == 'training') {
          icon = Icons.school;
        }

        return GestureDetector(
          onTap: () => _showEditTableDialog(table),
          child: Container(
            height: 50,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isMoving ? Colors.orange.withValues(alpha: 0.2) : AppColors.card2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isMoving ? Colors.orangeAccent : AppColors.accent.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.accent, size: 14),
                const SizedBox(height: 2),
                Text(
                  table['name'] ?? '',
                  style: TextStyle(color: AppColors.text, fontSize: 8, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      } else {
        // Empty cell in edit mode
        final bool isMovingTarget = _movingTable != null;
        return GestureDetector(
          onTap: () {
            if (_movingTable != null) {
              setState(() {
                _movingTable!['x'] = x;
                _movingTable!['y'] = y;
                _movingTable = null;
              });
            } else {
              _showAddTableDialog(x, y);
            }
          },
          child: Container(
            height: 50,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isMovingTarget ? Colors.green.withValues(alpha: 0.2) : AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isMovingTarget ? Colors.greenAccent : AppColors.text12,
                style: BorderStyle.solid,
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(Icons.add, color: AppColors.text24, size: 16),
            ),
          ),
        );
      }
    } else {
      // VIEW MODE (Non-edit mode)
      if (table != null) {
        final int tableId = table['tableId'] as int;
        final bool isOccupied = _isTableOccupied(tableId, _selectedHour);
        final bool isTraining = table['type'] == 'training' && _isTrainingHour(_selectedHour);
        
        Color statusColor = AppColors.good; // Free (Green)
        String statusText = 'LIBER';
        if (isOccupied) {
          statusColor = AppColors.bad; // Occupied (Red)
          statusText = 'OCUPAT';
        } else if (isTraining) {
          statusColor = Colors.purpleAccent; // Kids Training (Purple)
          statusText = 'COPII';
        }

        IconData icon = Icons.table_restaurant;
        if (table['type'] == 'outdoor') {
          icon = Icons.wb_sunny;
        } else if (table['type'] == 'training') {
          icon = Icons.school;
        }

        return GestureDetector(
          onTap: () {
            if (isOccupied) {
              final booking = _getBookingForTable(tableId, _selectedHour);
              if (booking != null) {
                _showBookingDetailsDialog(booking, table['name'] ?? '');
              }
            } else if (isTraining) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${table['name']} este ocupată automat pentru antrenamentul copiilor.'),
                  backgroundColor: Colors.purple,
                ),
              );
            } else {
              if (widget.isAdmin) {
                _showOfflineBookingDialog(table);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${table['name']} este liberă în acest interval!'),
                    backgroundColor: AppColors.good,
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            }
          },
          child: Container(
            height: 68,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor, width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: statusColor, size: 16),
                const SizedBox(height: 2),
                Text(
                  table['name'] ?? '',
                  style: TextStyle(color: AppColors.text, fontSize: 9, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontSize: 8, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        );
      } else {
        // Empty grid cells in view mode (Render simple space)
        return Container(
          height: 68,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.transparent),
          ),
        );
      }
    }
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: 11)),
      ],
    );
  }

  Widget _buildBadgeLegend(String label, Color color) {
    return _buildLegendItem(label, color);
  }
}

