/// Latest metrics pulled from the phone via Health Connect (e.g. Galaxy Watch → Samsung Health).
class WatchHealthReading {
  const WatchHealthReading({
    this.heartRateBpm,
    required this.stepsToday,
    required this.inactiveEstimateMinutes,
    this.lastHeartSampleAt,
    this.hasHeartRateSample = true,
  });

  /// Most recent BPM from Health Connect; null/absent treated as [hasHeartRateSample] == false.
  final int? heartRateBpm;
  final int stepsToday;
  /// Heuristic from low step counts in the last ~90 minutes (not a clinical sedentary score).
  final int inactiveEstimateMinutes;
  final DateTime? lastHeartSampleAt;
  final bool hasHeartRateSample;
}

class WatchSyncResult {
  const WatchSyncResult._({
    required this.ok,
    this.errorMessage,
    this.reading,
  });

  final bool ok;
  final String? errorMessage;
  final WatchHealthReading? reading;

  factory WatchSyncResult.success(WatchHealthReading reading) =>
      WatchSyncResult._(ok: true, reading: reading);

  factory WatchSyncResult.failure(String message) =>
      WatchSyncResult._(ok: false, errorMessage: message);
}
