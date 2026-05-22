class PingPongLocation {
  final String id;
  final String city;
  final String name;
  final int openHour; // ex: 10
  final int closeHour; // ex: 22
  final int numTables;
  final double pricePerHour;
  final String pricePerHourText;

  const PingPongLocation({
    required this.id,
    required this.city,
    required this.name,
    required this.openHour,
    required this.closeHour,
    required this.numTables,
    this.pricePerHour = 20.0,
    this.pricePerHourText = '20 RON/oră',
  });
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
  PingPongLocation(id: 'loc1', city: 'București', name: 'PingPong Arena', openHour: 10, closeHour: 23, numTables: 4),
  PingPongLocation(id: 'loc2', city: 'București', name: 'Smash Club Vitan', openHour: 12, closeHour: 24, numTables: 8),
  PingPongLocation(id: 'loc3', city: 'Cluj-Napoca', name: 'Transylvania TT', openHour: 9, closeHour: 21, numTables: 3),
  PingPongLocation(id: 'loc4', city: 'Timișoara', name: 'Banat PingPong', openHour: 10, closeHour: 22, numTables: 5),
  PingPongLocation(id: 'loc5', city: 'Brașov', name: 'Mountain Spin', openHour: 11, closeHour: 20, numTables: 2),
];
