import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as geo;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Free OpenFreeMap liberty style — no Google, no paid key.
const kMasirMapStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';


class OfflineRegionInfo {
  const OfflineRegionInfo({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;
}

/// Downloads MapLibre offline regions around a real GPS/map center.
class OfflineMapService {
  static const _metaKey = 'offline_regions_meta_v1';

  Future<List<OfflineRegionInfo>> listRegions() async {
    if (kIsWeb) return const [];
    try {
      final regions = await getListOfRegions();
      return [
        for (final region in regions)
          OfflineRegionInfo(
            id: region.id,
            name: (region.metadata['name'] as String?) ?? 'منطقه ${region.id}',
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Downloads a compact box around [center] for offline use.
  Future<void> downloadAround({
    required geo.LatLng center,
    required String name,
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('آفلاین روی وب پشتیبانی نمی‌شود');
    }

    final definition = OfflineRegionDefinition(
      bounds: LatLngBounds(
        southwest: LatLng(center.latitude - 0.055, center.longitude - 0.07),
        northeast: LatLng(center.latitude + 0.055, center.longitude + 0.07),
      ),
      mapStyleUrl: kMasirMapStyleUrl,
      minZoom: 10,
      maxZoom: 15,
      includeIdeographs: false,
    );

    final region = await downloadOfflineRegion(
      definition,
      metadata: {
        'name': name,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      onEvent: (status) {
        if (status is InProgress) {
          final total = status.requiredResourceCount;
          if (total > 0) {
            onProgress?.call(status.completedResourceCount / total);
          } else if (status.progress > 0) {
            onProgress?.call((status.progress / 100).clamp(0.0, 1.0));
          }
        } else if (status is Error) {
          // Terminal failure is also surfaced by the returned Future in some
          // plugin versions; keep a soft signal for UI.
          onProgress?.call(-1);
        }
      },
    );

    final prefs = await SharedPreferences.getInstance();
    final meta = prefs.getStringList(_metaKey) ?? <String>[];
    meta.removeWhere((row) => row.startsWith('${region.id}|'));
    meta.add('${region.id}|$name');
    await prefs.setStringList(_metaKey, meta);
  }

  Future<void> deleteRegion(int id) async {
    if (kIsWeb) return;
    await deleteOfflineRegion(id);
    final prefs = await SharedPreferences.getInstance();
    final meta = prefs.getStringList(_metaKey) ?? [];
    meta.removeWhere((row) => row.startsWith('$id|'));
    await prefs.setStringList(_metaKey, meta);
  }
}
