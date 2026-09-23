import 'package:flutter_tts/flutter_tts.dart';

class VoiceGuidanceService {
  VoiceGuidanceService() {
    _configure();
  }

  final FlutterTts _tts = FlutterTts();
  String? _lastText;
  DateTime? _lastSpokenAt;

  Future<void> _configure() async {
    await _tts.setLanguage('fa-IR');
    await _tts.setSpeechRate(0.44);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(false);
  }

  Future<void> speak(
    String text, {
    bool force = false,
    Duration minimumGap = const Duration(seconds: 4),
  }) async {
    final value = text.trim();
    if (value.isEmpty) return;

    final now = DateTime.now();
    if (!force &&
        _lastText == value &&
        _lastSpokenAt != null &&
        now.difference(_lastSpokenAt!) < minimumGap) {
      return;
    }

    _lastText = value;
    _lastSpokenAt = now;
    await _tts.stop();
    await _tts.speak(value);
  }

  Future<void> announceArrival() => speak('به مقصد رسیدید', force: true);

  Future<void> stop() => _tts.stop();
}
