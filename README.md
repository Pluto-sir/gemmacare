# gemmacare

## 문제
현재 문제:
에뮬레이터로 돌렸는데 이거 arm64 환경이어야 돌아가서 실제 폰에서 해야함.

## 실행 방법:
```bash
flutter pub get
```

```bash
flutter run
```

## 모델 추가하는법
app/src/main/assets/models에 모델의 이름을 gemma-care.gguf로 해서 넣는다. 모델은 
https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF
에서 
Q4_K_S
모델 사용.
