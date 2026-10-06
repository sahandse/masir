import 'package:flutter/material.dart';
import 'package:masir/core/services/offline_map_catalog_service.dart';

class OfflineMapsSheet extends StatefulWidget {
  const OfflineMapsSheet({super.key});

  @override
  State<OfflineMapsSheet> createState() => _OfflineMapsSheetState();
}

class _OfflineMapsSheetState extends State<OfflineMapsSheet> {
  final _service = OfflineMapCatalogService();
  Future<List<OfflineRegionState>>? _future;
  final Map<String, double> _progress = {};
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _service.loadCatalog();
    });
  }

  String _size(int bytes) {
    if (bytes <= 0) return 'حجم نامشخص';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }

  String _date(DateTime value) {
    if (value.millisecondsSinceEpoch == 0) return 'تاریخ نامشخص';
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  Future<void> _download(OfflineRegion region) async {
    setState(() {
      _busy.add(region.id);
      _progress[region.id] = 0;
    });
    try {
      await _service.download(
        region,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress[region.id] = value.clamp(0, 1));
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('نقشه ${region.title} دانلود و بررسی شد.')),
      );
      _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('دانلود یا بررسی فایل نقشه انجام نشد.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(region.id);
          _progress.remove(region.id);
        });
      }
    }
  }

  Future<void> _activate(OfflineRegion region) async {
    try {
      await _service.setActive(region);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('نقشه ${region.title} فعال شد.')),
      );
      _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فعال‌سازی نقشه آفلاین انجام نشد.')),
      );
    }
  }

  Future<void> _useOnlineMap() async {
    await _service.clearActive();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('نقشه آنلاین فعال شد.')),
    );
    _reload();
  }

  Future<void> _remove(OfflineRegion region) async {
    await _service.remove(region);
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_service.isConfigured) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.offline_pin_outlined,
                size: 42,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'نقشه‌های آفلاین',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Catalog نقشه‌های آفلاین هنوز برای این Build تنظیم نشده است. '
                'این بخش فقط فایل واقعی با checksum معتبر را فعال می‌کند و داده نمایشی ندارد.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: FutureBuilder<List<OfflineRegionState>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'دریافت فهرست نقشه‌های آفلاین انجام نشد.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final items = snapshot.data ?? const <OfflineRegionState>[];
            return Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.download_for_offline_outlined),
                  title: Text(
                    'نقشه‌های آفلاین',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'دانلود منطقه، بررسی SHA-256 و بروزرسانی نسخه',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.public_rounded),
                      title: const Text('نقشه آنلاین'),
                      subtitle: const Text('OpenStreetMap با اتصال اینترنت'),
                      trailing: items.any((e) => e.active)
                          ? TextButton(
                              onPressed: _useOnlineMap,
                              child: const Text('فعال کن'),
                            )
                          : const Chip(
                              avatar: Icon(Icons.check_rounded, size: 16),
                              label: Text('فعال'),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.map_outlined,
                                  size: 46,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'هنوز بسته آفلاین منتشر نشده است.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'به محض انتشار بسته واقعی OSM، همین‌جا نمایش داده می‌شود.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final state = items[index];
                            final region = state.region;
                            final busy = _busy.contains(region.id);
                            final progress = _progress[region.id];

                            return ListTile(
                              leading: Icon(
                                state.active
                                    ? Icons.offline_pin_rounded
                                    : state.installed
                                        ? Icons.download_done_rounded
                                        : Icons.map_outlined,
                              ),
                              title: Text(region.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'نسخه ${region.version} · ${_size(region.bytes)} · ${_date(region.updatedAt)}'
                                    '${state.active ? ' · فعال' : ''}'
                                    '${state.updateAvailable ? ' · بروزرسانی موجود' : ''}',
                                  ),
                                  if (busy && progress != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: LinearProgressIndicator(
                                        value: progress > 0 ? progress : null,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: busy
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'download') {
                                          _download(region);
                                        } else if (value == 'activate') {
                                          _activate(region);
                                        } else if (value == 'remove') {
                                          _remove(region);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'download',
                                          child: Text(
                                            state.installed
                                                ? 'دانلود دوباره / بروزرسانی'
                                                : 'دانلود',
                                          ),
                                        ),
                                        if (state.installed && !state.active)
                                          const PopupMenuItem(
                                            value: 'activate',
                                            child: Text('استفاده روی نقشه'),
                                          ),
                                        if (state.installed)
                                          const PopupMenuItem(
                                            value: 'remove',
                                            child: Text('حذف نقشه'),
                                          ),
                                      ],
                                    ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'فقط بسته‌های منتشرشده توسط Masir و ساخته‌شده از داده OSM فعال می‌شوند.',
                    style: theme.textTheme.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
