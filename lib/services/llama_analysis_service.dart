import 'dart:async';

import 'package:llama_flutter_android/llama_flutter_android.dart';

import '../models/health_snapshot.dart';
import '../prompts/analysis_prompt.dart';

/// Runs Gemma (GGUF via llama.cpp) on-device for structured health interpretation.
class LlamaAnalysisService {
  LlamaAnalysisService() : _llama = LlamaController();

  final LlamaController _llama;
  bool _disposed = false;

  Stream<double> get loadProgress => _llama.loadProgress;

  Future<bool> isModelLoaded() => _llama.isModelLoaded();

  Future<void> loadModel({
    required String modelPath,
    int threads = 4,
    int contextSize = 4096,
    int? gpuLayers,
  }) async {
    await _llama.loadModel(
      modelPath: modelPath,
      threads: threads,
      contextSize: contextSize,
      gpuLayers: gpuLayers,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _llama.dispose();
  }

  /// Returns concatenated model output (caller parses JSON).
  Future<String> analyzeSnapshot(HealthSnapshot snapshot) async {
    if (_disposed) throw StateError('LlamaAnalysisService disposed');
    if (!await _llama.isModelLoaded()) {
      throw StateError('Model not loaded');
    }

    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: kGemmaCareSystemPrompt),
      ChatMessage(
        role: 'user',
        content:
            '다음 데이터를 분석해 JSON만 출력하세요.\n\n${snapshot.toPromptBlock()}',
      ),
    ];

    final buffer = StringBuffer();
    await for (final token in _llama.generateChat(
      messages: messages,
      template: 'gemma',
      maxTokens: 512,
      temperature: 0.15,
      topP: 0.9,
    )) {
      buffer.write(token);
    }

    return buffer.toString();
  }
}
