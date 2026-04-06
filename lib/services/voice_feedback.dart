import 'package:flutter_tts/flutter_tts.dart';

import '../models/health_analysis.dart';

/// Short spoken cues for low-literacy / low-text UX.
class VoiceFeedback {
  VoiceFeedback() : _tts = FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(0.42);
    await _tts.setVolume(1.0);
    _ready = true;
  }

  Future<void> speakStatus(RiskLevel level) async {
    await init();
    final text = switch (level) {
      RiskLevel.low => '현재 상태는 안정적으로 보입니다.',
      RiskLevel.medium => '주의가 필요합니다. 휴식과 수분 섭취를 권장합니다.',
      RiskLevel.high => '위험 신호가 있습니다. 보호자에게 연락하거나 도움을 요청하세요.',
    };
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
