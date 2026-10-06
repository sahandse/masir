import 'dart:async';

import 'package:flutter/material.dart';
import 'package:masir/features/search/data/nominatim_service.dart';
import 'package:masir/core/services/offline_place_cache_service.dart';
import 'package:masir/features/search/models/place_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SearchSheet extends StatefulWidget {
  const SearchSheet({super.key, required this.onSelected});
  final ValueChanged<PlaceResult> onSelected;

  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  final _controller = TextEditingController();
  final _service = NominatimService();
  final _offline = OfflinePlaceCacheService();
  final _speech = SpeechToText();
  List<PlaceResult> _items = const [];
  bool _loading = false;
  String? _error;
  bool _offlineOnly = false;
  bool _listening = false;
  Timer? _debounce;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _speech.stop();
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

  Future<void> _toggleVoiceSearch() async {
    if (_listening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      if (_controller.text.trim().length >= 2) {
        await _submit(unfocus: false);
      }
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _listening = false);
      },
    );

    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جستجوی صوتی روی این دستگاه در دسترس نیست یا اجازه میکروفون داده نشده است.'),
        ),
      );
      return;
    }

    final locales = await _speech.locales();
    String? localeId;
    for (final locale in locales) {
      final id = locale.localeId.toLowerCase();
      if (id.startsWith('fa')) {
        localeId = locale.localeId;
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _listening = true;
      _error = null;
    });

    await _speech.listen(
      localeId: localeId,
      listenMode: ListenMode.search,
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isEmpty || !mounted) return;
        _controller
          ..text = words
          ..selection = TextSelection.collapsed(offset: words.length);
        _onChanged(words);
        if (result.finalResult) {
          setState(() => _listening = false);
          unawaited(_submit(unfocus: false));
        }
      },
    );
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

    final offlineResults = await _offline.search(query);
    try {
      final onlineResults = await _service.search(query);
      unawaited(_offline.merge(onlineResults));
      if (!mounted || currentRequest != _requestId) return;

      final merged = <PlaceResult>[];
      final seen = <String>{};
      for (final item in [...onlineResults, ...offlineResults]) {
        final key =
            '${item.position.latitude.toStringAsFixed(5)},${item.position.longitude.toStringAsFixed(5)}|${item.title.toLowerCase()}';
        if (seen.add(key)) merged.add(item);
      }

      setState(() {
        _items = merged;
        _offlineOnly = false;
      });
    } catch (_) {
      if (!mounted || currentRequest != _requestId) return;
      setState(() {
        _items = offlineResults;
        _offlineOnly = offlineResults.isNotEmpty;
        _error = offlineResults.isEmpty
            ? 'جستجو انجام نشد. اتصال اینترنت را بررسی کنید.'
            : null;
      });
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
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: _listening ? 'توقف شنیدن' : 'جستجوی صوتی فارسی',
                            onPressed: _toggleVoiceSearch,
                            icon: Icon(
                              _listening
                                  ? Icons.mic_rounded
                                  : Icons.mic_none_rounded,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _submit(),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ],
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
              _offlineOnly
                  ? 'نتایج ذخیره‌شده آفلاین از داده واقعی OpenStreetMap'
                  : 'داده مکان: OpenStreetMap / Nominatim',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
