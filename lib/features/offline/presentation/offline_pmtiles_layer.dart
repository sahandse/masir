import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

class OfflinePmTilesLayer extends StatefulWidget {
  const OfflinePmTilesLayer({
    super.key,
    required this.path,
  });

  final String path;

  @override
  State<OfflinePmTilesLayer> createState() => _OfflinePmTilesLayerState();
}

class _OfflinePmTilesLayerState extends State<OfflinePmTilesLayer> {
  late Future<vt.Style> _style;

  @override
  void initState() {
    super.initState();
    _style = _load();
  }

  @override
  void didUpdateWidget(covariant OfflinePmTilesLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _style.then((style) => style.dispose()).ignore();
      _style = _load();
    }
  }

  Future<vt.Style> _load() async {
    final provider = await vt.PmTilesVectorTileProvider.open(
      widget.path,
      logger: const vt.Logger.console(),
    );
    return vt.StyleReader(
      uri: 'asset://assets/map_styles/masir_offline.json',
      logger: const vt.Logger.console(),
      resolveProvider: (id) async =>
          id == 'openmaptiles' ? provider : null,
    ).read();
  }

  @override
  void dispose() {
    _style.then((style) => style.dispose()).ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<vt.Style>(
      future: _style,
      builder: (context, snapshot) {
        final style = snapshot.data;
        if (style != null) {
          return vt.VectorTileLayer(
            theme: style.theme,
            tileProviders: style.providers,
            rasterSources: style.rasterSources,
            sprites: style.sprites,
            diskCacheMaximumSizeInBytes: 0,
            logger: const vt.Logger.console(),
          );
        }

        if (snapshot.hasError) {
          return TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'ir.sahand.masir',
          );
        }

        return const ColoredBox(color: Color(0xFFF6F7F4));
      },
    );
  }
}
