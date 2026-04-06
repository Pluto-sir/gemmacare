import '../models/health_analysis.dart';

/// Event-based alerting: suppresses one-off spikes (alarm fatigue).
class AlertGate {
  AlertGate({this.windowSize = 5});

  final int windowSize;
  final List<RiskLevel> _history = <RiskLevel>[];

  void record(RiskLevel level) {
    _history.add(level);
    while (_history.length > windowSize) {
      _history.removeAt(0);
    }
  }

  void clear() => _history.clear();

  /// Fires only when the model asks for alert **and** recent pattern is sustained.
  bool shouldNotifyCaregiver({required bool modelWantsAlert}) {
    if (!modelWantsAlert) return false;
    if (_history.length < 2) return false;

    final last2 = _history.sublist(_history.length - 2);
    if (last2.every((r) => r == RiskLevel.high)) return true;

    if (_history.length >= 3) {
      final last3 = _history.sublist(_history.length - 3);
      final elevated = last3.every(
        (r) => r == RiskLevel.medium || r == RiskLevel.high,
      );
      if (elevated && last3.any((r) => r == RiskLevel.high)) return true;
      if (last3.every((r) => r == RiskLevel.medium)) return true;
    }

    return false;
  }
}
