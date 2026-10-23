import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/report_service.dart';

IconData roadReportIcon(RoadReportType type) => switch (type) {
      RoadReportType.traffic => Icons.traffic_rounded,
      RoadReportType.accident => Icons.car_crash_outlined,
      RoadReportType.police => Icons.local_police_outlined,
      RoadReportType.camera => Icons.videocam_outlined,
      RoadReportType.speedBump => Icons.speed_rounded,
      RoadReportType.closure => Icons.block_rounded,
      RoadReportType.roadwork => Icons.construction_rounded,
      RoadReportType.hazard => Icons.warning_amber_rounded,
    };

String reportAgeLabel(DateTime createdAt) {
  final diff = DateTime.now().toUtc().difference(createdAt.toUtc());
  if (diff.inMinutes < 1) return 'همین حالا';
  if (diff.inMinutes < 60) return '${diff.inMinutes} دقیقه پیش';
  if (diff.inHours < 24) return '${diff.inHours} ساعت پیش';
  return '${diff.inDays} روز پیش';
}

String reportDistanceLabel(double meters) {
  if (meters < 1000) return '${meters.round()} متر';
  return '${(meters / 1000).toStringAsFixed(1)} کیلومتر';
}

Future<RoadReportType?> showQuickReportSheet(
  BuildContext context, {
  required LatLng position,
  required bool configured,
}) {
  return showModalBottomSheet<RoadReportType>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'چه اتفاقی افتاده؟',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'گزارش در موقعیت فعلی شما ثبت می‌شود.',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 14),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 8,
              childAspectRatio: 0.92,
              children: [
                for (final type in RoadReportType.values)
                  _QuickReportTile(
                    type: type,
                    onTap: () => Navigator.of(sheetContext).pop(type),
                  ),
              ],
            ),
            if (!configured) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 15,
                    color: Theme.of(sheetContext).colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'حالت محلی: گزارش روی دستگاه ذخیره می‌شود و پس از اتصال سرور ارسال می‌شود.',
                      textAlign: TextAlign.center,
                      style: Theme.of(sheetContext).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _QuickReportTile extends StatelessWidget {
  const _QuickReportTile({
    required this.type,
    required this.onTap,
  });

  final RoadReportType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              roadReportIcon(type),
              size: 25,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            type.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class ReportVoteOutcome {
  const ReportVoteOutcome({
    required this.confirm,
    required this.result,
  });

  final bool confirm;
  final ReportVoteResult result;
}

Future<ReportVoteOutcome?> showReportDetailsSheet(
  BuildContext context, {
  required RoadReport report,
  required ReportService service,
}) {
  return showModalBottomSheet<ReportVoteOutcome>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ReportDetailsSheet(report: report, service: service),
  );
}

class _ReportDetailsSheet extends StatefulWidget {
  const _ReportDetailsSheet({
    required this.report,
    required this.service,
  });

  final RoadReport report;
  final ReportService service;

  @override
  State<_ReportDetailsSheet> createState() => _ReportDetailsSheetState();
}

class _ReportDetailsSheetState extends State<_ReportDetailsSheet> {
  bool _busy = false;

  Future<void> _vote({required bool confirm}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = confirm
        ? await widget.service.confirm(widget.report.id)
        : await widget.service.deny(widget.report.id);
    if (!mounted) return;
    Navigator.of(context).pop(ReportVoteOutcome(confirm: confirm, result: result));
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final scheme = Theme.of(context).colorScheme;
    final details = [
      reportAgeLabel(report.createdAt),
      if (report.confirmations > 0) '${report.confirmations} تأیید',
      if (report.denies > 0) '${report.denies} تکذیب',
    ].join(' · ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.secondaryContainer,
                  child: Icon(
                    roadReportIcon(report.type),
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              report.type.label,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (report.verified) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.verified_rounded,
                              size: 18,
                              color: scheme.primary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(details),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.service.isConfigured) ...[
              const Text(
                'آیا این گزارش هنوز در مسیر وجود دارد؟',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _vote(confirm: false),
                      icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
                      label: const Text('رفع شد'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _vote(confirm: true),
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.thumb_up_alt_outlined, size: 18),
                      label: const Text('هنوز هست'),
                    ),
                  ),
                ],
              ),
            ] else
              Text(
                'تأیید و تکذیب گزارش‌های دیگران با اتصال سرور جامعه فعال می‌شود.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
