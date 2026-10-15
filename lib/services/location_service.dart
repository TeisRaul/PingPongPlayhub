import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Locația aproximativă a utilizatorului (pentru sortarea sălilor după distanță).
/// Se cere doar când utilizatorul alege sortarea după distanță sau apasă „locația mea” pe hartă.
class LocationService {
  LocationService._();

  static LatLng? _last;
  static DateTime? _lastAt;

  /// Ultima locație aflată în această sesiune (fără a cere ceva).
  static LatLng? get lastKnown => _last;

  /// Locația curentă sau `null` dacă serviciul e oprit ori accesul a fost refuzat.
  static Future<LatLng?> current({bool forceRefresh = false}) async {
    final at = _lastAt;
    if (!forceRefresh && _last != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 5)) {
      return _last;
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 12)),
      );
      _last = LatLng(pos.latitude, pos.longitude);
      _lastAt = DateTime.now();
      return _last;
    } catch (_) {
      return null;
    }
  }
}
