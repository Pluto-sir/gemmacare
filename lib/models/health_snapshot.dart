/// Single point-in-time inputs for edge analysis (wearable + optional memo).
class HealthSnapshot {
  const HealthSnapshot({
    required this.heartRateBpm,
    required this.activitySteps,
    required this.inactiveMinutes,
    this.userNote = '',
    this.capturedAt,
    this.dataSourceLabel,
    this.heartRateMeasured = true,
  });

  final int heartRateBpm;
  final int activitySteps;
  final int inactiveMinutes;
  final String userNote;
  final DateTime? capturedAt;
  /// e.g. "Health Connect (삼성 헬스·워치 동기화)" vs null for manual sliders.
  final String? dataSourceLabel;
  final bool heartRateMeasured;

  String toPromptBlock() {
    final t = capturedAt ?? DateTime.now();
    final note = userNote.trim().isEmpty ? '(없음)' : userNote.trim();
    final src = dataSourceLabel ?? '수동 입력(앱 슬라이더)';
    final hrLine = heartRateMeasured
        ? '심박수: $heartRateBpm BPM'
        : '심박수: 최근 측정값 없음 (Health Connect에 기록된 심박이 없습니다)';
    return '''
측정 시각: ${t.toIso8601String()}
데이터 출처: $src
$hrLine
오늘 활동(걸음 수 추정): $activitySteps
최근 비활동 추정: $inactiveMinutes분 (최근 90분 걸음 수 기반 추정)
사용자 메모: $note
''';
  }
}
