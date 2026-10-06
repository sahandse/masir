# Organic Maps inspired roadmap for Masir 1.2+

Masir remains a Flutter application with its own Persian UI and uses real OpenStreetMap data.

## Already integrated in v1.2 branch

- Driving, walking and cycling route profiles.
- Valhalla costing mapped to auto, pedestrian and bicycle.
- Active navigation sessions remember the selected travel profile.
- Re-routing keeps the same travel profile.
- Real OpenStreetMap city guide using Overpass.
- City guide categories: sights, food, accommodation, services and shopping.
- Existing favorites/history/Home/Work remain local and private.

## Offline map direction

Organic Maps is used as a technical reference for offline architecture. Masir should not redistribute Organic Maps official binary map files or use Organic Maps download servers as a white-label backend.

The intended pipeline is:

1. Download OpenStreetMap PBF extracts from an allowed upstream such as Geofabrik.
2. Build Masir-owned regional offline packages using a reproducible generator pipeline.
3. Publish a Masir region catalog with version, size, checksum and update timestamp.
4. Download only user-selected Iran provinces/regions.
5. Verify checksum before activation.
6. Keep online OSM/Valhalla as fallback when an offline package is unavailable.
7. Add offline search and offline routing incrementally after the renderer/data bridge is stable.

## Attribution

If Organic Maps source code or UI is copied in a later phase, Masir must include the required Organic Maps attribution and notices. OpenStreetMap attribution must remain visible for map/data usage.

References:
- https://github.com/organicmaps/organicmaps
- https://github.com/organicmaps/organicmaps/blob/master/tools/python/maps_generator/README.md
- https://www.openstreetmap.org/copyright
