---
title: "[vLLM] GPU 영상 디코딩 — NVDEC로 VLM 입력 병목 줄이기"
excerpt: "A practical guide to moving VLM video decoding to NVIDIA NVDEC with vLLM by sehoon-lee"
description: "vLLM에서 NVDEC 기반 PyNvVideoCodec과 DeepStream으로 영상 프레임 디코딩을 GPU로 옮기는 방법, VRAM 예산과 운영 검증 기준을 정리합니다."

categories:
    - Infra
tags:
    - [vLLM, VLM, NVDEC, DeepStream, GPU Inference]

toc: true
toc_sticky: true

date: 2026-09-02
last_modified_at: 2026-09-02

math: false
---

## 핵심 요약

- 영상 VLM 서비스에서는 LLM 추론뿐 아니라 영상을 프레임으로 푸는 단계가 병목일 수 있다. vLLM은 기본 CPU 디코딩 외에 NVIDIA NVDEC를 사용하는 PyNvVideoCodec·DeepStream 백엔드를 제공한다.
- PyNvVideoCodec은 API 서버와 엔진 프로세스가 GPU를 함께 쓰므로 CUDA MPS와 디코딩 전용 VRAM 예산이 필요하다. 이 예산은 KV cache가 쓸 수 있는 메모리에서 분리된다.
- 짧은 파일을 요청 단위로 처리할 때와 지속적인 스트리밍 입력은 운영 조건이 다르다. 전자는 PyNvVideoCodec, 스트리밍은 DeepStream을 우선 검토하되 실제 영상 길이·동시성·TTFT로 측정해야 한다.

## 1. VLM이 느린 원인이 모델만은 아닐 때

영상 질의 서비스는 보통 파일을 열고, 필요한 프레임을 뽑고, 이미지 전처리를 한 뒤에야 VLM이 프롬프트를 처리한다. 모델의 prefill이나 생성 토큰 속도만 살펴보면 디코딩이 CPU를 오래 점유하는 문제를 놓치기 쉽습니다. 특히 영상 태깅처럼 프레임을 비교적 적게 뽑고 모델 추론이 가벼운 요청에서는 디코더가 전체 대기 시간을 지배할 수 있습니다.

vLLM의 기본 영상 경로는 CPU에서 디코딩합니다. NVIDIA GPU 환경에서는 NVDEC 하드웨어 비디오 엔진으로 샘플링한 프레임을 풀도록 바꿀 수 있습니다. 이는 VLM 자체를 더 빠르게 만드는 기능이 아니라, 입력 준비 단계의 자원을 CPU에서 GPU 비디오 엔진으로 옮기는 선택입니다.

![CPU 디코딩 경로와 NVDEC 경로의 비교](/assets/img/post/vllm-gpu-video-decoding/decode-pipeline.svg){: .align-center}
*NVDEC를 써도 멀티모달 전처리와 VLM 추론은 남습니다. 병목 위치를 측정한 뒤 적용해야 합니다.*

## 2. PyNvVideoCodec과 DeepStream은 용도가 다릅니다

| 구분 | PyNvVideoCodec | DeepStream |
| --- | --- | --- |
| 주 대상 | API 서버가 파일 영상을 처리하는 요청 | 지속적인 스트리밍 영상 소스 |
| 디코딩 위치 | NVDEC 후 호스트 메모리로 복사해 전처리 | NVDEC 하드웨어 비디오 엔진 활용 |
| 추가 조건 | CUDA MPS와 `--mm-ipc-gpu-memory-gb` 필요 | Linux x86-64 및 GStreamer 등 시스템 패키지 필요 |
| 메모리 제어 | 프런트엔드 디코딩 전용 VRAM 예산 | 워커 풀 크기와 GPU 자원을 함께 조절 |

PyNvVideoCodec은 API 서버 프로세스에서 디코딩하고 vLLM 엔진 프로세스에서 모델을 실행합니다. 하나의 GPU를 여러 CUDA 프로세스가 공유하므로 vLLM 공식 문서는 CUDA MPS를 필수 조건으로 명시합니다. 반면 DeepStream은 스트리밍 영상 소스에 권장되는 GPU 백엔드입니다.

> NVDEC를 켠다고 GPU 메모리 문제가 사라지는 것은 아닙니다. 디코딩용 메모리를 확보하면 그만큼 KV cache에 쓸 수 있는 공간은 줄어듭니다.

## 3. PyNvVideoCodec의 핵심은 VRAM 경계입니다

`--mm-ipc-gpu-memory-gb`는 API 서버가 프레임을 디코딩할 때 사용할 VRAM의 상한을 정합니다. vLLM은 이 값을 KV cache 후보 메모리에서 떼어내고, 디코딩 할당이 예산에 도달하면 엔진의 남은 VRAM을 침범하는 대신 작업을 기다리게 합니다.

따라서 값이 너무 작으면 디코딩 대기가 늘 수 있고, 너무 크면 긴 컨텍스트나 동시 요청에 쓸 KV cache 공간이 줄 수 있습니다. 공식 예시의 `1` GiB는 시작점일 뿐입니다. 서비스의 최대 영상 길이, 샘플 프레임 수, 해상도, API 서버 프로세스 수를 기준으로 정해야 합니다. API 서버가 여러 개면 설정한 예산은 프로세스 사이에 나뉩니다.

## 4. 파일 영상부터 최소 구성으로 확인하기

아래는 공식 문서의 PyNvVideoCodec 선택 방법을 바탕으로 한 최소 서버 구성입니다. 실행 전 GPU 드라이버·CUDA·vLLM 버전과 MPS 동작 여부를 해당 환경에서 확인해야 합니다.

```bash
# CUDA MPS는 vLLM 서버를 띄우기 전에 별도로 구성·시작해야 한다.

export VLLM_VIDEO_LOADER_BACKEND=pynvvideocodec

vllm serve Qwen/Qwen3-VL-30B-A3B-Instruct \
  --mm-ipc-gpu-memory-gb 1
```

백엔드를 전역 환경 변수로 바꾸기 어려우면 `--media-io-kwargs`로 영상 입력에만 지정할 수 있습니다.

```bash
vllm serve Qwen/Qwen3-VL-30B-A3B-Instruct \
  --media-io-kwargs '{"video": {"backend": "pynvvideocodec"}}' \
  --mm-ipc-gpu-memory-gb 1
```

스트리밍 입력에서는 DeepStream을 선택할 수 있습니다. 공식 문서 기준 패키지는 Linux x86-64용이며, pip wheel 외에도 GStreamer·CUDA 라이브러리 같은 시스템 의존성이 필요합니다.

```bash
pip install 'vllm[deepstream]'

export VLLM_VIDEO_LOADER_BACKEND=deepstream
vllm serve Qwen/Qwen3-VL-30B-A3B-Instruct
```

## 5. 무엇을 재야 적용 여부를 알 수 있나

NVDEC 적용 전후에는 동일한 모델, 영상 집합, 샘플 프레임 정책, 동시성으로 비교해야 합니다. 최소한 다음을 함께 기록합니다.

1. **입력 단계 시간**: 영상 열기부터 프레임 준비까지의 시간과 CPU 사용률
2. **사용자 체감 지연**: 첫 응답 토큰까지의 시간(TTFT), 전체 응답 시간, p95 지연 시간
3. **GPU 자원**: NVDEC 사용률, peak VRAM, KV cache 여유량
4. **대기 현상**: 디코딩 예산을 낮췄을 때 요청이 기다리는지, OOM 대신 지연으로 전환되는지
5. **정확성**: 프레임 샘플 수와 간격을 바꿔도 영상 질문의 답이 유지되는지

CPU 사용률만 내려가도 서비스가 빨라졌다고 결론 내리면 안 됩니다. 이미 VLM 추론이 병목이면 디코딩 백엔드 교체의 효과는 작을 수 있습니다. 반대로 CPU 디코더가 포화된 서비스라면 NVDEC가 CPU 여유와 영상 처리량을 개선할 수 있지만, 그 대가로 GPU 메모리·드라이버·MPS 운영 복잡도가 늘어납니다.

## 참고 출처

- [vLLM — Multimodal Inputs: GPU Video Decoding](https://docs.vllm.ai/en/latest/features/multimodal_inputs/)
- [vLLM GitHub 저장소](https://github.com/vllm-project/vllm)
- [NVIDIA Video Codec SDK](https://developer.nvidia.com/video-codec-sdk)
- [NVIDIA CUDA Multi-Process Service](https://docs.nvidia.com/deploy/mps/)

검증 기준일: 2026-09-02. vLLM의 멀티모달·GPU 디코딩 지원은 활발히 변경될 수 있으므로, 실제 운영 전에는 사용 중인 버전의 공식 문서와 대상 GPU·드라이버 조합을 다시 확인해야 합니다.
