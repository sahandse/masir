import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:masir/core/services/map_feedback_service.dart';

class MapFeedbackSheet extends StatefulWidget {
  const MapFeedbackSheet({
    super.key,
    required this.position,
  });

  final LatLng position;

  @override
  State<MapFeedbackSheet> createState() => _MapFeedbackSheetState();
}

class _MapFeedbackSheetState extends State<MapFeedbackSheet> {
  final _service = MapFeedbackService();
  final _note = TextEditingController();
  MapFeedbackType? _type;
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final type = _type;
    if (type == null || _sending) return;
    setState(() => _sending = true);
    final sent = await _service.submit(
      type: type,
      position: widget.position,
      note: _note.text,
    );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'گزارش اصلاح برای بررسی ارسال شد.'
              : 'گزارش اصلاح روی دستگاه ذخیره شد و بعداً ارسال می‌شود.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 18,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_location_alt_outlined),
              title: Text(
                'اصلاح نقشه',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                'پیشنهاد ابتدا بررسی می‌شود و مستقیماً روی نقشه عمومی اعمال نمی‌شود.',
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in MapFeedbackType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'توضیح بیشتر (اختیاری)',
                hintText: 'مثلاً نام درست مکان یا دلیل بسته بودن مسیر',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _type == null || _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('ارسال برای بررسی'),
            ),
          ],
        ),
      ),
    );
  }
}
