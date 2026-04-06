import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Resolves the on-disk path for the GGUF shipped under Android `assets/models/gemma-care.gguf`.
Future<String> prepareBundledGemmaModelPath() async {
  if (!Platform.isAndroid) {
    throw UnsupportedError('번들 GGUF는 Android에서만 지원됩니다.');
  }
  const channel = MethodChannel('gemmacare/bundled_model');
  try {
    final path = await channel.invokeMethod<String>('prepareBundledModel');
    if (path == null || path.isEmpty) {
      throw Exception('모델 파일 경로를 받지 못했습니다.');
    }
    return path;
  } on PlatformException catch (e) {
    final detail = e.message ?? e.code;
    throw Exception(
      '모델을 꺼내는 데 실패했습니다. android/app/src/main/assets/models/에 '
      'gemma-care.gguf 가 있는지 확인한 뒤 다시 빌드해 주세요.\n($detail)',
    );
  }
}
