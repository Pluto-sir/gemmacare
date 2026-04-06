import 'dart:convert';

enum RiskLevel {
  low,
  medium,
  high;

  static RiskLevel fromString(String raw) {
    switch (raw.toUpperCase().trim()) {
      case 'HIGH':
        return RiskLevel.high;
      case 'MEDIUM':
        return RiskLevel.medium;
      case 'LOW':
      default:
        return RiskLevel.low;
    }
  }
}

/// Structured output aligned with the Gemma Care spec (JSON).
class HealthAnalysis {
  const HealthAnalysis({
    required this.summary,
    required this.riskLevel,
    required this.reasoning,
    required this.recommendations,
    required this.alertCaregiverSuggested,
  });

  final String summary;
  final RiskLevel riskLevel;
  final String reasoning;
  final List<String> recommendations;
  /// Raw model suggestion; combine with [AlertGate] for event-based alerting.
  final bool alertCaregiverSuggested;

  factory HealthAnalysis.fromJson(Map<String, dynamic> json) {
    final rec = json['recommendations'];
    return HealthAnalysis(
      summary: json['summary']?.toString() ?? '',
      riskLevel: RiskLevel.fromString(json['risk_level']?.toString() ?? 'LOW'),
      reasoning: json['reasoning']?.toString() ?? '',
      recommendations: rec is List
          ? rec.map((e) => e.toString()).toList()
          : const [],
      alertCaregiverSuggested: json['alert_caregiver'] == true,
    );
  }

  static HealthAnalysis? tryParseModelOutput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    var slice = trimmed;
    if (slice.contains('```')) {
      slice = slice.replaceAll(RegExp(r'```(?:json)?'), '').trim();
    }
    final start = slice.indexOf('{');
    final end = slice.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    slice = slice.substring(start, end + 1);
    try {
      final map = jsonDecode(slice) as Map<String, dynamic>;
      return HealthAnalysis.fromJson(map);
    } on Object {
      return null;
    }
  }
}
