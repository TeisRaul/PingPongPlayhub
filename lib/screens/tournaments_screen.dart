import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'chat_screen.dart';
import '../widgets/player_drawer.dart';
import '../theme/app_theme.dart';

class TournamentsScreen extends StatefulWidget {
  const TournamentsScreen({super.key});

  @override
  State<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends State<TournamentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? userData;
  bool isVenue = false;
  bool isVerifiedVenue = false;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserRole();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // First check players
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          userData = doc.data();
          isVenue = false;
          isVerifiedVenue = false;
          _isLoadingUser = false;
        });
      } else {
        // Fallback to venues
        final venueDoc = await FirebaseFirestore.instance.collection('venues').doc(user.uid).get();
        if (venueDoc.exists) {
          setState(() {
            userData = venueDoc.data();
            isVenue = true;
            isVerifiedVenue = venueDoc.data()?['isVerified'] ?? false;
            _isLoadingUser = false;
          });
        } else {
          setState(() => _isLoadingUser = false);
        }
      }
    } else {
      setState(() => _isLoadingUser = false);
    }
  }

  int getLevelValue(String levelName) {
    if (levelName == 'Diamond') return 20;
    
    final parts = levelName.split(' ');
    if (parts.length < 2) return 0;
    
    final tier = parts[0];
    final sub = parts[1];
    
    const List<String> tiers = ['Iron', 'Bronze', 'Silver', 'Gold', 'Platinum'];
    const List<String> subs = ['I', 'II', 'III', 'IV'];
    
    int tierIdx = tiers.indexOf(tier);
    int subIdx = subs.indexOf(sub);
    
    if (tierIdx == -1 || subIdx == -1) return 0;
    return tierIdx * 4 + subIdx;
  }

  void _showCreateTournamentDialog() {
    // Verificarea contului se cere doar sălilor; jucătorii pot doar PROPUNE turnee.
    if (isVenue && !isVerifiedVenue) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.orangeAccent, width: 1.5),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 28),
              SizedBox(width: 10),
              Text(tr('tour.unverified_title'), style: TextStyle(color: AppColors.text)),
            ],
          ),
          content: Text(
            tr('tour.unverified_body'),
            style: TextStyle(color: AppColors.text70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('common.close').toUpperCase(), style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => CreateTournamentForm(
        isPlayer: !isVenue,
        venueId: userData?['venueId'] ?? (isVenue ? FirebaseAuth.instance.currentUser?.uid ?? '' : ''),
        venueName: userData?['venueName'] ?? '',
        onSuccess: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isVenue ? tr('tour.created') : tr('tour.proposed_sent')),
              backgroundColor: Colors.green
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      drawer: const PlayerDrawer(activePage: 'tournaments'),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu, color: AppColors.accent),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: Text(tr('tour.title')),
        backgroundColor: AppColors.card,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.muted,
          tabs: [
            Tab(icon: const Icon(Icons.emoji_events_outlined), text: tr('tour.tab_active')),
            Tab(icon: const Icon(Icons.pending_actions), text: isVenue ? tr('tour.tab_approve') : tr('tour.tab_proposed')),
            Tab(icon: const Icon(Icons.history), text: tr('tour.tab_history')),
          ],
        ),
      ),
      floatingActionButton: (isVenue && isVerifiedVenue) || !isVenue
          ? FloatingActionButton.extended(
              onPressed: _showCreateTournamentDialog,
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              icon: Icon(isVenue ? Icons.add : Icons.campaign),
              label: Text(isVenue ? tr('tour.create') : tr('tour.propose'), style: const TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
      body: _isLoadingUser
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTournamentsList('active'),
                _buildTournamentsList('pending'),
                _buildTournamentsList('history'),
              ],
            ),
    );
  }


  /// Turneu încheiat după dată: data (yyyy-MM-dd) + ora de final (sau sfârșitul zilei).
  bool _isExpired(Map<String, dynamic> data) {
    final DateTime? d = DateTime.tryParse((data['date'] ?? '').toString());
    if (d == null) return false;
    final String end = (data['endTime'] ?? '').toString();
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(end);
    final DateTime endAt = m != null
        ? DateTime(d.year, d.month, d.day, int.parse(m.group(1)!), int.parse(m.group(2)!))
        : DateTime(d.year, d.month, d.day, 23, 59);
    return endAt.isBefore(DateTime.now());
  }

  /// Căruia dintre cele trei liste îi aparține turneul.
  bool _belongsTo(String listType, Map<String, dynamic> data) {
    final String status = (data['status'] ?? 'open').toString();
    final bool running = status == 'open' || status == 'active';
    switch (listType) {
      case 'active':
        return running && !_isExpired(data);
      case 'pending':
        return status == 'pending_approval';
      default:
        return status == 'completed' || (running && _isExpired(data));
    }
  }

  Widget _buildTournamentsList(String listType) {
    final Query baseQuery = FirebaseFirestore.instance.collection('tournaments');
    Query query;
    if (listType == 'active') {
      query = baseQuery.where('status', whereIn: ['open', 'active']);
    } else if (listType == 'pending') {
      query = baseQuery.where('status', isEqualTo: 'pending_approval');
    } else {
      // Finalizate + cele deschise/active a căror dată a trecut (filtrate local în _belongsTo).
      query = baseQuery.where('status', whereIn: ['completed', 'open', 'active']);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(tr('tour.load_error', {'error': '${snapshot.error}'}), style: const TextStyle(color: Colors.redAccent)));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: AppColors.accent));
        }

        final docs = (snapshot.data?.docs ?? [])
            .where((d) => _belongsTo(listType, d.data() as Map<String, dynamic>))
            .toList();
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_events_outlined, size: 64, color: AppColors.border700),
                const SizedBox(height: 16),
                Text(
                  listType == 'active' ? tr('tour.none_active') : tr('tour.none'),
                  style: TextStyle(color: AppColors.muted, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String id = doc.id;

            final String title = data['title'] ?? tr('tour.default_title');
            final String venueName = data['venueName'] ?? tr('tour.default_venue');
            final String date = data['date'] ?? '';
            final String time = data['time'] ?? '';
            final String endTime = data['endTime'] ?? '';
            final int maxPlayers = data['maxPlayers'] ?? 8;
            final List<dynamic> joinedUids = data['joinedUids'] ?? [];
            final String status = data['status'] ?? 'open';
            final double entryFee = (data['entryFee'] ?? 0).toDouble();
            final String minRank = data['minRank'] ?? 'Toate Rank-urile';
            final String maxRank = data['maxRank'] ?? 'Toate Rank-urile';

            Color statusColor = AppColors.accent;
            String statusText = tr('tour.st_open');
            if (status == 'active') {
              statusColor = Colors.orangeAccent;
              statusText = tr('tour.st_active');
            } else if (status == 'completed') {
              statusColor = Colors.greenAccent;
              statusText = tr('tour.st_completed');
            } else if (status == 'pending_approval') {
              statusColor = Colors.yellowAccent;
              statusText = tr('tour.st_pending');
            }
            if (listType == 'history' && status != 'completed') {
              statusColor = AppColors.muted;
              statusText = tr('tour.st_ended');
            }

            return Card(
              color: AppColors.card,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: statusColor.withValues(alpha: 0.3), width: 1.5),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TournamentDetailsScreen(
                        tournamentId: id,
                        currentUserData: userData,
                        isVenue: isVenue,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              statusText.toUpperCase(),
                              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                          ),
                          Text(
                            entryFee == 0 ? tr('tour.free') : tr('tour.fee', {'fee': '$entryFee'}),
                            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.storefront, size: 16, color: AppColors.muted),
                          const SizedBox(width: 6),
                          Text(venueName, style: TextStyle(color: AppColors.muted, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(color: AppColors.card2),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_month_outlined, size: 18, color: AppColors.accent),
                              const SizedBox(width: 6),
                              Text('$date | $time${endTime.isNotEmpty ? " - $endTime" : ""}', style: TextStyle(color: AppColors.text70, fontSize: 13)),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(Icons.people_outline, size: 18, color: AppColors.accent),
                              const SizedBox(width: 6),
                              Text(tr('tour.players_count', {'n': '${joinedUids.length}', 'max': '$maxPlayers'}), style: TextStyle(color: AppColors.text70, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.military_tech_outlined, size: 18, color: AppColors.accent),
                            const SizedBox(width: 6),
                            Text(
                              minRank == 'Toate Rank-urile'
                                  ? tr('tour.level_all')
                                  : tr('tour.level_range', {'min': minRank, 'max': maxRank}),
                              style: TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class CreateTournamentForm extends StatefulWidget {
  final bool isPlayer;
  final String venueId;
  final String venueName;
  final VoidCallback onSuccess;

  const CreateTournamentForm({
    super.key,
    this.isPlayer = false,
    required this.venueId,
    required this.venueName,
    required this.onSuccess,
  });

  @override
  State<CreateTournamentForm> createState() => _CreateTournamentFormState();
}

class _CreateTournamentFormState extends State<CreateTournamentForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _feeController = TextEditingController(text: '0');

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  TimeOfDay? _selectedEndTime;
  int _maxPlayers = 8;
  String _minRank = 'Toate Rank-urile';
  String _maxRank = 'Toate Rank-urile';
  bool _isLoading = false;

  // For players proposing tournaments
  String? _selectedVenueId;
  String? _selectedVenueName;
  int _numTables = 1;
  String _paymentMethod = 'Cash (la sală)';
  List<Map<String, dynamic>> _venues = [];

  final List<int> _playerSlots = [8, 16, 32, 64];

  final List<String> _ranks = [
    'Toate Rank-urile',
    'Iron I', 'Iron II', 'Iron III', 'Iron IV',
    'Bronze I', 'Bronze II', 'Bronze III', 'Bronze IV',
    'Silver I', 'Silver II', 'Silver III', 'Silver IV',
    'Gold I', 'Gold II', 'Gold III', 'Gold IV',
    'Platinum I', 'Platinum II', 'Platinum III', 'Platinum IV',
    'Diamond'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isPlayer) {
      _loadVenues();
    } else {
      _selectedVenueId = widget.venueId;
      _selectedVenueName = widget.venueName;
    }
  }

  Future<void> _loadVenues() async {
    try {
      // We actually need to query 'venues' collection if it exists. But previously we checked users and venues.
      // The venues are those where isVerified is true (wait, earlier it was 'users' or 'venues').
      // Let's query 'venues' collection.
      final venuesSnap = await FirebaseFirestore.instance.collection('venues').where('isVerified', isEqualTo: true).get();
      setState(() {
        _venues = venuesSnap.docs.map((doc) => {'id': doc.id, 'name': doc.data()['venueName'] ?? 'Sală'}).toList();
      });
    } catch (e) {
      debugPrint('Eroare load venues: $e');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: AppColors.scheme(
              primary: AppColors.accent,
              onPrimary: AppColors.onAccent,
              surface: AppColors.card,
              onSurface: AppColors.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: AppColors.scheme(
              primary: AppColors.accent,
              onPrimary: AppColors.onAccent,
              surface: AppColors.card,
              onSurface: AppColors.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: AppColors.scheme(
              primary: AppColors.bad,
              onPrimary: AppColors.onAccent,
              surface: AppColors.card,
              onSurface: AppColors.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedEndTime = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null || _selectedEndTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selectează data, ora de start și ora de sfârșit!'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (widget.isPlayer && _selectedVenueId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trebuie să selectezi o sală parteneră!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final startMin = _selectedTime!.hour * 60 + _selectedTime!.minute;
    final endMin = _selectedEndTime!.hour * 60 + _selectedEndTime!.minute;
    if (endMin <= startMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ora de sfârșit trebuie să fie după ora de start!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final hourStr = _selectedTime!.hour.toString().padLeft(2, '0');
      final minuteStr = _selectedTime!.minute.toString().padLeft(2, '0');
      final timeStr = '$hourStr:$minuteStr';

      final endHourStr = _selectedEndTime!.hour.toString().padLeft(2, '0');
      final endMinuteStr = _selectedEndTime!.minute.toString().padLeft(2, '0');
      final endTimeStr = '$endHourStr:$endMinuteStr';

      // 1. Create Tournament Document
      final tourRef = FirebaseFirestore.instance.collection('tournaments').doc();
      await tourRef.set({
        'tournamentId': tourRef.id,
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'date': dateStr,
        'time': timeStr,
        'endTime': endTimeStr,
        'maxPlayers': _maxPlayers,
        'entryFee': double.tryParse(_feeController.text) ?? 0.0,
        'minRank': _minRank,
        'maxRank': _maxRank,
        'venueId': widget.isPlayer ? _selectedVenueId : widget.venueId,
        'venueName': widget.isPlayer ? _selectedVenueName : widget.venueName,
        'joinedUids': [],
        'joinedPlayers': [],
        'status': widget.isPlayer ? 'pending_approval' : 'open',
        'createdAt': FieldValue.serverTimestamp(),
        if (widget.isPlayer) 'proposerUid': FirebaseAuth.instance.currentUser?.uid,
        if (widget.isPlayer) 'numTables': _numTables,
        if (widget.isPlayer) 'paymentMethod': _paymentMethod,
      });

      // Notificări (popup + email): propunerea ajunge la sală, creatorul primește confirmarea.
      try {
        final String meUid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final meDoc = await FirebaseFirestore.instance.collection('users').doc(meUid).get();
        final String meName = (meDoc.data()?['username'] ?? '').toString();
        final String targetVenueId = widget.isPlayer ? (_selectedVenueId ?? '') : widget.venueId;
        final String targetVenueName = widget.isPlayer ? (_selectedVenueName ?? '') : widget.venueName;
        final tArgs = {
          'title': _titleController.text.trim(),
          'date': dateStr,
          'time': timeStr,
          'venue': targetVenueName,
          'player': meName,
        };
        if (widget.isPlayer) {
          await NotificationService.send(toUid: targetVenueId, type: 'tournament_proposed', titleKey: 'n.tour_proposed_venue_title', bodyKey: 'n.tour_proposed_venue_body', args: tArgs);
          await NotificationService.send(toUid: meUid, allowSelf: true, type: 'tournament_proposed', titleKey: 'n.tour_proposed_self_title', bodyKey: 'n.tour_proposed_self_body', args: tArgs);
        } else {
          await NotificationService.send(toUid: meUid, allowSelf: true, type: 'tournament_created', titleKey: 'n.tour_created_title', bodyKey: 'n.tour_created_body', args: tArgs);
        }
      } catch (_) {}

      // 2. Note: We no longer block the entire day in the venue's doc.
      // Tournament time blocks are validated dynamically during match reservation!

      // 3. Create corresponding group chat for the tournament
      final chatRef = FirebaseFirestore.instance.collection('chats').doc('tournament_${tourRef.id}');
      await chatRef.set({
        'isTournamentChat': true,
        'tournamentId': tourRef.id,
        'title': 'Chat: ${_titleController.text.trim()}',
        'adminUid': widget.venueId,
        'onlyAdminCanSend': false,
        'uids': [widget.venueId],
        'usernames': [widget.venueName],
        'avatars': [''],
        'lastMessage': 'Grup creat pentru turneu.',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      widget.onSuccess();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la crearea turneului: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 24,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Organizează un Turneu',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: AppColors.muted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (widget.isPlayer) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedVenueId,
                    decoration: const InputDecoration(
                      labelText: 'Selectează Sala Parteneră',
                      prefixIcon: Icon(Icons.storefront),
                    ),
                    items: _venues.map((v) {
                      return DropdownMenuItem<String>(
                        value: v['id'],
                        child: Text(v['name']),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedVenueId = val;
                        _selectedVenueName = _venues.firstWhere((v) => v['id'] == val)['name'];
                      });
                    },
                    validator: (val) => val == null ? 'Alege o sală pentru turneu' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _numTables,
                          decoration: const InputDecoration(
                            labelText: 'Mese Necesare',
                            prefixIcon: Icon(Icons.table_restaurant),
                          ),
                          items: List.generate(10, (index) => index + 1).map((n) {
                            return DropdownMenuItem<int>(
                              value: n,
                              child: Text('$n Mese'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _numTables = val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _paymentMethod,
                          decoration: const InputDecoration(
                            labelText: 'Plată Sală',
                            prefixIcon: Icon(Icons.payment),
                          ),
                          items: ['Cash (la sală)', 'Card în aplicație'].map((m) {
                            return DropdownMenuItem<String>(
                              value: m,
                              child: Text(m),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _paymentMethod = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titlu Turneu',
                    prefixIcon: Icon(Icons.emoji_events_outlined),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Te rugăm să introduci titlul' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Descriere / Detalii / Regulament',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Te rugăm să introduci detalii' : null,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: Icon(Icons.calendar_month, color: AppColors.accent),
                  label: Text(
                    _selectedDate == null
                        ? 'Alege Data Turneului'
                        : DateFormat('dd MMMM yyyy').format(_selectedDate!),
                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickTime,
                        icon: Icon(Icons.access_time, color: AppColors.accent),
                        label: Text(
                          _selectedTime == null
                              ? 'Ora Start'
                              : '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: AppColors.text),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickEndTime,
                        icon: Icon(Icons.lock_clock, color: AppColors.bad),
                        label: Text(
                          _selectedEndTime == null
                              ? 'Ora Sfârșit'
                              : '${_selectedEndTime!.hour.toString().padLeft(2, '0')}:${_selectedEndTime!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: AppColors.text),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: AppColors.bad.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _maxPlayers,
                        decoration: const InputDecoration(labelText: 'Maxim Jucători'),
                        items: _playerSlots
                            .map((slots) => DropdownMenuItem(value: slots, child: Text('$slots Jucători')))
                            .toList(),
                        onChanged: (val) => setState(() => _maxPlayers = val ?? 8),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _feeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Taxă Înscriere (RON)'),
                        validator: (val) => val == null || double.tryParse(val) == null ? 'Valoare invalidă' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Restricție Nivel Rank:', style: TextStyle(color: AppColors.text70, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _minRank,
                        decoration: const InputDecoration(labelText: 'Nivel Minim'),
                        items: _ranks
                            .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                            .toList(),
                        onChanged: (val) => setState(() {
                          _minRank = val ?? 'Toate Rank-urile';
                          if (_minRank == 'Toate Rank-urile') {
                            _maxRank = 'Toate Rank-urile';
                          } else {
                            final minIdx = _ranks.indexOf(_minRank);
                            final maxIdx = _ranks.indexOf(_maxRank);
                            if (_maxRank == 'Toate Rank-urile' || maxIdx < minIdx) {
                              _maxRank = _minRank;
                            }
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _maxRank,
                        decoration: const InputDecoration(labelText: 'Nivel Maxim'),
                        items: _ranks
                            .where((r) {
                              if (_minRank == 'Toate Rank-urile') {
                                return r == 'Toate Rank-urile';
                              }
                              if (r == 'Toate Rank-urile') return false;
                              return _ranks.indexOf(r) >= _ranks.indexOf(_minRank);
                            })
                            .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                            .toList(),
                        onChanged: (val) => setState(() => _maxRank = val ?? 'Toate Rank-urile'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black))
                      : const Text('CREEAZĂ TURNEUL'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TournamentDetailsScreen extends StatefulWidget {
  final String tournamentId;
  final Map<String, dynamic>? currentUserData;
  final bool isVenue;

  const TournamentDetailsScreen({
    super.key,
    required this.tournamentId,
    required this.currentUserData,
    required this.isVenue,
  });

  @override
  State<TournamentDetailsScreen> createState() => _TournamentDetailsScreenState();
}

class _TournamentDetailsScreenState extends State<TournamentDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _detailTabController;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _detailTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _detailTabController.dispose();
    super.dispose();
  }

  int getLevelValue(String levelName) {
    if (levelName == 'Diamond') return 20;
    
    final parts = levelName.split(' ');
    if (parts.length < 2) return 0;
    
    final tier = parts[0];
    final sub = parts[1];
    
    const List<String> tiers = ['Iron', 'Bronze', 'Silver', 'Gold', 'Platinum'];
    const List<String> subs = ['I', 'II', 'III', 'IV'];
    
    int tierIdx = tiers.indexOf(tier);
    int subIdx = subs.indexOf(sub);
    
    if (tierIdx == -1 || subIdx == -1) return 0;
    return tierIdx * 4 + subIdx;
  }

  Future<void> _joinTournament(Map<String, dynamic> tourData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.currentUserData == null) return;

    final List<dynamic> joinedUids = List.from(tourData['joinedUids'] ?? []);
    final List<dynamic> joinedPlayers = List.from(tourData['joinedPlayers'] ?? []);
    final int maxPlayers = tourData['maxPlayers'] ?? 8;

    if (joinedUids.length >= maxPlayers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acest turneu este deja plin!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    // Rank validation
    final String minRank = tourData['minRank'] ?? 'Toate Rank-urile';
    final String maxRank = tourData['maxRank'] ?? 'Toate Rank-urile';
    final String playerLevel = widget.currentUserData?['level'] ?? 'Iron I';

    if (minRank != 'Toate Rank-urile') {
      int playerVal = getLevelValue(playerLevel);
      int minVal = getLevelValue(minRank);
      int maxVal = getLevelValue(maxRank);

      if (playerVal < minVal || playerVal > maxVal) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent, width: 1.5)),
            title: Text('Restricție de Nivel', style: TextStyle(color: AppColors.text)),
            content: Text('Nivelul tău ($playerLevel) nu se încadrează în intervalul permis pentru acest turneu ($minRank - $maxRank).'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK', style: TextStyle(color: AppColors.accent)),
              ),
            ],
          ),
        );
        return;
      }
    }

    setState(() => _isActionLoading = true);

    try {
      final myProfileData = {
        'uid': user.uid,
        'username': widget.currentUserData?['username'] ?? 'Player',
        'rating': widget.currentUserData?['rating'] ?? 0,
        'level': playerLevel,
      };

      joinedUids.add(user.uid);
      joinedPlayers.add(myProfileData);

      await FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).update({
        'joinedUids': joinedUids,
        'joinedPlayers': joinedPlayers,
      });

      final joinArgs = {
        'title': (tourData['title'] ?? '').toString(),
        'date': (tourData['date'] ?? '').toString(),
        'time': (tourData['time'] ?? '').toString(),
        'venue': (tourData['venueName'] ?? '').toString(),
        'player': (myProfileData['username'] ?? '').toString(),
      };
      await NotificationService.send(toUid: (tourData['venueId'] ?? '').toString(), type: 'tournament_join', titleKey: 'n.tour_join_venue_title', bodyKey: 'n.tour_join_venue_body', args: joinArgs);
      await NotificationService.send(toUid: user.uid, allowSelf: true, type: 'tournament_join', titleKey: 'n.tour_join_self_title', bodyKey: 'n.tour_join_self_body', args: joinArgs);

      // Synchronize in tournament chat room
      final chatRef = FirebaseFirestore.instance.collection('chats').doc('tournament_${widget.tournamentId}');
      final chatSnapshot = await chatRef.get();
      if (!chatSnapshot.exists) {
        await chatRef.set({
          'isTournamentChat': true,
          'tournamentId': widget.tournamentId,
          'title': tourData['title'] ?? 'Chat Turneu',
          'adminUid': tourData['venueId'] ?? '',
          'uids': [tourData['venueId'] ?? '', user.uid],
          'usernames': [tourData['venueName'] ?? 'Club', widget.currentUserData?['username'] ?? 'Player'],
          'avatars': ['', widget.currentUserData?['avatarUrl'] ?? ''],
          'lastMessage': 'Chat-ul turneului a fost inițializat.',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'onlyAdminCanSend': false,
        }, SetOptions(merge: true));
      } else {
        await chatRef.update({
          'uids': FieldValue.arrayUnion([user.uid]),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Te-ai înscris cu succes în turneu!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la înscriere: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _leaveTournament(Map<String, dynamic> tourData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isActionLoading = true);

    try {
      final List<dynamic> joinedUids = List.from(tourData['joinedUids'] ?? []);
      final List<dynamic> joinedPlayers = List.from(tourData['joinedPlayers'] ?? []);

      final String leavingName = joinedPlayers
          .where((p) => p['uid'] == user.uid)
          .map((p) => (p['username'] ?? '').toString())
          .firstWhere((_) => true, orElse: () => '');
      joinedUids.remove(user.uid);
      joinedPlayers.removeWhere((p) => p['uid'] == user.uid);

      await FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).update({
        'joinedUids': joinedUids,
        'joinedPlayers': joinedPlayers,
      });
      await NotificationService.send(
        toUid: (tourData['venueId'] ?? '').toString(),
        type: 'tournament_leave',
        titleKey: 'n.tour_leave_venue_title',
        bodyKey: 'n.tour_leave_venue_body',
        args: {'title': (tourData['title'] ?? '').toString(), 'player': leavingName},
      );

      // Synchronize in tournament chat room
      final chatRef = FirebaseFirestore.instance.collection('chats').doc('tournament_${widget.tournamentId}');
      final chatSnapshot = await chatRef.get();
      if (chatSnapshot.exists) {
        await chatRef.update({
          'uids': FieldValue.arrayRemove([user.uid]),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Te-ai retras din turneu.'), backgroundColor: Colors.orangeAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _approveTournament() async {
    setState(() => _isActionLoading = true);
    try {
      final tRef = FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId);
      final tData = (await tRef.get()).data() ?? {};
      await tRef.update({
        'status': 'open',
      });
      await NotificationService.send(
        toUid: (tData['proposerUid'] ?? '').toString(),
        type: 'tournament_approved',
        titleKey: 'n.tour_approved_title',
        bodyKey: 'n.tour_approved_body',
        args: {'title': (tData['title'] ?? '').toString(), 'date': (tData['date'] ?? '').toString(), 'venue': (tData['venueName'] ?? '').toString()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turneul a fost aprobat!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _rejectTournament() async {
    setState(() => _isActionLoading = true);
    try {
      final tRef = FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId);
      final tData = (await tRef.get()).data() ?? {};
      await tRef.update({
        'status': 'cancelled',
      });
      await NotificationService.send(
        toUid: (tData['proposerUid'] ?? '').toString(),
        type: 'tournament_rejected',
        titleKey: 'n.tour_rejected_title',
        bodyKey: 'n.tour_rejected_body',
        args: {'title': (tData['title'] ?? '').toString(), 'date': (tData['date'] ?? '').toString(), 'venue': (tData['venueName'] ?? '').toString()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Propunerea a fost respinsă.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _cancelTournament(Map<String, dynamic> tourData) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text('Anulează Turneul', style: TextStyle(color: AppColors.text)),
          ],
        ),
        content: Text(
          'Sigur dorești să anulezi acest turneu? Această acțiune este ireversibilă, va notifica toți jucătorii înscriși și va debloca automat ziua respectivă în calendarul clubului.',
          style: TextStyle(color: AppColors.text70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('ÎNCHIDE', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ANULEAZĂ TURNEUL', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isActionLoading = true);

    try {
      final String dateStr = tourData['date'] ?? '';
      final String venueId = tourData['venueId'] ?? '';
      final String title = tourData['title'] ?? 'Turneu';
      final List<dynamic> joinedPlayers = tourData['joinedPlayers'] ?? [];

      // 1. Update tournament status
      await FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).update({
        'status': 'cancelled',
      });

      // 2. Unblock date in venue
      if (dateStr.isNotEmpty && venueId.isNotEmpty) {
        final venueRef = FirebaseFirestore.instance.collection('venues').doc(venueId);
        await venueRef.update({
          'blockedDates': FieldValue.arrayRemove([dateStr]),
        });
      }

      // 3. Send notifications to all joined players
      final batch = FirebaseFirestore.instance.batch();
      for (var player in joinedPlayers) {
        final String playerUid = player['uid'];
        final notifRef = FirebaseFirestore.instance.collection('notifications').doc();
        batch.set(notifRef, {
          'toUid': playerUid,
          'fromUid': 'system',
          'fromUsername': 'PingPong Playhub',
          'title': 'Turneu Anulat',
          'body': 'Turneul "$title" la care te-ai înscris a fost anulat de către organizator.',
          'type': 'tournament_cancelled',
          'status': 'pending',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      // 4. Post system message in tournament chat
      final chatRef = FirebaseFirestore.instance.collection('chats').doc('tournament_${widget.tournamentId}');
      final batch2 = FirebaseFirestore.instance.batch();
      batch2.update(chatRef, {
        'lastMessage': 'Turneul a fost anulat de către organizator.',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
      final msgRef = chatRef.collection('messages').doc();
      batch2.set(msgRef, {
        'senderUid': 'system',
        'text': 'Turneul a fost anulat de către organizator.',
        'timestamp': FieldValue.serverTimestamp(),
      });
      await batch2.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turneul a fost anulat cu succes!'), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Map<String, dynamic> _buildInitialBracket(List<dynamic> players, int maxPlayers) {
    List<dynamic> bracketPlayers = List.from(players);
    while (bracketPlayers.length < maxPlayers) {
      bracketPlayers.add(null);
    }

    // Shuffle for random seed pairings
    bracketPlayers.shuffle();

    Map<String, dynamic> matches = {};
    int currentRound = 1;
    int tempMatchesCount = maxPlayers ~/ 2;

    while (tempMatchesCount >= 1) {
      String roundName = "";
      if (tempMatchesCount == 4) {
        roundName = "Sferturi";
      } else if (tempMatchesCount == 2) roundName = "Semifinale";
      else if (tempMatchesCount == 1) roundName = "Finala Mare";
      else roundName = "Runda de $tempMatchesCount";

      for (int i = 0; i < tempMatchesCount; i++) {
        String matchId = "R${currentRound}_M$i";
        
        String? nextMatchId;
        int? nextMatchSlot;
        String? loserMatchId;
        int? loserMatchSlot;

        if (tempMatchesCount > 1) {
          if (tempMatchesCount == 2) {
            nextMatchId = "Finals";
            nextMatchSlot = i + 1;
            loserMatchId = "ThirdPlace";
            loserMatchSlot = i + 1;
          } else {
            nextMatchId = "R${currentRound + 1}_M${i ~/ 2}";
            nextMatchSlot = (i % 2) + 1;
          }
        }

        dynamic p1 = (currentRound == 1) ? bracketPlayers[2 * i] : null;
        dynamic p2 = (currentRound == 1) ? bracketPlayers[2 * i + 1] : null;

        String? winnerUid;
        bool isCompleted = false;
        if (currentRound == 1) {
          if (p1 == null && p2 == null) {
            isCompleted = true;
          } else if (p1 == null) {
            winnerUid = p2['uid'];
            isCompleted = true;
          } else if (p2 == null) {
            winnerUid = p1['uid'];
            isCompleted = true;
          }
        }

        matches[matchId] = {
          'matchId': matchId,
          'round': currentRound,
          'roundName': roundName,
          'player1': p1,
          'player2': p2,
          'score1': null,
          'score2': null,
          'winnerUid': winnerUid,
          'isCompleted': isCompleted,
          'nextMatchId': nextMatchId,
          'nextMatchSlot': nextMatchSlot,
          'loserMatchId': loserMatchId,
          'loserMatchSlot': loserMatchSlot,
        };
      }

      tempMatchesCount ~/= 2;
      currentRound++;
    }

    // Add ThirdPlace Match
    matches["ThirdPlace"] = {
      'matchId': "ThirdPlace",
      'round': currentRound - 1,
      'roundName': "Finala Mică",
      'player1': null,
      'player2': null,
      'score1': null,
      'score2': null,
      'winnerUid': null,
      'isCompleted': false,
      'nextMatchId': null,
      'nextMatchSlot': null,
    };

    // Pre-advance BYEs
    matches.forEach((id, match) {
      if (match['isCompleted'] && match['winnerUid'] != null) {
        final winner = match['winnerUid'] == match['player1']?['uid'] ? match['player1'] : match['player2'];
        final nextId = match['nextMatchId'];
        final nextSlot = match['nextMatchSlot'];
        if (nextId != null && nextSlot != null && matches.containsKey(nextId)) {
          if (nextSlot == 1) {
            matches[nextId]!['player1'] = winner;
          } else {
            matches[nextId]!['player2'] = winner;
          }
        }
      }
    });

    return matches;
  }

  Future<void> _generateBracket(Map<String, dynamic> tourData) async {
    final List<dynamic> joinedPlayers = tourData['joinedPlayers'] ?? [];
    final int maxPlayers = tourData['maxPlayers'] ?? 8;

    if (joinedPlayers.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sunt necesari cel puțin 2 jucători pentru a genera bracket-ul!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isActionLoading = true);

    try {
      final bracketMatches = _buildInitialBracket(joinedPlayers, maxPlayers);

      await FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).update({
        'status': 'active',
        'bracket': bracketMatches,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bracket generat cu succes! Spor la joc!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _recordMatchResult(
    String matchId,
    int score1,
    int score2,
    String winnerUid,
    Map<String, dynamic> bracketMatches,
    List<dynamic> joinedPlayers,
  ) async {
    setState(() => _isActionLoading = true);

    try {
      final updatedBracket = Map<String, dynamic>.from(bracketMatches);
      final match = Map<String, dynamic>.from(updatedBracket[matchId]);

      final p1 = match['player1'];
      final p2 = match['player2'];

      match['score1'] = score1;
      match['score2'] = score2;
      match['winnerUid'] = winnerUid;
      match['isCompleted'] = true;

      updatedBracket[matchId] = match;

      final winnerPlayer = (p1 != null && p1['uid'] == winnerUid) ? p1 : p2;
      final loserPlayer = (p1 != null && p1['uid'] == winnerUid) ? p2 : p1;

      // Advance Winner
      final String? nextId = match['nextMatchId'];
      final int? nextSlot = match['nextMatchSlot'];
      if (nextId != null && nextSlot != null && updatedBracket.containsKey(nextId)) {
        final nextMatch = Map<String, dynamic>.from(updatedBracket[nextId]);
        if (nextSlot == 1) {
          nextMatch['player1'] = winnerPlayer;
        } else {
          nextMatch['player2'] = winnerPlayer;
        }
        
        // Auto-advance if next match other slot is already resolved as BYE
        updatedBracket[nextId] = nextMatch;
      }

      // Advance Loser if Semifinal
      final String? loserId = match['loserMatchId'];
      final int? loserSlot = match['loserMatchSlot'];
      if (loserId != null && loserSlot != null && updatedBracket.containsKey(loserId)) {
        final loserMatch = Map<String, dynamic>.from(updatedBracket[loserId]);
        if (loserSlot == 1) {
          loserMatch['player1'] = loserPlayer;
        } else {
          loserMatch['player2'] = loserPlayer;
        }
        updatedBracket[loserId] = loserMatch;
      }

      // Check if Finals are complete
      final finalMatch = updatedBracket['Finals'];
      final thirdMatch = updatedBracket['ThirdPlace'];
      
      bool tourComplete = false;
      if (finalMatch != null && finalMatch['isCompleted'] == true &&
          (thirdMatch == null || thirdMatch['isCompleted'] == true || thirdMatch['player1'] == null || thirdMatch['player2'] == null)) {
        tourComplete = true;
      }

      if (tourComplete) {
        // Tournament fully finished, distribute points!
        final String winnerOfFinals = finalMatch['winnerUid'];
        final String loserOfFinals = (finalMatch['player1']?['uid'] == winnerOfFinals)
            ? (finalMatch['player2']?['uid'] ?? '')
            : (finalMatch['player1']?['uid'] ?? '');

        String winnerOfThirdPlace = '';
        String loserOfThirdPlace = '';
        if (thirdMatch != null && thirdMatch['isCompleted'] == true) {
          winnerOfThirdPlace = thirdMatch['winnerUid'] ?? '';
          loserOfThirdPlace = (thirdMatch['player1']?['uid'] == winnerOfThirdPlace)
              ? (thirdMatch['player2']?['uid'] ?? '')
              : (thirdMatch['player1']?['uid'] ?? '');
        }

        final batch = FirebaseFirestore.instance.batch();
        for (var player in joinedPlayers) {
          final String playerUid = player['uid'];
          int pointsToAdd = 0;

          if (playerUid == winnerOfFinals) {
            pointsToAdd = 350;
          } else if (playerUid == loserOfFinals) {
            pointsToAdd = 300;
          } else if (playerUid == winnerOfThirdPlace) {
            pointsToAdd = 250;
          } else if (playerUid == loserOfThirdPlace) {
            pointsToAdd = 200;
          } else {
            // Find round where they lost
            int highestLostRound = 1;
            for (var mId in updatedBracket.keys) {
              final m = updatedBracket[mId] as Map<String, dynamic>;
              if (m['isCompleted'] == true &&
                  (m['player1']?['uid'] == playerUid || m['player2']?['uid'] == playerUid) &&
                  m['winnerUid'] != playerUid) {
                highestLostRound = m['round'] ?? 1;
                break;
              }
            }
            if (highestLostRound == 1) {
              pointsToAdd = 0;
            } else if (highestLostRound == 2) pointsToAdd = 30;
            else pointsToAdd = 60; // Round 3 and above
          }

          if (pointsToAdd > 0) {
            final userRef = FirebaseFirestore.instance.collection('users').doc(playerUid);
            batch.update(userRef, {
              'rating': FieldValue.increment(pointsToAdd),
            });

            // Send notification to player
            final notifRef = FirebaseFirestore.instance.collection('notifications').doc();
            batch.set(notifRef, {
              'toUid': playerUid,
              'fromUid': 'system',
              'fromUsername': 'PingPong Playhub',
              'title': 'Puncte Turneu Acordate!',
              'body': 'Felicitări! Ai primit +$pointsToAdd puncte în clasament pentru performanța ta din turneu.',
              'type': 'points_earned',
              'status': 'pending',
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
        }

        await batch.commit();

        final p1 = finalMatch['player1'] as Map<String, dynamic>?;
        final p2 = finalMatch['player2'] as Map<String, dynamic>?;
        final isP1Winner = finalMatch['winnerUid'] == p1?['uid'];
        final winnerUsername = isP1Winner ? (p1?['username'] ?? '') : (p2?['username'] ?? '');

        await FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).update({
          'status': 'completed',
          'bracket': updatedBracket,
          'winnerUid': winnerOfFinals,
          'winnerUsername': winnerUsername,
        });
      } else {
        await FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).update({
          'bracket': updatedBracket,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rezultat înregistrat cu succes!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la înregistrarea rezultatului: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _showScoreInputDialog(String matchId, Map<String, dynamic> match, Map<String, dynamic> bracketMatches, List<dynamic> joinedPlayers) {
    final p1 = match['player1'];
    final p2 = match['player2'];

    if (p1 == null || p2 == null) return;

    final score1Ctrl = TextEditingController(text: '0');
    final score2Ctrl = TextEditingController(text: '0');
    String winnerUid = p1['uid'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.accent, width: 1.5),
              ),
              title: Text('Introdu Scorul Meciului', style: TextStyle(color: AppColors.text)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Scor pentru ${p1['username']}:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: score1Ctrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text('Scor pentru ${p2['username']}:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: score2Ctrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Text('Alege Câștigătorul:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: winnerUid,
                    dropdownColor: AppColors.card,
                    items: [
                      DropdownMenuItem(value: p1['uid'], child: Text(p1['username'], style: TextStyle(color: AppColors.text))),
                      DropdownMenuItem(value: p2['uid'], child: Text(p2['username'], style: TextStyle(color: AppColors.text))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => winnerUid = val);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('ANULEAZĂ', style: TextStyle(color: AppColors.muted)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    final s1 = int.tryParse(score1Ctrl.text) ?? 0;
                    final s2 = int.tryParse(score2Ctrl.text) ?? 0;
                    _recordMatchResult(matchId, s1, s2, winnerUid, bracketMatches, joinedPlayers);
                  },
                  child: Text('SALVEAZĂ REZULTAT', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('Eroare: ${snapshot.error}')));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
        }

        final tourDoc = snapshot.data;
        if (tourDoc == null || !tourDoc.exists) {
          return const Scaffold(body: Center(child: Text('Turneul nu a fost găsit.')));
        }

        final data = tourDoc.data() as Map<String, dynamic>;
        final String title = data['title'] ?? 'Turneu';
        final List<dynamic> joinedUids = data['joinedUids'] ?? [];
        final List<dynamic> joinedPlayers = data['joinedPlayers'] ?? [];
        final int maxPlayers = data['maxPlayers'] ?? 8;
        final String venueId = data['venueId'] ?? '';

        final user = FirebaseAuth.instance.currentUser;
        final bool isJoined = user != null && joinedUids.contains(user.uid);
        final bool isHost = user != null && user.uid == venueId;

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            title: Text(title),
            backgroundColor: AppColors.card,
            elevation: 0,
            bottom: TabBar(
              controller: _detailTabController,
              indicatorColor: AppColors.accent,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.muted,
              tabs: const [
                Tab(text: 'Detalii'),
                Tab(text: 'Jucători'),
                Tab(text: 'Tablou Bracket'),
              ],
            ),
          ),
          body: _isActionLoading
              ? Center(child: CircularProgressIndicator(color: AppColors.accent))
              : TabBarView(
                  controller: _detailTabController,
                  children: [
                    _buildDetailsTab(data, isJoined, isHost),
                    _buildPlayersTab(joinedPlayers, maxPlayers),
                    _buildBracketTab(data, isHost),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildDetailsTab(Map<String, dynamic> tourData, bool isJoined, bool isHost) {
    final String desc = tourData['description'] ?? 'Fără descriere.';
    final String venueName = tourData['venueName'] ?? 'Club';
    final String minRank = tourData['minRank'] ?? 'Toate Rank-urile';
    final String maxRank = tourData['maxRank'] ?? 'Toate Rank-urile';
    final int maxPlayers = tourData['maxPlayers'] ?? 8;
    final List<dynamic> joinedUids = tourData['joinedUids'] ?? [];
    final String status = tourData['status'] ?? 'open';
    final String date = tourData['date'] ?? '';
    final String time = tourData['time'] ?? '';
    final String endTime = tourData['endTime'] ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Status
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: status == 'open'
                  ? Colors.green.withValues(alpha: 0.15)
                  : status == 'active'
                      ? Colors.orange.withValues(alpha: 0.15)
                      : status == 'completed'
                          ? Colors.blue.withValues(alpha: 0.15)
                          : Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: status == 'open'
                    ? Colors.green
                    : status == 'active'
                        ? Colors.orange
                        : status == 'completed'
                            ? Colors.blue
                            : Colors.red,
              ),
            ),
            child: Text(
              status == 'open'
                  ? 'ÎNSCRIERI DESCHISE'
                  : status == 'active'
                      ? 'TURNEU ÎN DESFĂȘURARE'
                      : status == 'completed'
                          ? 'TURNEU FINALIZAT'
                          : 'TURNEU ANULAT',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: status == 'open'
                    ? Colors.greenAccent
                    : status == 'active'
                        ? Colors.orangeAccent
                        : status == 'completed'
                            ? Colors.blueAccent
                            : Colors.redAccent,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Detail Card
          Card(
            color: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Despre Turneu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.accent)),
                  const SizedBox(height: 8),
                  Text(desc, style: TextStyle(color: AppColors.text70, fontSize: 14, height: 1.4)),
                  const SizedBox(height: 20),
                  Divider(color: AppColors.card2),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.storefront, 'Locație', venueName),
                  _buildDetailRow(Icons.calendar_month, 'Data & Ora', '$date, $time${endTime.isNotEmpty ? " - $endTime" : ""}'),
                  _buildDetailRow(Icons.people, 'Număr de participanți', '${joinedUids.length} / $maxPlayers înscriși'),
                  _buildDetailRow(
                    Icons.military_tech_outlined,
                    'Restricție nivel',
                    minRank == 'Toate Rank-urile' ? 'Fără limită' : '$minRank - $maxRank',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Chat Button (visible to anyone joined or the host)
          if (isJoined || isHost) ...[
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      chatId: 'tournament_${widget.tournamentId}',
                      isTournamentChat: true,
                      tournamentTitle: tourData['title'] ?? 'Chat Turneu',
                      adminUid: tourData['venueId'],
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('DESCHIDE CHAT TURNEU'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action button
          if (!widget.isVenue) ...[
            if (status == 'open') ...[
              if (isJoined)
                ElevatedButton.icon(
                  onPressed: () => _leaveTournament(tourData),
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('RETRAGE-TE DIN TURNEU'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _joinTournament(tourData),
                  icon: const Icon(Icons.person_add),
                  label: const Text('ÎNSCRIE-TE ACUM'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
            ] else if (status == 'pending_approval')
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'Propunerea ta este în așteptarea aprobării clubului.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              )
            else if (status == 'cancelled')
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'Acest turneu a fost anulat de organizator.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Înscrierile sunt închise pentru acest turneu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
              ),
          ] else if (isHost) ...[
            if (status == 'pending_approval') ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _rejectTournament,
                      icon: const Icon(Icons.close),
                      label: const Text('RESPINGE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _approveTournament,
                      icon: const Icon(Icons.check),
                      label: const Text('APROBĂ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (status == 'open') ...[
              ElevatedButton.icon(
                onPressed: () => _generateBracket(tourData),
                icon: const Icon(Icons.grid_view_rounded),
                label: const Text('GENEREAZĂ BRACKET'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Apasă pe butonul de mai sus când înscrierile sunt gata pentru a crea schema meciurilor.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
            if (status == 'open' || status == 'active') ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _cancelTournament(tourData),
                icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                label: const Text('ANULEAZĂ TURNEUL', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPlayersTab(List<dynamic> joinedPlayers, int maxPlayers) {
    if (joinedPlayers.isEmpty) {
      return Center(child: Text('Niciun jucător înscris încă.', style: TextStyle(color: AppColors.muted)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: joinedPlayers.length,
      itemBuilder: (context, index) {
        final player = joinedPlayers[index];
        final String name = player['username'] ?? 'Player';
        final int rating = player['rating'] ?? 0;
        final String level = player['level'] ?? 'Iron I';

        return Card(
          color: AppColors.card,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.accent.withValues(alpha: 0.1),
              child: Text('${index + 1}', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
            ),
            title: Text(name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
            subtitle: Text(level, style: TextStyle(color: AppColors.muted)),
            trailing: Text('$rating PTS', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  Widget _buildBracketTab(Map<String, dynamic> tourData, bool isHost) {
    final String status = tourData['status'] ?? 'open';
    if (status == 'open') {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.grid_view_rounded, size: 64, color: AppColors.muted),
              SizedBox(height: 16),
              Text(
                'Bracket-ul se va genera după încheierea înscrierilor de către organizatorul turneului.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    final bracket = tourData['bracket'] as Map<String, dynamic>? ?? {};
    final int maxPlayers = tourData['maxPlayers'] ?? 8;

    // Group matches into rounds for visual presentation
    // R1, R2, R3... Finals, ThirdPlace
    int roundCount = 0;
    int temp = maxPlayers ~/ 2;
    while (temp >= 1) {
      roundCount++;
      temp ~/= 2;
    }

    List<List<Map<String, dynamic>>> roundMatches = List.generate(roundCount + 1, (_) => []);

    bracket.forEach((matchId, matchMap) {
      final m = Map<String, dynamic>.from(matchMap);
      if (matchId == 'Finals') {
        roundMatches[roundCount].add(m);
      } else if (matchId == 'ThirdPlace') {
        // Will place it with Finals
        roundMatches[roundCount].add(m);
      } else {
        int r = m['round'] ?? 1;
        if (r <= roundCount) {
          roundMatches[r - 1].add(m);
        }
      }
    });

    // Sort matches inside each round by matchId to keep symmetric order
    for (var list in roundMatches) {
      list.sort((a, b) => (a['matchId'] ?? '').compareTo(b['matchId'] ?? ''));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(roundMatches.length, (roundIdx) {
          final matches = roundMatches[roundIdx];
          if (matches.isEmpty) return const SizedBox();

          String roundName = "Runda ${roundIdx + 1}";
          if (roundIdx == roundCount - 1) {
            roundName = "Semifinale";
          } else if (roundIdx == roundCount) {
            roundName = "Finalele";
          } else {
            int matchCount = maxPlayers ~/ (2 << roundIdx);
            if (matchCount == 4) {
              roundName = "Sferturi";
            } else if (matchCount == 8) roundName = "Optimi";
            else if (matchCount == 16) roundName = "Șaisprezecimi";
          }

          return Container(
            width: 250,
            margin: const EdgeInsets.only(right: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  roundName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, matchIdx) {
                      final match = matches[matchIdx];
                      final String matchId = match['matchId'] ?? '';
                      final p1 = match['player1'];
                      final p2 = match['player2'];
                      final s1 = match['score1'];
                      final s2 = match['score2'];
                      final bool isCompleted = match['isCompleted'] ?? false;
                      final String? winnerUid = match['winnerUid'];

                      final bool p1Won = isCompleted && winnerUid == p1?['uid'];
                      final bool p2Won = isCompleted && winnerUid == p2?['uid'];

                      // Check if it is clickable by host (both players must be resolved)
                      final bool isClickable = isHost && p1 != null && p2 != null && !isCompleted;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (matchId == 'ThirdPlace')
                              Padding(
                                padding: EdgeInsets.only(bottom: 6.0),
                                child: Text('FINALA MICĂ (Locul 3-4)', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            InkWell(
                              onTap: isClickable
                                  ? () => _showScoreInputDialog(matchId, match, bracket, tourData['joinedPlayers'])
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isClickable 
                                        ? AppColors.accent.withValues(alpha: 0.6) 
                                        : isCompleted 
                                            ? Colors.greenAccent.withValues(alpha: 0.3)
                                            : AppColors.card2,
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    // Player 1
                                    _buildBracketPlayerRow(p1, s1, p1Won, p1 == null && p2 != null),
                                    Divider(color: AppColors.card2, height: 1),
                                    // Player 2
                                    _buildBracketPlayerRow(p2, s2, p2Won, p2 == null && p1 != null),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBracketPlayerRow(dynamic player, int? score, bool isWinner, bool isByeOpponent) {
    if (player == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: Alignment.centerLeft,
        child: Text(
          isByeOpponent ? 'BYE (Liber)' : 'Așteptare...',
          style: TextStyle(color: Colors.grey.withValues(alpha: 0.6), fontStyle: FontStyle.italic, fontSize: 13),
        ),
      );
    }

    final String name = player['username'] ?? 'Player';
    final String level = player['level'] ?? 'Iron I';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isWinner ? Colors.green.withValues(alpha: 0.08) : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: isWinner ? Colors.greenAccent : AppColors.text70,
                    fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                    decoration: (!isWinner && score != null) ? TextDecoration.lineThrough : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  level,
                  style: TextStyle(color: AppColors.muted2, fontSize: 10),
                ),
              ],
            ),
          ),
          if (score != null)
            Text(
              '$score',
              style: TextStyle(
                color: isWinner ? Colors.greenAccent : AppColors.muted,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
        ],
      ),
    );
  }
}
