import 'dart:async';

import 'package:flutter/material.dart';
import 'package:masir/features/search/data/nominatim_service.dart';
import 'package:masir/features/search/models/place_result.dart';

class SearchSheet extends StatefulWidget {
  const SearchSheet({super.key, required this.onSelected});
  final ValueChanged<PlaceResult> onSelected;

  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  final _controller = TextEditingController();
  final _service = NominatimService();
  List<PlaceResult> _items = const [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _items = const [];
        _error = null;
        _loading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 700), () {
      _submit(unfocus: false);
    });
  }

  Future<void> _submit({bool unfocus = true}) async {
    final query = _controller.text.trim();
    if (query.length < 2) return;
    if (unfocus) FocusScope.of(context).unfocus();

    final currentRequest = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await _service.search(query);
      if (!mounted || currentRequest != _requestId) return;
      setState(() => _items = results);
    } catch (_) {
      if (!mounted || currentRequest != _requestId) return;
      setState(() => _error = 'جستجو انجام نشد. اتصال اینترنت را بررسی کنید.');
    } finally {
      if (mounted && currentRequest == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 10,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'نام مقصد یا آدرس را بنویسید',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: () => _submit(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!),
              ),
            if (!_loading && _items.isEmpty && _controller.text.trim().length >= 2 && _error == null)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('اگر نتیجه‌ای نیست، نام محله یا شهر را هم بنویسید.'),
              ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.place_outlined)),
                    title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onSelected(item);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'داده مکان: OpenStreetMap / Nominatim',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
