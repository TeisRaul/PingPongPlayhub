class PingPongLocation {
  final String id;
  final String city;
  final String name;
  final int openHour; // ex: 10
  final int closeHour; // ex: 22
  final int numTables;
  final int indoorTables;
  final int outdoorTables;
  final double pricePerHour;
  final String pricePerHourText;
  final bool allowHalfHour;
  final String? stripeAccountId;
  final bool offersSubscription;
  final double subscriptionPrice;
  final List<Map<String, dynamic>> extraServices;
  final List<String> supportedSports;
  final bool isPublic;
  final Map<String, dynamic> sportSpecs; // detalii & reguli pe sport (venues.sportSpecs)
  final String venueRules; // reguli generale ale sălii
  final double? rating; // nota medie din recenzii (venues.rating)
  final int ratingCount;
  final double? latitude; // coordonate proprii ale sălii (dacă au fost verificate la înscriere)
  final double? longitude;
  final Map<String, String> schedule; // program: 'Luni-Vineri' / 'Sambata' / 'Duminica' -> '09:00 - 22:00'

  const PingPongLocation({
    required this.id,
    required this.city,
    required this.name,
    required this.openHour,
    required this.closeHour,
    required this.numTables,
    int? indoorTables,
    this.outdoorTables = 0,
    this.pricePerHour = 20.0,
    this.pricePerHourText = '20 RON/oră',
    this.allowHalfHour = false,
    this.stripeAccountId,
    this.offersSubscription = false,
    this.subscriptionPrice = 150.0,
    this.extraServices = const [],
    this.supportedSports = const ['ping_pong'],
    this.isPublic = false,
    this.sportSpecs = const {},
    this.venueRules = '',
    this.rating,
    this.ratingCount = 0,
    this.latitude,
    this.longitude,
    this.schedule = const {},
  }) : indoorTables = indoorTables ?? numTables;

  /// Sala e deschisă la momentul [t]? Dacă programul zilei lipsește sau nu poate fi citit, se consideră deschisă.
  bool isOpenAt(DateTime t) {
    final key = t.weekday == DateTime.saturday ? 'Sambata' : (t.weekday == DateTime.sunday ? 'Duminica' : 'Luni-Vineri');
    final raw = schedule[key];
    int open = openHour;
    int close = closeHour;
    if (raw != null) {
      final parts = raw.split('-');
      if (parts.length == 2) {
        int? toMinutes(String x) {
          final hm = x.trim().split(':');
          final h = int.tryParse(hm.first);
          if (h == null) return null;
          final m = hm.length > 1 ? (int.tryParse(hm[1]) ?? 0) : 0;
          return h * 60 + m;
        }
        final o = toMinutes(parts[0]);
        final c = toMinutes(parts[1]);
        if (o == null || c == null) return true;
        final now = t.hour * 60 + t.minute;
        return now >= o && now < c;
      }
    }
    final nowH = t.hour + t.minute / 60.0;
    return nowH >= open && nowH < close;
  }
}

const List<String> romanianCities = [
  'Alba Iulia',
  'Alexandria',
  'Arad',
  'Bacău',
  'Baia Mare',
  'Bistrița',
  'Botoșani',
  'Brașov',
  'Brăila',
  'București',
  'Buzău',
  'Călărași',
  'Cluj-Napoca',
  'Constanța',
  'Craiova',
  'Deva',
  'Drobeta-Turnu Severin',
  'Focșani',
  'Galați',
  'Giurgiu',
  'Iași',
  'Miercurea Ciuc',
  'Oradea',
  'Piatra Neamț',
  'Pitești',
  'Ploiești',
  'Râmnicu Vâlcea',
  'Reșița',
  'Satu Mare',
  'Sfântu Gheorghe',
  'Sibiu',
  'Slatina',
  'Slobozia',
  'Suceava',
  'Târgoviște',
  'Târgu Jiu',
  'Târgu Mureș',
  'Timișoara',
  'Tulcea',
  'Vaslui',
  'Zalău'
];
