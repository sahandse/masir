import 'package:latlong2/latlong.dart';

class PlaceResult {
  const PlaceResult({required this.title, required this.subtitle, required this.position});
  final String title;
  final String subtitle;
  final LatLng position;
}
