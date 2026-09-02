---
title: "[TensorRT] Dynamic Shape Profile을 잡는 실전 절차"
excerpt: "YOLO 추론에서 Dynamic Shape Profile을 설계하고 검증하는 방법 by sehoon-lee"
description: "TensorRT의 min/opt/max profile을 실제 요청 분포에 맞춰 설계하고 trtexec로 검증하는 운영 절차를 정리합니다."
categories:
  - Infra
tags:
  - [TensorRT, YOLO, Dynamic Shape, trtexec, GPU Inference]
toc: true
toc_sticky: true
date: 2026-09-02
last_modified_at: 2026-09-02
---

## 핵심 요약

- TensorRT의 `min/opt/max`는 단순한 허용 범위가 아니라 tactic과 메모리 계획을 결정하는 최적화 계약이다.
- 실제 요청 shape 분포를 기준으로 `opt` shape를 정하고, 드문 대형 입력은 별도 profile 또는 엔진으로 분리한다.
- profile 밖 입력은 enqueue 전에 차단하고, 주력 shape의 p95 latency와 peak VRAM으로 배포 여부를 결정한다.

## 1. 증상부터 profile 문제로 분리하기

YOLO나 검출 모델을 TensorRT 엔진으로 운영할 때 해상도 또는 batch가 바뀌면 `profile does not support shape` 오류, 급격한 p95 지연 증가, workspace 부족이 나타날 수 있다. 이 문제를 `max`를 크게 잡는 방식으로만 해결하면 엔진 크기와 빌드 시간은 커지고, 가장 자주 쓰는 입력의 성능은 오히려 나빠질 수 있다.

먼저 요청 로그에서 batch와 H×W 빈도를 수집한다. 예를 들어 640×640 batch 1이 대부분이고 1280×720 요청이 드물다면, 640×640을 `opt`로 둔 profile이 주력 경로다. 동적 shape의 목표는 모든 모양을 한 엔진에 넣는 것이 아니라, 실제 서비스 입력을 예측 가능하게 빠르게 처리하는 것이다.

## 2. min/opt/max의 역할

`min`과 `max`는 실행 가능한 입력 범위이고 `opt`는 TensorRT가 가장 중요하게 최적화할 대표 shape다. 따라서 `opt`에는 평균이 아니라 가장 많은 요청을 넣는다. 고정 letterbox 정책으로 모든 입력을 640×640으로 바꿀 수 있다면 profile도 단순해진다. 원본 비율 보존이 필요하다면 640×640과 1280×720처럼 서로 다른 워크로드를 분리하는 것이 관리하기 쉽다.

```bash
trtexec --onnx=model.onnx --explicitBatch \
  --minShapes=images:1x3x640x640 \
  --optShapes=images:4x3x640x640 \
  --maxShapes=images:8x3x640x640 \
  --fp16 --saveEngine=yolo-640.engine
```

이 구성은 batch 4, 640×640을 주력으로 둔다. 실제 서비스가 batch 1 위주라면 `optShapes`도 batch 1로 바꿔 비교해야 한다. 추론 서버의 micro-batching 정책과 profile을 따로 결정하면 의도와 다른 tactic이 선택될 수 있다.

## 3. 실행 전 입력을 검사한다

엔진에 shape 오류를 맡기면 원인 추적이 어렵다. 전처리 뒤 입력 tensor가 profile 범위인지 확인하고, 범위 밖이면 resize 정책을 적용하거나 별도 엔진으로 라우팅한다. 로그에는 원본 이미지 shape, 모델 입력 shape, batch, profile 번호를 남긴다.

```text
원본 1280x720 -> letterbox 640x640 -> images=(4,3,640,640)
선택 profile=0 -> enqueue
```

이 기록이 있으면 “엔진 오류”와 “전처리 정책 우회”를 분리할 수 있다. 특히 카메라 스트림마다 해상도가 다른 경우, 입력 단계에서 규칙을 고정하지 않으면 profile 수만 늘어난다.

## 4. profile별 latency를 측정한다

엔진을 빌드했다는 사실은 성능 검증이 아니다. 주력 shape와 최대 shape를 각각 warm-up 후 충분히 측정하고, p50뿐 아니라 p95와 peak GPU 메모리를 비교한다.

```bash
trtexec --loadEngine=yolo-640.engine \
  --shapes=images:4x3x640x640 \
  --warmUp=1000 --duration=60 --useCudaGraph
```

동일한 ONNX라도 profile 설계가 다르면 엔진과 latency가 달라진다. 입력 복사·전처리 시간이 포함된 서비스 지연도 별도로 보아야 한다. `trtexec` 수치만 좋아도 resize 비용이나 큐 대기가 크면 사용자 체감 지연은 개선되지 않을 수 있다.

## 5. 엔진을 나눌 신호

다음 중 하나가 보이면 큰 범위 하나를 계속 넓히기보다 분리를 검토한다.

1. 드문 1280×720 요청 때문에 640×640 주력 경로의 p95 또는 VRAM이 악화된다.
2. 최대 shape에서만 workspace 부족이나 빌드 시간이 과도하게 증가한다.
3. letterbox가 작은 객체 검출 품질을 떨어뜨려 원본 비율 경로가 필요하다.
4. GPU 메모리에 두 엔진을 올릴 수 있고 라우팅 규칙을 명확히 만들 수 있다.

엔진 수 증가는 배포와 메모리 관리 비용도 증가시킨다. 따라서 드문 shape가 실제 품질 또는 SLA 이득을 만드는지 먼저 확인한다.

## 6. 배포와 롤백 기준

새 profile은 주력 shape의 p95가 기존보다 나빠지거나 peak VRAM이 운영 한계를 넘으면 배포하지 않는다. 오류가 발생했을 때는 `max`를 무작정 키우지 말고, 실제 요청 분포와 resize 정책이 기대대로 적용됐는지부터 확인한다. 이 과정을 지키면 Dynamic Shape 지원은 예외 처리의 모음이 아니라 재현 가능한 성능 계약이 된다.

## 참고 출처

- [NVIDIA TensorRT — Working with Dynamic Shapes](https://docs.nvidia.com/deeplearning/tensorrt/latest/inference-library/work-dynamic-shapes.html)
- [NVIDIA TensorRT — trtexec reference](https://docs.nvidia.com/deeplearning/tensorrt/latest/reference/command-line-programs.html)
- [NVIDIA TensorRT — Performance Best Practices](https://docs.nvidia.com/deeplearning/tensorrt/latest/performance/best-practices.html)
