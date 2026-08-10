---
title: "[NVIDIA] TensorRT-LLM으로 VLM 추론 서버 구성하기"
excerpt: "A practical guide to serving VLMs with TensorRT-LLM, the PyTorch backend, and trtllm-serve by sehoon-lee"
description: "TensorRT-LLM의 최신 멀티모달 추론 구조와 PyTorch 백엔드 기반 trtllm-serve 실행 방법, 최적화와 운영 시 주의사항을 정리합니다."

categories:
    - Infra
tags:
    - [NVIDIA, TensorRT-LLM, VLM, Multimodal, GPU Inference]

toc: true
toc_sticky: true

date: 2026-08-11
last_modified_at: 2026-08-11

math: false
---

## 핵심 요약

- TensorRT-LLM의 최신 멀티모달 경로는 별도 비전 엔진 빌드보다 PyTorch 백엔드와 `trtllm-serve` 사용을 중심으로 한다.
- VLM 요청은 입력 전처리, 비전 인코더, 텍스트 임베딩과의 결합, LLM 디코딩 순서로 처리된다.
- 이미지뿐 아니라 모델에 따라 영상과 오디오 입력도 OpenAI 호환 형식으로 전달할 수 있다.

## 1. 배경

VLM을 실제 서비스에 적용하면 텍스트 LLM과 다른 병목이 발생한다. 이미지를 리사이즈하고 정규화하는 CPU 작업, 비전 인코더의 GPU 연산, 이미지 임베딩과 텍스트 토큰을 합치는 과정이 추가되기 때문이다.

기존 TensorRT 사용 경험만으로 접근하면 비전 인코더와 LLM 엔진을 각각 변환해야 한다고 생각하기 쉽다. 하지만 현재 TensorRT-LLM의 멀티모달 지원 방식은 과거 예제와 구조가 달라졌다. 이번 글에서는 최신 공식 문서를 기준으로 VLM 요청이 처리되는 과정과 서버 실행 방법을 정리한다.

## 2. VLM 추론 구조

일반적인 텍스트 LLM은 토큰을 임베딩으로 변환한 뒤 디코더에 입력한다. VLM은 여기에 다음 세 단계가 추가된다.

1. **Multimodal Input Processor**: 이미지나 영상을 모델이 받을 수 있는 pixel value 형태로 전처리한다.
2. **Multimodal Encoder**: 비전 입력을 LLM의 임베딩 공간과 결합할 수 있는 특징으로 변환한다.
3. **LLM Decoder Integration**: 이미지 임베딩과 텍스트 임베딩을 결합하여 언어 모델 디코더에 전달한다.

| 구분 | 텍스트 LLM | VLM |
|---|---|---|
| 입력 | 텍스트 토큰 | 텍스트 + 이미지·영상·오디오 |
| 추가 연산 | 없음 | 전처리 + 멀티모달 인코더 |
| 주요 병목 | 프리필·디코딩 | 전처리·인코딩·프리필·디코딩 |

## 3. 기존 TensorRT 방식과 달라진 점

예전 TensorRT-LLM 멀티모달 예제는 `build_multimodal_engine.py`와 `trtllm-build`를 이용해 엔진을 생성했다. 현재 공식 저장소에서는 이 레거시 TensorRT 백엔드 방식이 제거되었다고 명시한다.

최신 멀티모달 모델은 PyTorch 백엔드에서 지원되며, `trtllm-serve` 또는 LLM Python API를 사용하는 방향으로 바뀌었다. 따라서 과거 블로그나 예제의 엔진 빌드 명령을 그대로 따라가기보다 설치한 TensorRT-LLM 버전의 공식 문서를 먼저 확인해야 한다.

> 멀티모달 지원은 빠르게 변경되는 영역이다. 오래된 예제에서 파일이 사라졌다면 설치 오류보다 백엔드 마이그레이션 여부를 먼저 확인하는 것이 좋다.

## 4. trtllm-serve 실행

공식 문서에 제시된 Qwen2-VL 실행 예시는 다음과 같다.

```bash
trtllm-serve Qwen/Qwen2-VL-7B-Instruct --backend pytorch
```

서버가 실행되면 OpenAI 호환 Chat Completions 형식으로 이미지 URL 또는 base64 이미지를 전달할 수 있다.

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2-VL-7B-Instruct",
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "이미지의 객체와 상황을 설명해줘."},
        {"type": "image_url", "image_url": {"url": "https://example.com/image.png"}}
      ]
    }],
    "max_tokens": 128
  }'
```

영상 입력 모델을 사용할 경우 `video_url` 타입을 사용할 수 있다. 영상 디코딩에는 OpenCV가 필요하며 기본 설치에 포함되지 않으므로 다음 패키지를 별도로 설치한다.

```bash
pip install opencv-python-headless
```

## 5. 멀티모달 최적화

TensorRT-LLM 공식 문서는 멀티모달 추론을 위해 세 가지 최적화를 설명한다.

- **In-Flight Batching**: 서로 다른 요청을 GPU 실행기 안에서 묶어 GPU 사용률과 처리량을 높인다.
- **CPU/GPU Concurrency**: CPU 전처리와 GPU 이미지 인코딩을 비동기로 겹쳐 전체 지연 시간을 줄인다.
- **Raw Data Hashing**: 이미지 해시와 토큰 청크 정보를 이용해 KV 캐시 재사용 가능성을 높이고 충돌을 줄인다.

실무에서는 디코딩 속도만 측정하면 안 된다. 이미지 다운로드, 디코딩, 리사이즈, 비전 인코딩을 포함한 end-to-end latency와 첫 토큰 지연 시간을 함께 측정해야 한다.

## 6. 적용 시 주의사항

- 지원 입력 형식은 모델에 따라 다르다. 서버가 이미지·영상·오디오 타입을 받더라도 선택한 모델이 해당 modality를 지원해야 한다.
- 최신 공식 저장소는 멀티모달 모델을 PyTorch 백엔드로 안내한다. 레거시 엔진 빌드 예제와 혼용하지 않는다.
- 원격 이미지 URL을 받는 서비스는 파일 크기, MIME 형식, 다운로드 시간, 내부망 접근을 제한해야 한다.
- 영상 입력은 프레임 수에 따라 비전 토큰과 메모리 사용량이 크게 증가할 수 있으므로 최대 길이와 샘플링 정책을 정해야 한다.

정리하면 TensorRT-LLM의 VLM 지원은 단순히 LLM 엔진에 이미지를 추가하는 기능이 아니다. CPU 전처리부터 비전 인코딩과 LLM 디코딩까지 하나의 서빙 파이프라인으로 관리하는 접근이다. 기존 TensorRT 엔진 변환 경험이 있더라도 최신 버전에서는 `trtllm-serve`와 PyTorch 백엔드를 기준으로 다시 확인하는 것이 안전하다.

## 참고

- [NVIDIA TensorRT-LLM — Multimodal Support](https://nvidia.github.io/TensorRT-LLM/latest/features/multi-modality.html)
- [NVIDIA TensorRT-LLM — trtllm-serve](https://nvidia.github.io/TensorRT-LLM/commands/trtllm-serve/trtllm-serve.html)
- [NVIDIA/TensorRT-LLM — Multimodal examples](https://github.com/NVIDIA/TensorRT-LLM/blob/main/examples/models/core/multimodal/README.md)

검증 기준일: 2026-08-11. TensorRT-LLM 문서는 빠르게 변경될 수 있으므로 실제 적용 전 설치 버전의 지원 모델 표를 다시 확인해야 한다.
