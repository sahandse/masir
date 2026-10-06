import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class OfflineRegion {
  const OfflineRegion({
    required this.id,
    required this.title,
    required this.fileName,
    required this.downloadUrl,
    required this.bytes,
    required this.sha256,
    required this.version,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String fileName;
  final String downloadUrl;
  final int bytes;
  final String sha256;
  final String version;
  final DateTime updatedAt;

  factory OfflineRegion.fromJson(Map<String, dynamic> json) => OfflineRegion(
        id: json['id'] as String,
        title: json['title'] as String,
        fileName: json['file_name'] as String,
        downloadUrl: json['download_url'] as String,
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        sha256: (json['sha256'] as String? ?? '').toLowerCase(),
        version: json['version'] as String? ?? 'unknown',
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

class OfflineRegionState {
  const OfflineRegionState({
    required this.region,
    required this.file,
    required this.installed,
    required this.updateAvailable,
    required this.active,
  });

  final OfflineRegion region;
  final File file;
  final bool installed;
  final bool updateAvailable;
  final bool active;
}

class OfflineMapCatalogService {
  OfflineMapCatalogService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 12),
                headers: const {
                  'User-Agent': 'MasirNavigation/1.2 (ir.sahand.masir)',
                },
              ),
            );

  final Dio _dio;

  static const catalogUrl = String.fromEnvironment(
    'MASIR_OFFLINE_CATALOG_URL',
    defaultValue:
        'https://raw.githubusercontent.com/sahandse/masir/main/offline/catalog.json',
  );
  static const _activeRegionKey = '__active_region_id';

  bool get isConfigured => catalogUrl.trim().isNotEmpty;

  Future<Directory> _mapsDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/offline_maps');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<OfflineRegionState>> loadCatalog() async {
    if (!isConfigured) return const [];
    final response = await _dio.get<dynamic>(catalogUrl);
    final root = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    final raw = (root as Map<String, dynamic>)['regions'] as List<dynamic>? ??
        const <dynamic>[];
    final regions = raw
        .map((e) => OfflineRegion.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    final dir = await _mapsDirectory();
    final manifest = await _readManifest(dir);
    final activeId = manifest[_activeRegionKey] as String?;
    final states = <OfflineRegionState>[];
    for (final region in regions) {
      final file = File('${dir.path}/${region.fileName}');
      final installed = await file.exists();
      states.add(
        OfflineRegionState(
          region: region,
          file: file,
          installed: installed,
          updateAvailable:
              (manifest[region.id] as Map<String, dynamic>?)?['version'] != null &&
                  (manifest[region.id] as Map<String, dynamic>)['version'] !=
                      region.version,
          active: installed && activeId == region.id,
        ),
      );
    }
    return states;
  }

  Future<void> download(
    OfflineRegion region, {
    required void Function(double progress) onProgress,
  }) async {
    final dir = await _mapsDirectory();
    final target = File('${dir.path}/${region.fileName}');
    final temp = File('${target.path}.download');

    if (await temp.exists()) await temp.delete();

    await _dio.download(
      region.downloadUrl,
      temp.path,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
      options: Options(
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 20),
      ),
    );

    if (region.sha256.isNotEmpty) {
      final digest = await _sha256(temp);
      if (digest.toLowerCase() != region.sha256.toLowerCase()) {
        await temp.delete();
        throw StateError('Checksum mismatch for ${region.id}');
      }
    }

    if (await target.exists()) await target.delete();
    await temp.rename(target.path);

    final manifest = await _readManifest(dir);
    manifest[region.id] = {
      'version': region.version,
      'file_name': region.fileName,
      'installed_at': DateTime.now().toUtc().toIso8601String(),
      'sha256': region.sha256,
    };
    await _writeManifest(dir, manifest);
    onProgress(1);
  }

  Future<void> remove(OfflineRegion region) async {
    final dir = await _mapsDirectory();
    final target = File('${dir.path}/${region.fileName}');
    if (await target.exists()) await target.delete();
    final manifest = await _readManifest(dir);
    manifest.remove(region.id);
    if (manifest[_activeRegionKey] == region.id) {
      manifest.remove(_activeRegionKey);
    }
    await _writeManifest(dir, manifest);
  }

  Future<void> setActive(OfflineRegion region) async {
    final dir = await _mapsDirectory();
    final target = File('${dir.path}/${region.fileName}');
    if (!await target.exists()) {
      throw StateError('Offline map is not installed: ${region.id}');
    }
    final manifest = await _readManifest(dir);
    manifest[_activeRegionKey] = region.id;
    await _writeManifest(dir, manifest);
  }

  Future<String?> activeMapPath() async {
    final dir = await _mapsDirectory();
    final manifest = await _readManifest(dir);
    final activeId = manifest[_activeRegionKey] as String?;
    if (activeId == null || activeId.isEmpty) return null;

    final value = manifest[activeId];
    if (value is! Map<String, dynamic>) return null;
    final fileName = value['file_name'] as String?;
    if (fileName == null || fileName.isEmpty) return null;

    final file = File('${dir.path}/$fileName');
    return await file.exists() ? file.path : null;
  }

  Future<void> clearActive() async {
    final dir = await _mapsDirectory();
    final manifest = await _readManifest(dir);
    manifest.remove(_activeRegionKey);
    await _writeManifest(dir, manifest);
  }

  Future<Map<String, dynamic>> _readManifest(Directory dir) async {
    final file = File('${dir.path}/manifest.json');
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final data = jsonDecode(await file.readAsString());
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeManifest(
    Directory dir,
    Map<String, dynamic> manifest,
  ) async {
    final file = File('${dir.path}/manifest.json');
    await file.writeAsString(jsonEncode(manifest), flush: true);
  }

  Future<String> _sha256(File file) async {
    final sink = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return sink.events.single.toString();
  }
}
