import 'dart:io' show Platform;

import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/watch_health_reading.dart';

/// Reads Galaxy Watch / Samsung Health data that has been shared to [Health Connect].
class WatchHealthService {
  final Health _health = Health();

  static int _inactiveFromStepsWindow(int stepsLast90m) {
    if (stepsLast90m <= 0) return 75;
    if (stepsLast90m >= 500) return 5;
    return (75 * (1 - stepsLast90m / 500)).round().clamp(5, 75);
  }

  Future<WatchSyncResult> syncFromPhoneHealth() async {
    if (!Platform.isAndroid) {
      return WatchSyncResult.failure(
        'Health Connect는 Android에서만 사용됩니다.',
      );
    }

    await _health.configure();

    final hcOk = await _health.isHealthConnectAvailable();
    if (!hcOk) {
      return WatchSyncResult.failure(
        'Health Connect를 사용할 수 없습니다. 앱을 설치·업데이트한 뒤, '
        '삼성 헬스 설정에서 Health Connect로 심박·활동 데이터를 공유해 주세요.',
      );
    }

    final ar = await Permission.activityRecognition.request();
    if (!ar.isGranted) {
      return WatchSyncResult.failure(
        '걸음 수를 읽으려면「신체 활동」권한이 필요합니다.',
      );
    }

    final types = <HealthDataType>[
      HealthDataType.HEART_RATE,
      HealthDataType.STEPS,
    ];
    final granted = await _health.requestAuthorization(
      types,
      permissions: const [
        HealthDataAccess.READ,
        HealthDataAccess.READ,
      ],
    );
    if (!granted) {
      return WatchSyncResult.failure(
        'Health Connect에서 이 앱에 심박·걸음「읽기」권한을 허용해 주세요.',
      );
    }

    final now = DateTime.now();
    final startDay = DateTime(now.year, now.month, now.day);
    final windowStart = now.subtract(const Duration(minutes: 90));
    final hrStart = now.subtract(const Duration(hours: 12));

    final stepsToday = await _health.getTotalStepsInInterval(startDay, now) ?? 0;
    final steps90 = await _health.getTotalStepsInInterval(windowStart, now) ?? 0;

    final hrPoints = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.HEART_RATE],
      startTime: hrStart,
      endTime: now,
    );

    HealthDataPoint? latest;
    for (final p in hrPoints) {
      if (p.type != HealthDataType.HEART_RATE) continue;
      if (p.value is! NumericHealthValue) continue;
      if (latest == null || p.dateTo.isAfter(latest.dateTo)) {
        latest = p;
      }
    }

    int? bpm;
    DateTime? lastAt;
    var hasHr = false;
    if (latest != null) {
      bpm = (latest.value as NumericHealthValue).numericValue.round();
      lastAt = latest.dateTo;
      hasHr = true;
    }

    return WatchSyncResult.success(
      WatchHealthReading(
        heartRateBpm: bpm,
        stepsToday: stepsToday,
        inactiveEstimateMinutes: _inactiveFromStepsWindow(steps90),
        lastHeartSampleAt: lastAt,
        hasHeartRateSample: hasHr,
      ),
    );
  }
}
