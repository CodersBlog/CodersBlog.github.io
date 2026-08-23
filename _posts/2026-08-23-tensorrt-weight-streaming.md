---
title: "[TensorRT] Weight Streaming — VRAM이 부족한 모델의 가중치 나눠 가져오기"
excerpt: "A practical guide to reducing VRAM usage with TensorRT Weight Streaming by sehoon-lee"
description: "TensorRT Weight Streaming으로 일부 가중치를 호스트 메모리에 두어 VRAM 사용량을 줄이고, 상주 예산과 성능을 검증하는 방법을 정리합니다."

categories:
    - Infra
tags:
    - [TensorRT, Weight Streaming, NVIDIA, GPU Inference, VRAM]

toc: true
toc_sticky: true

date: 2026-08-23
last_modified_at: 2026-08-23

math: false
---

## 핵심 요약

- Weight Streaming은 일부 가중치를 호스트 메모리에 두고 실행 시 필요한 만큼 GPU로 전송해 VRAM 사용량을 줄인다.
- GPU에 상주시키는 가중치 예산을 낮출수록 더 큰 모델을 실행할 수 있지만 전송량과 지연 시간이 늘 수 있다.
- 자동 예산은 시작점일 뿐이다. 실제 입력과 동시 실행 수로 VRAM, 호스트 RAM, 지연 시간, 처리량을 함께 측정해야 한다.

## 1. 모델은 준비됐는데 VRAM이 모자랄 때

ONNX 모델을 TensorRT 엔진으로 변환했는데 실행 단계에서 메모리 부족이 발생하는 경우가 있다. 가중치뿐 아니라 활성값, 실행 컨텍스트의 작업 메모리, 입력·출력 버퍼가 같은 GPU 메모리를 사용하기 때문이다. 배치를 줄이거나 정밀도를 낮추면 해결될 수 있지만, 정확도 요구 때문에 양자화가 어렵거나 한 요청의 입력 크기 자체를 줄일 수 없는 상황도 있다.

TensorRT의 Weight Streaming은 모든 가중치를 엔진 로드 시 GPU에 올리지 않는다. 일부는 호스트 메모리에 보관하고 네트워크 실행 중 필요한 시점에 GPU로 가져온다. 이 방식은 모델의 계산량을 줄이는 최적화가 아니라 가중치의 저장 위치를 조절하는 메모리 관리 기능이다. 따라서 더 큰 모델이나 배치를 실행할 여지를 만드는 대신 호스트와 디바이스 사이의 전송 비용을 감수한다.

## 2. 일반 실행과 Weight Streaming 비교

| 구분 | 일반 TensorRT 실행 | Weight Streaming |
| --- | --- | --- |
| 가중치 위치 | 엔진 로드 시 대부분 GPU에 상주 | 일부는 호스트에 두고 필요할 때 전송 |
| GPU 메모리 | 가중치 전체 공간을 우선 확보 | 설정한 상주 예산만큼 절약 가능 |
| 호스트 메모리 | 상대적으로 부담이 작음 | 역직렬화 시 전체 가중치용 호스트 버퍼가 필요할 수 있음 |
| 지연 시간 | 가중치 전송이 반복되지 않음 | 낮은 예산에서는 전송 때문에 증가할 수 있음 |
| 적합한 상황 | 모델과 버퍼가 VRAM에 충분히 들어감 | VRAM 부족을 해소하는 것이 최우선 |

여기서 예산은 스트리밍 가능한 가중치 중 GPU에 계속 둘 바이트 수다. 예산을 스트리밍 가능한 전체 크기보다 크게 주면 전체 크기로 잘리고 사실상 스트리밍이 꺼진다. 반대로 예산을 줄이면 VRAM은 확보되지만 매 추론에서 가져와야 하는 데이터가 늘어난다. TensorRT는 계산과 전송을 최대한 겹치도록 어떤 가중치를 남길지 선택한다.

## 3. 빌드부터 실행까지의 처리 순서

1. **스트리밍 가능한 엔진 빌드**: 빌더 설정에 `WEIGHT_STREAMING`을 켠다. TensorRT 11.x의 새 네트워크는 Strong Typing이 기본이다.
2. **엔진 역직렬화**: 런타임이 가중치를 호스트에 보관한다. 큰 엔진은 호스트 RAM의 순간 최대 사용량도 확인한다.
3. **가중치 크기 조회**: `streamable_weights_size`로 예산의 상한을 확인한다.
4. **GPU 상주 예산 설정**: `weight_streaming_budget_v2`에 바이트 단위 예산을 지정한다.
5. **컨텍스트 메모리 재확인**: 스트리밍용 scratch memory와 활성값·입출력 버퍼를 포함한 실제 여유 공간을 계산한다.
6. **반복 측정**: 예산별 peak VRAM, p50·p95 지연 시간과 처리량을 비교해 운영값을 고른다.

> Weight Streaming은 OOM을 피하는 안전장치이지 무료 가속 기능이 아니다. 목표는 가장 작은 예산이 아니라 서비스의 지연 시간 기준을 만족하는 가장 작은 예산이다.

## 4. trtexec로 예산 비교하기

검증 기준일인 2026-08-23의 TensorRT 11.2.1에서는 다음처럼 ONNX 모델로 스트리밍 가능한 엔진을 만든다. `trtexec`는 pip wheel에 포함되지 않으므로 Debian/RPM, tar/zip 또는 컨테이너 설치가 필요하다.

```bash
# 1) Weight Streaming을 허용한 엔진 빌드
trtexec \
  --onnx=model.onnx \
  --saveEngine=model-streaming.plan \
  --allowWeightStreaming \
  --skipInference

# 2) GPU에 4 GiB의 스트리밍 가능 가중치를 상주시켜 측정
trtexec \
  --loadEngine=model-streaming.plan \
  --weightStreamingBudget=4G \
  --warmUp=2000 \
  --duration=10

# 비교 기준: -1은 런타임 Weight Streaming 비활성화
trtexec --loadEngine=model-streaming.plan --weightStreamingBudget=-1
```

`--weightStreamingBudget`의 K·M·G 접미사는 2진 단위인 KiB·MiB·GiB를 뜻한다. 문서상 `0`은 가중치가 GPU에 모두 들어가지 않을 때 가능한 최소 예산을 선택하고, `-1`은 런타임 스트리밍을 끈다. 최소 예산 한 번만 재기보다 비활성화, 자동 또는 최소, 여러 고정 예산을 같은 입력 shape와 실행 시간으로 비교하는 편이 좋다.

## 5. Python API에서 예산 정하기

TensorRT 11.x에서는 이전 `setWeightStreamingBudget()` 대신 V2 API를 사용한다. 다음 코드는 역직렬화한 엔진에서 스트리밍 가능한 전체 크기와 자동 예산을 확인한 뒤, 둘 중 작은 값을 적용하는 시작 예시다. 자동 예산은 애플리케이션의 다른 GPU 할당을 모두 알지 못하므로 그대로 운영값으로 확정하면 안 된다.

```python
import tensorrt as trt

logger = trt.Logger(trt.Logger.WARNING)
runtime = trt.Runtime(logger)

with open("model-streaming.plan", "rb") as f:
    engine = runtime.deserialize_cuda_engine(f.read())

streamable = engine.streamable_weights_size
automatic = engine.get_weight_streaming_automatic_budget()
budget = min(streamable, automatic)
engine.weight_streaming_budget_v2 = budget

print(f"streamable={streamable / 2**30:.2f} GiB")
print(f"resident budget={engine.weight_streaming_budget_v2 / 2**30:.2f} GiB")
print(f"streaming scratch={engine.weight_streaming_scratch_memory_size / 2**20:.1f} MiB")
```

여러 실행 컨텍스트를 동시에 사용하면 컨텍스트별 메모리와 애플리케이션 버퍼도 남겨야 한다. 예산을 바꾸는 시점에는 해당 엔진의 활성 컨텍스트가 없어야 한다. 엔진을 읽을 때 호스트 peak memory가 문제가 된다면 TensorRT 문서가 권장하는 `IStreamReaderV2`로 파일에서 직접 역직렬화하는 방식도 검토할 수 있다.

## 6. 실무 적용 기준과 주의사항

- **먼저 기준선을 만든다.** 스트리밍을 끈 상태가 실행 가능하면 지연 시간과 메모리를 기록하고, 예산을 단계적으로 낮춘다.
- **호스트 RAM도 측정한다.** GPU에서 빠진 가중치가 사라지는 것이 아니라 호스트로 이동한다. 역직렬화 순간과 안정 상태를 나눠 본다.
- **PCIe 경쟁을 확인한다.** 입력 복사, 다른 GPU 작업과 가중치 전송이 같은 링크를 사용하면 단독 벤치마크보다 운영 지연이 커질 수 있다.
- **동시 실행 수를 반영한다.** 컨텍스트가 늘면 scratch memory와 활성값이 반복될 수 있으므로 한 컨텍스트에서 맞던 예산이 OOM을 일으킬 수 있다.
- **엔진 이식성을 가정하지 않는다.** TensorRT 엔진은 기본적으로 플랫폼과 GPU 조건의 영향을 받는다. 대상 환경에서 직접 빌드·검증하거나 호환성 옵션을 별도로 검토한다.
- **양자화와 목적을 구분한다.** 양자화는 가중치 표현 자체를 줄일 수 있고 Weight Streaming은 저장 위치를 바꾼다. 정확도와 지연 시간 요구에 따라 두 방법을 따로 비교한다.

정리하면 Weight Streaming은 VRAM 부족 때문에 모델을 전혀 실행하지 못하는 상황에서 선택지를 넓힌다. 그러나 예산을 과하게 줄이면 메모리는 절약해도 지연 시간과 처리량이 서비스 기준을 벗어날 수 있다. 스트리밍 가능한 크기, scratch memory, 호스트 peak memory를 먼저 확인하고 실제 요청 분포에서 예산별 성능 곡선을 만드는 것이 가장 안전하다.

## 참고 출처

- [NVIDIA TensorRT — Weight Streaming 공식 문서](https://docs.nvidia.com/deeplearning/tensorrt/latest/inference-library/weight-streaming.html)
- [NVIDIA TensorRT — Performance Benchmarking과 trtexec 플래그](https://docs.nvidia.com/deeplearning/tensorrt/latest/performance/benchmarking.html)
- [NVIDIA TensorRT — 10.x에서 11.x로 Weight Streaming API 마이그레이션](https://docs.nvidia.com/deeplearning/tensorrt/latest/api/migration/tensorrt-10x-to-11x-c-api-patterns.html)
- [NVIDIA TensorRT 11.2.1 Release Notes](https://docs.nvidia.com/deeplearning/tensorrt/latest/getting-started/release-notes.html)
- [NVIDIA TensorRT 11.2.1 Support Matrix](https://docs.nvidia.com/deeplearning/tensorrt/latest/getting-started/support-matrix.html)
- [NVIDIA TensorRT 11.2.1 Prerequisites](https://docs.nvidia.com/deeplearning/tensorrt/latest/installing-tensorrt/prerequisites.html)

검증 기준일: 2026-08-23. NVIDIA TensorRT 11.2.1 공식 문서와 지원 매트릭스를 기준으로 작성했다. 이 버전의 Debian/RPM/tar/zip 패키지는 CUDA Toolkit 13.3 update 1 기준이며, pip은 CUDA 12 또는 13 계열에 맞는 wheel을 선택할 수 있다. 지원 GPU, 드라이버, Python, ONNX 조건은 설치 방식과 플랫폼에 따라 달라지므로 실제 적용 전 대상 환경의 Support Matrix를 다시 확인해야 한다. 성능 결과는 모델, 입력 shape, PCIe 대역폭, GPU와 동시 실행 수에 따라 달라진다.
