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
  }) : indoorTables = indoorTables ?? numTables;
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
