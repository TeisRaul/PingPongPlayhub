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

const List<PingPongLocation> mockLocations = [
  PingPongLocation(id: 'loc1', city: 'București', name: 'PingPong Arena', openHour: 10, closeHour: 23, numTables: 4, indoorTables: 3, outdoorTables: 1),
  PingPongLocation(id: 'loc2', city: 'București', name: 'Smash Club Vitan', openHour: 12, closeHour: 24, numTables: 8, indoorTables: 6, outdoorTables: 2),
  PingPongLocation(id: 'loc3', city: 'Cluj-Napoca', name: 'Transylvania TT', openHour: 9, closeHour: 21, numTables: 3, indoorTables: 3, outdoorTables: 0),
  PingPongLocation(id: 'loc4', city: 'Timișoara', name: 'Banat PingPong', openHour: 10, closeHour: 22, numTables: 5, indoorTables: 3, outdoorTables: 2),
  PingPongLocation(id: 'loc5', city: 'Brașov', name: 'Mountain Spin', openHour: 11, closeHour: 20, numTables: 2, indoorTables: 1, outdoorTables: 1),
];

