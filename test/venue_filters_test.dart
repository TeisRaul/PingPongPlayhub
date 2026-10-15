import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pingpong_playhub/data/mock_locations.dart';
import 'package:pingpong_playhub/utils/venue_filters.dart';

PingPongLocation _loc(
  String id,
  String name, {
  double price = 20,
  double? rating,
  int ratingCount = 0,
  double? lat,
  double? lng,
  List<Map<String, dynamic>> extras = const [],
}) =>
    PingPongLocation(
      id: id,
      city: 'București',
      name: name,
      openHour: 0,
      closeHour: 24,
      numTables: 2,
      pricePerHour: price,
      rating: rating,
      ratingCount: ratingCount,
      latitude: lat,
      longitude: lng,
      extraServices: extras,
    );

void main() {
  final venues = [
    _loc('a', 'Arena Centru', price: 40, rating: 4.8, ratingCount: 30, lat: 44.43, lng: 26.10),
    _loc('b', 'Club Sport Cluj', price: 25, rating: 4.2, ratingCount: 10, lat: 46.77, lng: 23.59),
    _loc('c', 'Ping Pong Nou', price: 15, extras: [
      {'name': 'Rachete', 'price': 5},
    ]),
    _loc('d', 'Sala Veche', price: 30, rating: 3.1, ratingCount: 4, lat: 45.75, lng: 21.23),
  ];
  final bucharest = LatLng(44.4268, 26.1025);

  List<String> ids(List<PingPongLocation> l) => l.map((e) => e.id).toList();

  group('applyVenueFilters', () {
    test('fără filtre: aceeași listă, aceeași ordine', () {
      expect(ids(applyVenueFilters(venues, VenueFilters(), null)), ['a', 'b', 'c', 'd']);
    });

    test('căutare după nume, fără diferență între majuscule', () {
      expect(ids(applyVenueFilters(venues, VenueFilters(query: ' ping '), null)), ['c']);
    });

    test('preț maxim pe oră (limita inclusă)', () {
      expect(ids(applyVenueFilters(venues, VenueFilters(maxPrice: 30), null)), ['b', 'c', 'd']);
    });

    test('rating minim: sălile fără rating dispar', () {
      expect(ids(applyVenueFilters(venues, VenueFilters(minRating: 4), null)), ['a', 'b']);
    });

    test('doar săli cu servicii extra', () {
      expect(ids(applyVenueFilters(venues, VenueFilters(withExtras: true), null)), ['c']);
    });

    test('filtre combinate', () {
      final f = VenueFilters(maxPrice: 35, minRating: 4);
      expect(ids(applyVenueFilters(venues, f, null)), ['b']);
    });

    test('sortare după preț', () {
      expect(ids(applyVenueFilters(venues, VenueFilters(sort: VenueSort.price), null)), ['c', 'b', 'd', 'a']);
    });

    test('sortare după rating (fără rating la sfârșit)', () {
      expect(ids(applyVenueFilters(venues, VenueFilters(sort: VenueSort.rating), null)), ['a', 'b', 'd', 'c']);
    });

    test('sortare după distanță: sălile fără coordonate la sfârșit', () {
      final r = applyVenueFilters(venues, VenueFilters(sort: VenueSort.distance), bucharest);
      expect(ids(r), ['a', 'b', 'd', 'c']); // București, Cluj (~325 km), Timișoara (~530 km), necunoscut
    });

    test('sortare după distanță fără locația utilizatorului nu strică lista', () {
      final r = applyVenueFilters(venues, VenueFilters(sort: VenueSort.distance), null);
      expect(r.length, 4);
    });

    test('nu modifică lista primită', () {
      final copy = List<PingPongLocation>.from(venues);
      applyVenueFilters(venues, VenueFilters(sort: VenueSort.price), null);
      expect(ids(venues), ids(copy));
    });
  });

  group('VenueFilters', () {
    test('activeCount / isActive', () {
      expect(VenueFilters().isActive, isFalse);
      final f = VenueFilters(query: 'x', maxPrice: 20, openNow: true, sort: VenueSort.price);
      expect(f.activeCount, 4);
      expect(f.isActive, isTrue);
    });

    test('copy e independentă de original', () {
      final f = VenueFilters(maxPrice: 20);
      final c = f.copy()..maxPrice = 50;
      expect(f.maxPrice, 20);
      expect(c.maxPrice, 50);
    });
  });

  group('venueDistanceKm', () {
    test('București – Cluj ≈ 325 km în linie dreaptă', () {
      final km = venueDistanceKm(venues[1], bucharest)!;
      expect(km, inInclusiveRange(300, 350));
    });

    test('null când lipsesc coordonatele sau locația utilizatorului', () {
      expect(venueDistanceKm(venues[2], bucharest), isNull);
      expect(venueDistanceKm(venues[0], null), isNull);
    });
  });
}
