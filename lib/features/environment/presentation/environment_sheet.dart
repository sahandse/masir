import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/environment_service.dart';

class EnvironmentSheet extends StatefulWidget {
  const EnvironmentSheet({
    super.key,
    required this.position,
    required this.title,
  });

  final LatLng position;
  final String title;

  @override
  State<EnvironmentSheet> createState() => _EnvironmentSheetState();
}

class _EnvironmentSheetState extends State<EnvironmentSheet> {
  final _service = EnvironmentService();
  late Future<EnvironmentSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.current(widget.position);
  }

  void _refresh() {
    setState(() => _future = _service.current(widget.position));
  }

  String _temperature(double? value) =>
      value == null ? '—' : '\${value.round()}°';

  String _number(double? value) =>
      value == null ? '—' : value.round().toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: FutureBuilder<EnvironmentSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 260,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 42),
                  const SizedBox(height: 12),
                  const Text('دریافت آب‌وهوا و کیفیت هوا انجام نشد.'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('تلاش دوباره'),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('داده زنده Open-Meteo'),
                  trailing: IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.thermostat_rounded,
                        title: 'دما',
                        value: _temperature(data.temperatureC),
                        subtitle: data.weatherLabel,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.air_rounded,
                        title: 'AQI',
                        value: data.usAqi?.toString() ?? '—',
                        subtitle: data.aqiLabel,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.device_thermostat_outlined,
                        title: 'دمای حسی',
                        value: _temperature(data.apparentTemperatureC),
                        subtitle: 'سانتی‌گراد',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.wind_power_outlined,
                        title: 'باد',
                        value: _number(data.windKmh),
                        subtitle: 'km/h',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'PM2.5: \${data.pm25?.toStringAsFixed(1) ?? '—'} · '
                  'PM10: \${data.pm10?.toStringAsFixed(1) ?? '—'} µg/m³',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(title, style: theme.textTheme.labelMedium),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
