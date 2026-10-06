import 'package:flutter_test/flutter_test.dart';
import 'package:masir/core/services/navigation_preferences_service.dart';
import 'package:masir/core/services/offline_map_catalog_service.dart';

void main() {
  group('TravelMode', () {
    test('maps to Valhalla costing profiles', () {
      expect(TravelMode.driving.valhallaCosting, 'auto');
      expect(TravelMode.walking.valhallaCosting, 'pedestrian');
      expect(TravelMode.cycling.valhallaCosting, 'bicycle');
    });

    test('restores persisted values safely', () {
      expect(TravelMode.fromStorage('walking'), TravelMode.walking);
      expect(TravelMode.fromStorage('cycling'), TravelMode.cycling);
      expect(TravelMode.fromStorage('unknown'), TravelMode.driving);
      expect(TravelMode.fromStorage(null), TravelMode.driving);
    });
  });

  group('OfflineRegion', () {
    test('parses a real catalog entry', () {
      final region = OfflineRegion.fromJson({
        'id': 'iran',
        'title': 'ایران',
        'file_name': 'iran.pmtiles',
        'download_url':
            'https://example.test/releases/download/offline-iran/iran.pmtiles',
        'bytes': 123456,
        'sha256': 'ABCDEF',
        'version': '2026.10',
        'updated_at': '2026-10-06T00:00:00Z',
      });

      expect(region.id, 'iran');
      expect(region.fileName, 'iran.pmtiles');
      expect(region.bytes, 123456);
      expect(region.sha256, 'abcdef');
      expect(region.version, '2026.10');
      expect(region.updatedAt.isUtc, isTrue);
    });
  });
}
