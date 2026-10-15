import 'package:latlong2/latlong.dart';

/// Coordonate pentru reședințele de județ din România (folosite când o sală nu are coordonate proprii).
const Map<String, LatLng> romanianCityCoords = {
  'alba iulia':          LatLng(46.0667,  23.5833),
  'alexandria':          LatLng(43.9764,  25.3358),
  'arad':                LatLng(46.1833,  21.3167),
  'bacău':               LatLng(46.5675,  26.9133),
  'baia mare':           LatLng(47.6567,  23.5683),
  'bistrița':            LatLng(47.1353,  24.4992),
  'botoșani':            LatLng(47.7444,  26.6578),
  'brașov':              LatLng(45.6427,  25.5887),
  'brăila':              LatLng(45.2692,  27.9575),
  'bucurești':           LatLng(44.4268,  26.1025),
  'buzău':               LatLng(45.1500,  26.8167),
  'călărași':            LatLng(44.2019,  27.3328),
  'cluj-napoca':         LatLng(46.7712,  23.6236),
  'constanța':           LatLng(44.1598,  28.6348),
  'craiova':             LatLng(44.3302,  23.7949),
  'deva':                LatLng(45.8869,  22.9008),
  'drobeta-turnu severin': LatLng(44.6261, 22.6567),
  'focșani':             LatLng(45.6989,  27.1872),
  'galați':              LatLng(45.4353,  28.0078),
  'giurgiu':             LatLng(43.9022,  25.9697),
  'iași':                LatLng(47.1585,  27.6014),
  'miercurea ciuc':      LatLng(46.3569,  25.8028),
  'oradea':              LatLng(47.0722,  21.9217),
  'piatra neamț':        LatLng(46.9228,  26.3683),
  'pitești':             LatLng(44.8565,  24.8692),
  'ploiești':            LatLng(44.9356,  26.0225),
  'râmnicu vâlcea':      LatLng(45.0997,  24.3694),
  'reșița':              LatLng(45.2983,  21.8889),
  'satu mare':           LatLng(47.7908,  22.8872),
  'sfântu gheorghe':     LatLng(45.8672,  25.7883),
  'sibiu':               LatLng(45.7983,  24.1256),
  'slatina':             LatLng(44.4308,  24.3647),
  'slobozia':            LatLng(44.5628,  27.3672),
  'suceava':             LatLng(47.6514,  26.2556),
  'târgoviște':          LatLng(44.9275,  25.4575),
  'târgu jiu':           LatLng(45.0333,  23.2833),
  'târgu mureș':         LatLng(46.5500,  24.5667),
  'timișoara':           LatLng(45.7489,  21.2087),
  'tulcea':              LatLng(45.1667,  28.8000),
  'vaslui':              LatLng(46.6333,  27.7333),
  'zalău':               LatLng(47.1833,  23.0500),
};

LatLng? coordsForCity(String? city) {
  if (city == null || city.isEmpty) return null;
  return romanianCityCoords[city.toLowerCase().trim()];
}
