---
title: "[vLLM] GPU 영상 디코딩 — NVDEC로 VLM 입력 병목 줄이기"
excerpt: "NVDEC 기반 영상 디코딩으로 VLM 입력 경로의 CPU 병목을 분리하고 측정하는 방법 by sehoon-lee"
description: "vLLM에서 PyNvVideoCodec과 DeepStream을 선택하고 디코딩 VRAM 예산을 검증하는 운영 절차를 정리합니다."
categories:
  - Infra
tags:
  - [vLLM, VLM, NVDEC, PyNvVideoCodec, DeepStream]
toc: true
toc_sticky: true
date: 2026-09-07
last_modified_at: 2026-09-07
---

## 핵심 요약

영상 VLM의 지연 시간은 모델 추론만으로 정해지지 않는다. 파일을 열고 프레임을 디코딩하고 전처리한 뒤 비전 인코더에 전달하는 입력 경로가 CPU를 점유하면, GPU에 여유가 있어도 요청은 느려진다. vLLM은 기본 CPU 디코딩 외에 NVIDIA NVDEC 기반 PyNvVideoCodec과 DeepStream 백엔드를 제공한다. 이 글은 두 선택지의 경계와 VRAM 예산을 운영 관점에서 정리한다.

## 1. 병목을 먼저 분리한다

영상 질의는 대체로 파일 획득, 컨테이너 파싱, 프레임 디코딩, 샘플링, 리사이즈, 비전 인코더, LLM prefill 순서로 진행된다. 30초 영상에서 32프레임만 쓰더라도 CPU 디코더가 여러 요청을 처리하면 프레임 준비 대기열이 생길 수 있다. 반대로 긴 프롬프트와 큰 모델에서 prefill이 지배적이면 NVDEC 전환 효과는 제한적이다.

따라서 적용 전에는 입력 준비 시간, TTFT, 전체 지연, CPU 사용률, peak VRAM을 같은 영상 집합으로 나눠 기록한다. CPU 사용률만 낮아진 결과는 충분하지 않다. TTFT와 오류율이 개선되어야 서비스 관점의 이득이다.

## 2. PyNvVideoCodec과 DeepStream의 선택

PyNvVideoCodec은 API 요청으로 들어온 파일 영상을 다루는 경우에 적합하다. API 서버 프로세스가 디코딩하고 vLLM 엔진 프로세스가 모델을 실행하므로, 한 GPU를 여러 CUDA 프로세스가 공유하는 환경에서는 CUDA MPS 구성이 필요할 수 있다. DeepStream은 RTSP 같은 지속 스트리밍 입력에 더 자연스럽다. Linux x86-64와 GStreamer 등 시스템 의존성을 함께 관리해야 하지만, 스트림 워커 풀을 지속 입력 모델에 맞춰 조절할 수 있다.

짧은 동영상 질의에는 PyNvVideoCodec부터, 카메라와 스트림 분석에는 DeepStream부터 검토하는 것이 현실적인 시작점이다. NVDEC는 GPU 비디오 엔진으로 디코딩 작업을 옮길 뿐 비전 인코더 연산, 프레임 수, KV cache, 업로드 시간까지 줄이지는 않는다.

## 3. 디코딩용 VRAM 경계를 둔다

`--mm-ipc-gpu-memory-gb`는 프런트엔드 디코딩이 사용할 GPU 메모리의 상한이다. 이 값은 엔진이 KV cache 후보로 사용할 수 있는 여유 메모리와 경쟁한다. 너무 작으면 디코딩 작업이 기다리고 TTFT가 늘 수 있으며, 너무 크면 긴 컨텍스트나 동시 요청에서 KV cache가 줄어 OOM 또는 스케줄링 저하가 발생할 수 있다.

```bash
export VLLM_VIDEO_LOADER_BACKEND=pynvvideocodec

vllm serve Qwen/Qwen3-VL-30B-A3B-Instruct \
  --mm-ipc-gpu-memory-gb 1
```

전역 환경 변수 변경이 부담스러우면 영상 입력에만 백엔드를 지정할 수 있다.

```bash
vllm serve Qwen/Qwen3-VL-30B-A3B-Instruct \
  --media-io-kwargs '{"video":{"backend":"pynvvideocodec"}}' \
  --mm-ipc-gpu-memory-gb 1
```

스트리밍 워크로드라면 DeepStream 패키지와 시스템 라이브러리 호환성을 먼저 확인한다.

```bash
pip install 'vllm[deepstream]'
export VLLM_VIDEO_LOADER_BACKEND=deepstream
vllm serve Qwen/Qwen3-VL-30B-A3B-Instruct
```

1GiB는 보편적 정답이 아니라 측정 시작점이다. 최대 해상도, 요청당 프레임 수, API 서버 프로세스 수, 목표 동시성을 기준으로 0.5·1·2GiB처럼 단계적으로 비교한다.

## 4. 운영 실험과 롤백

동일 모델, 영상 목록, 프레임 정책을 고정하고 입력 준비 시간과 CPU 사용률로 CPU 디코더 포화를 찾는다. 이어 TTFT와 p95 전체 지연으로 사용자 체감 효과를 확인하고, NVDEC 사용률·peak VRAM·KV cache 여유를 같이 기록한다. 동시성을 하나씩 올려 디코딩 예산 부족이 OOM 대신 대기로 전환되는지도 관찰한다.

문제가 생기면 모델을 바꾸기 전에 입력 단계와 추론 단계를 분리해 시간을 다시 측정한다. 디코딩 메모리와 KV cache가 경쟁한다면 VRAM 예산 또는 동시성을 직전 검증값으로 되돌린다. MPS를 구성하지 않은 다중 CUDA 프로세스, 드라이버와 wheel 호환성, 과도한 해상도와 프레임 수가 대표적인 실패 지점이다.

## 결론

NVDEC는 CPU 디코딩이 실제 병목인 영상 VLM 서비스에서 유용하다. 파일 기반 API에는 PyNvVideoCodec, 지속 스트림에는 DeepStream이라는 워크로드 구분을 먼저 세우고, VRAM 예산을 KV cache와 함께 조절해야 한다. 정답은 벤치마크 하나가 아니라 자신의 영상 길이, 해상도, 동시성, 품질 요구에서 나온다.

## 참고 출처

- https://docs.vllm.ai/en/latest/features/multimodal_inputs/
- https://github.com/vllm-project/vllm
- https://developer.nvidia.com/video-codec-sdk
- https://docs.nvidia.com/deploy/mps/
