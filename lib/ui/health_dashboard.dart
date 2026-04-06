import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/health_analysis.dart';
import '../models/health_snapshot.dart';
import '../services/alert_gate.dart';
import '../services/bundled_model_path.dart';
import '../services/llama_analysis_service.dart';
import '../services/voice_feedback.dart';
import '../services/watch_health_service.dart';

String _formatLlamaPlatformError(Object e) {
  final s = e.toString();
  final isChannel =
      e is PlatformException && e.code == 'channel-error' ||
          s.contains('LlamaHostApi') ||
          s.contains('llama_flutter_android.LlamaHostApi') ||
          s.contains('Unable to establish connection on channel');
  if (isChannel) {
    return '이 실행 환경에서는 AI 모델(llama)을 연결할 수 없습니다.\n\n'
        '「llama_flutter_android」는 ARM64(실제 갤럭시 등 폰)용 라이브러리만 포함합니다. '
        '이름에 x86_64가 있는 PC 에뮬레이터에서는 동작하지 않습니다.\n\n'
        '→ 실제 안드로이드 폰을 USB로 연결해 실행하거나, '
        'ARM64 안드로이드 이미지 에뮬레이터를 사용해 주세요.';
  }
  return s;
}

enum _AiPhase {
  idle,
  /// Desktop / non-Android: no bundled model.
  skipped,
  unpacking,
  loadingWeights,
  ready,
  failed,
}

class HealthDashboard extends StatefulWidget {
  const HealthDashboard({super.key});

  @override
  State<HealthDashboard> createState() => _HealthDashboardState();
}

class _HealthDashboardState extends State<HealthDashboard> {
  final _llama = LlamaAnalysisService();
  final _alertGate = AlertGate();
  final _voice = VoiceFeedback();
  final _watchHealth = WatchHealthService();

  final _noteController = TextEditingController();

  int _heartRate = 78;
  int _steps = 1200;
  int _inactiveMinutes = 45;
  bool _syncedFromWatch = false;
  bool _hasWatchHeartRate = true;
  bool _syncingWatch = false;
  String? _watchHint;
  bool _watchHintPositive = false;

  _AiPhase _aiPhase = _AiPhase.idle;
  double _loadProgress = 0;
  bool _analyzing = false;
  String? _error;

  HealthAnalysis? _lastAnalysis;
  bool _caregiverNotified = false;

  bool get _aiReady => _aiPhase == _AiPhase.ready;

  bool get _canRunCheck =>
      _aiReady && !_analyzing && !_syncingWatch && !_isAiPreparing;

  bool get _isAiPreparing =>
      _aiPhase == _AiPhase.unpacking || _aiPhase == _AiPhase.loadingWeights;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Platform.isAndroid) {
        _bootstrapBundledModel();
      } else {
        setState(() => _aiPhase = _AiPhase.skipped);
      }
    });
  }

  Future<void> _bootstrapBundledModel() async {
    setState(() {
      _aiPhase = _AiPhase.unpacking;
      _error = null;
    });
    try {
      final path = await prepareBundledGemmaModelPath();
      if (!mounted) return;
      setState(() {
        _aiPhase = _AiPhase.loadingWeights;
        _loadProgress = 0;
      });

      late final StreamSubscription<double> sub;
      sub = _llama.loadProgress.listen((p) {
        if (mounted) setState(() => _loadProgress = p);
      });

      await _llama.loadModel(modelPath: path);
      await sub.cancel();

      if (mounted) {
        setState(() {
          _aiPhase = _AiPhase.ready;
          _loadProgress = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiPhase = _AiPhase.failed;
          _error = _formatLlamaPlatformError(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    unawaited(_llama.dispose());
    super.dispose();
  }

  Future<void> _pullFromWatch() async {
    setState(() {
      _syncingWatch = true;
      _watchHint = null;
      _watchHintPositive = false;
    });
    final result = await _watchHealth.syncFromPhoneHealth();
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _syncingWatch = false;
        _watchHint = result.errorMessage;
        _watchHintPositive = false;
      });
      return;
    }
    final r = result.reading!;
    setState(() {
      _syncingWatch = false;
      _syncedFromWatch = true;
      _hasWatchHeartRate = r.hasHeartRateSample;
      _heartRate = r.heartRateBpm ?? 0;
      _steps = r.stepsToday;
      _inactiveMinutes = r.inactiveEstimateMinutes;
      final t = r.lastHeartSampleAt;
      _watchHintPositive = true;
      _watchHint = t != null
          ? '손목 시계 기준 시각 ${_formatTime(t)}에 맞춰 왔어요.'
          : '심박 기록은 없고, 걸음 수만 가져왔어요.';
    });
  }

  String _formatTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}시 ${two(d.minute)}분';
  }

  void _onManualAdjust() {
    setState(() => _syncedFromWatch = false);
  }

  Future<void> _runAnalysis() async {
    if (!_aiReady) return;
    setState(() {
      _analyzing = true;
      _caregiverNotified = false;
    });

    final snapshot = HealthSnapshot(
      heartRateBpm: _heartRate,
      activitySteps: _steps,
      inactiveMinutes: _inactiveMinutes,
      userNote: _noteController.text,
      dataSourceLabel: _syncedFromWatch
          ? 'Health Connect (삼성 헬스·갤럭시 워치 동기화)'
          : null,
      heartRateMeasured: !_syncedFromWatch || _hasWatchHeartRate,
    );

    try {
      final raw = await _llama.analyzeSnapshot(snapshot);
      final parsed = HealthAnalysis.tryParseModelOutput(raw);
      if (!mounted) return;
      if (parsed == null) {
        setState(() {
          _error = '결과를 읽지 못했습니다. 한 번 더 눌러 주세요.';
        });
        return;
      }

      _alertGate.record(parsed.riskLevel);
      final notify = _alertGate.shouldNotifyCaregiver(
        modelWantsAlert: parsed.alertCaregiverSuggested,
      );

      setState(() {
        _lastAnalysis = parsed;
        _caregiverNotified = notify;
        _error = null;
      });

      if (notify) {
        _showCaregiverSimulation();
      }
      unawaited(_voice.speakStatus(parsed.riskLevel));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              '확인 중 문제가 생겼어요. 잠시 후 다시 눌러 주세요.\n${_formatLlamaPlatformError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _showCaregiverSimulation() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          '가족에게 알림을 보냈어요. (시험)',
          style: TextStyle(fontSize: 18),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  Color _riskColor(RiskLevel? level) {
    return switch (level) {
      null => Colors.blueGrey,
      RiskLevel.low => const Color(0xFF1B5E20),
      RiskLevel.medium => const Color(0xFFE65100),
      RiskLevel.high => const Color(0xFFB71C1C),
    };
  }

  Color _heartColor(int bpm) {
    if (bpm < 60 || bpm > 110) return const Color(0xFFB71C1C);
    if (bpm < 70 || bpm > 95) return const Color(0xFFE65100);
    return const Color(0xFF2E7D32);
  }

  String _riskWord(RiskLevel? level) {
    return switch (level) {
      null => '기다리는 중',
      RiskLevel.low => '괜찮아요',
      RiskLevel.medium => '조금 주의',
      RiskLevel.high => '위험할 수 있어요',
    };
  }

  @override
  Widget build(BuildContext context) {
    final level = _lastAnalysis?.riskLevel;
    final accent = _riskColor(level);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemma Care'),
      ),
      body: Column(
        children: [
          if (_isAiPreparing) _AiPreparingBanner(phase: _aiPhase, progress: _loadProgress),
          if (_aiPhase == _AiPhase.failed)
            _AiFailedBanner(
              message: _error ?? '모델을 준비하지 못했습니다.',
              onRetry: _bootstrapBundledModel,
            ),
          if (_aiPhase == _AiPhase.skipped)
            Material(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '이 화면은 안드로이드 휴대폰에서만 AI 확인을 할 수 있어요.',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                Center(
                  child: Semantics(
                    label: '오늘 상태 ${_riskWord(level)}',
                    child: Column(
                      children: [
                        Container(
                          width: 168,
                          height: 168,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.15),
                            border: Border.all(color: accent, width: 10),
                          ),
                          child: Icon(
                            Icons.favorite_rounded,
                            size: 72,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _riskWord(level),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineLarge?.copyWith(
                            color: accent,
                            fontSize: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_lastAnalysis != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 54),
                    ),
                    onPressed: () => _voice.speakStatus(_lastAnalysis!.riskLevel),
                    icon: const Icon(Icons.volume_up_rounded, size: 28),
                    label: const Text('큰 소리로 듣기'),
                  ),
                ],
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('손목 시계', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text(
                          '워치에서 재는 심박·걸음은 삼성 헬스로 옵니다. '
                          '삼성 헬스에서 Health Connect 공유를 켜 주세요.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _syncingWatch || _isAiPreparing || _analyzing
                              ? null
                              : _pullFromWatch,
                          icon: _syncingWatch
                              ? const SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                )
                              : const Icon(Icons.watch_rounded, size: 30),
                          label: Text(
                            _syncingWatch ? '가져오는 중…' : '시계 숫자 가져오기',
                          ),
                        ),
                        if (_watchHint != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _watchHint!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _watchHintPositive
                                  ? const Color(0xFF1B5E20)
                                  : const Color(0xFFE65100),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('지금 숫자', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          _syncedFromWatch ? '시계에서 가져온 값' : '아래에서 직접 맞춘 값',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _MetricTile(
                                label: '심박',
                                value: (!_hasWatchHeartRate && _syncedFromWatch)
                                    ? '—'
                                    : '$_heartRate',
                                unit: (!_hasWatchHeartRate && _syncedFromWatch)
                                    ? ''
                                    : 'BPM',
                                color: (!_hasWatchHeartRate && _syncedFromWatch)
                                    ? Colors.black45
                                    : _heartColor(_heartRate),
                              ),
                            ),
                            Expanded(
                              child: _MetricTile(
                                label: '오늘 걸음',
                                value: '$_steps',
                                unit: '걸음',
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Expanded(
                              child: _MetricTile(
                                label: '쉼(추정)',
                                value: '$_inactiveMinutes',
                                unit: '분',
                                color: const Color(0xFF6A1B9A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Theme(
                          data: theme.copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              '숫자를 직접 바꾸기',
                              style: theme.textTheme.titleMedium,
                            ),
                            subtitle: Text(
                              '시계 없을 때·가족이 대신 넣을 때',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.black54,
                              ),
                            ),
                            children: [
                              const SizedBox(height: 8),
                              Text('심박 $_heartRate', style: theme.textTheme.bodyLarge),
                              Slider(
                                min: 40,
                                max: 160,
                                divisions: 120,
                                value: _heartRate.toDouble().clamp(40, 160),
                                onChanged: (v) => setState(() {
                                  _onManualAdjust();
                                  _hasWatchHeartRate = true;
                                  _heartRate = v.round();
                                }),
                              ),
                              Text('걸음 $_steps', style: theme.textTheme.bodyLarge),
                              Slider(
                                min: 0,
                                max: 8000,
                                divisions: 80,
                                value: _steps.clamp(0, 8000).toDouble(),
                                onChanged: (v) => setState(() {
                                  _onManualAdjust();
                                  _steps = v.round();
                                }),
                              ),
                              Text('쉼 $_inactiveMinutes분', style: theme.textTheme.bodyLarge),
                              Slider(
                                min: 0,
                                max: 480,
                                divisions: 48,
                                value: _inactiveMinutes.clamp(0, 480).toDouble(),
                                onChanged: (v) => setState(() {
                                  _onManualAdjust();
                                  _inactiveMinutes = v.round();
                                }),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _noteController,
                          style: theme.textTheme.bodyLarge,
                          decoration: InputDecoration(
                            labelText: '오늘 몸 상태 한마디 (있으면)',
                            labelStyle: theme.textTheme.bodyLarge,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.all(18),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null && _aiPhase != _AiPhase.failed) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (_lastAnalysis != null) ...[
                  const SizedBox(height: 18),
                  Card(
                    color: _caregiverNotified
                        ? const Color(0xFFFFF3E0)
                        : Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('오늘 말로 정리', style: theme.textTheme.titleLarge),
                          const SizedBox(height: 10),
                          Text(
                            _lastAnalysis!.summary,
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (_caregiverNotified) ...[
                            const SizedBox(height: 14),
                            Text(
                              '가족에게도 알림을 보냈어요.',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: const Color(0xFFE65100),
                              ),
                            ),
                          ] else if (_lastAnalysis!.alertCaregiverSuggested) ...[
                            const SizedBox(height: 14),
                            Text(
                              '가족 알림은 아직이에요. 같은 상태가 이어지면 보낼게요.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                          const SizedBox(height: 14),
                          Text('이렇게 하면 좋아요', style: theme.textTheme.titleMedium),
                          ..._lastAnalysis!.recommendations.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('• ', style: theme.textTheme.bodyLarge),
                                  Expanded(child: Text(r, style: theme.textTheme.bodyLarge)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  '병원 진단이 아니라 참고용이에요. 많이 불편하면 바로 전화하거나 병원에 가세요.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FilledButton.icon(
          onPressed: _canRunCheck ? _runAnalysis : null,
          icon: _analyzing
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.health_and_safety_rounded, size: 30),
          label: Text(
            !_aiReady && Platform.isAndroid
                ? '도우미 준비 중…'
                : _analyzing
                    ? '확인하는 중…'
                    : '오늘 내 상태 확인하기',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _AiPreparingBanner extends StatelessWidget {
  const _AiPreparingBanner({required this.phase, required this.progress});

  final _AiPhase phase;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = phase == _AiPhase.unpacking
        ? '처음이라 큰 파일을 옮기고 있어요. 잠시만 기다려 주세요.'
        : '도우미를 깨우는 중이에요… ${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%';
    return Material(
      color: const Color(0xFFFFF9C4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(msg, style: theme.textTheme.bodyLarge),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiFailedBanner extends StatelessWidget {
  const _AiFailedBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: const Color(0xFFFFEBEE),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '도우미를 불러오지 못했어요',
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFFB71C1C),
              ),
            ),
            const SizedBox(height: 8),
            Text(message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: 28,
              color: color,
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black45),
            ),
        ],
      ),
    );
  }
}
