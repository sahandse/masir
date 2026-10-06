import 'package:shared_preferences/shared_preferences.dart';

enum TravelMode {
  driving,
  walking,
  cycling;

  String get label => switch (this) {
        TravelMode.driving => 'خودرو',
        TravelMode.walking => 'پیاده',
        TravelMode.cycling => 'دوچرخه',
      };

  String get valhallaCosting => switch (this) {
        TravelMode.driving => 'auto',
        TravelMode.walking => 'pedestrian',
        TravelMode.cycling => 'bicycle',
      };

  static TravelMode fromStorage(String? value) => TravelMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => TravelMode.driving,
      );
}

class NavigationPreferences {
  const NavigationPreferences({
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.avoidFerries = false,
    this.autoZoom = true,
    this.speedWarning = true,
    this.mode = TravelMode.driving,
  });

  final bool avoidTolls;
  final bool avoidHighways;
  final bool avoidFerries;
  final bool autoZoom;
  final bool speedWarning;
  final TravelMode mode;

  NavigationPreferences copyWith({
    bool? avoidTolls,
    bool? avoidHighways,
    bool? avoidFerries,
    bool? autoZoom,
    bool? speedWarning,
    TravelMode? mode,
  }) => NavigationPreferences(
        avoidTolls: avoidTolls ?? this.avoidTolls,
        avoidHighways: avoidHighways ?? this.avoidHighways,
        avoidFerries: avoidFerries ?? this.avoidFerries,
        autoZoom: autoZoom ?? this.autoZoom,
        speedWarning: speedWarning ?? this.speedWarning,
        mode: mode ?? this.mode,
      );
}

class NavigationPreferencesService {
  static const _avoidTolls = 'nav_avoid_tolls';
  static const _avoidHighways = 'nav_avoid_highways';
  static const _avoidFerries = 'nav_avoid_ferries';
  static const _autoZoom = 'nav_auto_zoom';
  static const _speedWarning = 'nav_speed_warning';
  static const _travelMode = 'nav_travel_mode';

  Future<NavigationPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NavigationPreferences(
      avoidTolls: prefs.getBool(_avoidTolls) ?? false,
      avoidHighways: prefs.getBool(_avoidHighways) ?? false,
      avoidFerries: prefs.getBool(_avoidFerries) ?? false,
      autoZoom: prefs.getBool(_autoZoom) ?? true,
      speedWarning: prefs.getBool(_speedWarning) ?? true,
      mode: TravelMode.fromStorage(prefs.getString(_travelMode)),
    );
  }

  Future<void> save(NavigationPreferences value) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool(_avoidTolls, value.avoidTolls),
      prefs.setBool(_avoidHighways, value.avoidHighways),
      prefs.setBool(_avoidFerries, value.avoidFerries),
      prefs.setBool(_autoZoom, value.autoZoom),
      prefs.setBool(_speedWarning, value.speedWarning),
      prefs.setString(_travelMode, value.mode.name),
    ]);
  }
}
