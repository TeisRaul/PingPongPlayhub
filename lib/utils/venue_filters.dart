import 'package:latlong2/latlong.dart';

import '../data/mock_locations.dart';
import '../l10n/strings.dart';

enum VenueSort { recommended, distance, price, rating }

/// Filtrele și sortarea pentru lista de săli.
class VenueFilters {
  String query;
  double? maxPrice; // RON / oră; null = fără limită
  double? minRating; // 0-5; null = oricare
  bool openNow;
  bool withExtras; // săli cu servicii extra (echipament, bar etc.)
  VenueSort sort;

  VenueFilters({
    this.query = '',
    this.maxPrice,
    this.minRating,
    this.openNow = false,
    this.withExtras = false,
    this.sort = VenueSort.recommended,
  });

  VenueFilters copy() => VenueFilters(
        query: query,
        maxPrice: maxPrice,
        minRating: minRating,
        openNow: openNow,
        withExtras: withExtras,
        sort: sort,
      );

  /// Câte filtre sunt active (sortarea implicită nu contează).
  int get activeCount =>
      (query.trim().isNotEmpty ? 1 : 0) +
      (maxPrice != null ? 1 : 0) +
      (minRating != null ? 1 : 0) +
      (openNow ? 1 : 0) +
      (withExtras ? 1 : 0) +
      (sort != VenueSort.recommended ? 1 : 0);

  bool get isActive => activeCount > 0;
}

const Distance _distance = Distance();

LatLng? venueCoords(PingPongLocation loc) {
  final lat = loc.latitude;
  final lng = loc.longitude;
  if (lat == null || lng == null) return null;
  return LatLng(lat, lng);
}

/// Distanța în km până la sală, sau `null` dacă nu se știe locația utilizatorului sau a sălii.
double? venueDistanceKm(PingPongLocation loc, LatLng? user) {
  final c = venueCoords(loc);
  if (user == null || c == null) return null;
  return _distance.distance(user, c) / 1000;
}

String? venueDistanceLabel(PingPongLocation loc, LatLng? user) {
  final km = venueDistanceKm(loc, user);
  if (km == null) return null;
  if (km < 1) return tr('vf.m', {'n': '${(km * 1000).round()}'});
  return tr('vf.km', {'n': km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0)});
}

/// Aplică filtrele și sortarea; nu modifică lista primită.
List<PingPongLocation> applyVenueFilters(List<PingPongLocation> input, VenueFilters f, LatLng? user) {
  final q = f.query.trim().toLowerCase();
  final now = DateTime.now();
  final out = input.where((loc) {
    if (q.isNotEmpty && !loc.name.toLowerCase().contains(q)) return false;
    if (f.maxPrice != null && loc.pricePerHour > f.maxPrice!) return false;
    if (f.minRating != null && (loc.rating == null || loc.rating! < f.minRating!)) return false;
    if (f.openNow && !loc.isOpenAt(now)) return false;
    if (f.withExtras && loc.extraServices.isEmpty) return false;
    return true;
  }).toList();

  switch (f.sort) {
    case VenueSort.distance:
      out.sort((a, b) {
        final da = venueDistanceKm(a, user);
        final db = venueDistanceKm(b, user);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
      break;
    case VenueSort.price:
      out.sort((a, b) => a.pricePerHour.compareTo(b.pricePerHour));
      break;
    case VenueSort.rating:
      out.sort((a, b) {
        final ra = a.rating ?? -1;
        final rb = b.rating ?? -1;
        final c = rb.compareTo(ra);
        return c != 0 ? c : b.ratingCount.compareTo(a.ratingCount);
      });
      break;
    case VenueSort.recommended:
      break;
  }
  return out;
}
