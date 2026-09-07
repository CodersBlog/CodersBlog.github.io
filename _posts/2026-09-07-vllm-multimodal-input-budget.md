---
title: "[VLM 운영] 이미지·영상 입력 예산으로 OOM을 막는 법 — vLLM 멀티모달 제한 설계"
excerpt: "vLLM의 이미지·영상 요청 한도를 입력 계약으로 설계해 VLM OOM을 예방하는 방법 by sehoon-lee"
description: "멀티모달 입력의 개수, 프레임 수, 해상도를 제한하고 품질과 지연을 함께 검증하는 운영 절차입니다."
categories:
  - Infra
tags:
  - [vLLM, VLM, Multimodal, GPU Memory, SSRF]
toc: true
toc_sticky: true
date: 2026-09-07
last_modified_at: 2026-09-07
---

## 핵심 요약

멀티모달 VLM 서비스에서 OOM은 모델 가중치만의 문제가 아니다. 한 요청에 들어오는 이미지 수, 영상 프레임 수, 해상도는 비전 인코더 연산과 입력 토큰 수를 함께 늘린다. GPU 디코딩을 도입해 입력을 더 빨리 받아들이게 됐다면, 다음 단계는 그 입력이 서비스가 감당할 수 있는 크기인지 통제하는 일이다.

## 1. 요청의 최악값을 제품 계약으로 만든다

평소에는 정상인데 고해상도 사진 묶음이나 긴 동영상에서만 TTFT가 급격히 늘거나 비전 인코더 OOM이 난다면 입력 예산부터 점검한다. 이미지 장수만 세면 충분하지 않다. 5장의 512px 이미지와 5장의 4K 이미지는 비용이 다르고, 영상은 프레임 수와 가로·세로가 함께 작동한다.

예를 들어 고객 문의 API가 제품 사진 4장까지만 의미 있고, 현장 영상 요약은 24프레임이면 충분하다면 이것을 서버 경계로 둔다. 시작 예산은 이미지 최대 4장과 1024×1024, 영상 최대 1개와 24프레임 및 768×768처럼 명시한다. 이후 TTFT, 비전 인코더 시간, peak VRAM, p95 전체 지연, 오류율을 같은 요청 식별자로 기록한다.

## 2. vLLM에 개수·프레임·해상도를 함께 제한한다

vLLM의 `--limit-mm-per-prompt`는 개수만 주는 형식뿐 아니라 개수, 프레임, 가로, 세로를 함께 주는 JSON 형식을 지원한다. 운영에서는 후자를 사용해 최악 요청을 드러내는 편이 좋다.

```bash
vllm serve Qwen/Qwen3-VL-8B-Instruct \
  --limit-mm-per-prompt '{"image":{"count":4,"width":1024,"height":1024},"video":{"count":1,"num_frames":24,"width":768,"height":768}}'
```

빠르게 이미지 수만 막아야 할 때는 다음처럼 시작할 수 있다. 하지만 개별 해상도 예산이 명확하지 않으므로 임시 완화책으로 본다.

```bash
vllm serve Qwen/Qwen3-VL-8B-Instruct \
  --limit-mm-per-prompt.image 4
```

영상의 엔진 제한과 샘플링 정책도 같은 값으로 고정한다. 프레임 수를 줄인 결과가 사용자 품질 기준을 만족하는지는 대표 입력셋으로 확인해야 한다.

```bash
vllm serve Qwen/Qwen3-VL-8B-Instruct \
  --limit-mm-per-prompt '{"video":{"count":1,"num_frames":24,"width":768,"height":768}}' \
  --media-io-kwargs '{"video":{"num_frames":24}}'
```

## 3. 품질과 메모리를 같은 실험에서 본다

정상 크기, 제품이 허용하는 최대 크기, 의도적으로 초과한 입력의 세 묶음을 준비한다. 같은 모델, 프롬프트, 동시성에서 제한 전후의 TTFT, 전체 지연, peak VRAM을 비교한다. 초과 입력은 모델 OOM이 아니라 예측 가능한 요청 거부 또는 전처리 실패로 끝나야 한다.

이미지 수, 프레임 수, 해상도를 한 항목씩 바꾸며 품질 평가와 p95 지연을 함께 기록한다. GPU 메모리가 낮아졌다는 사실만으로 성공이라고 판단하면 안 된다. 비전 입력을 과도하게 줄여 답변 품질이 떨어졌을 수 있기 때문이다.

## 4. URL 입력에는 별도 보안 경계를 둔다

입력 예산은 자원 문제를 해결하지만, 원격 URL을 서버가 가져오는 구조의 SSRF 위험까지 해결하지는 않는다. 외부 URL을 꼭 받아야 한다면 업로드 프록시를 우선하고, 엔진이 URL을 직접 접근하면 허용 도메인과 리다이렉트 제한을 함께 적용한다.

```bash
export VLLM_MEDIA_URL_ALLOW_REDIRECTS=0

vllm serve Qwen/Qwen3-VL-8B-Instruct \
  --allowed-media-domains uploads.example.com cdn.example.com \
  --limit-mm-per-prompt '{"image":{"count":4,"width":1024,"height":1024}}'
```

API 게이트웨이 또는 업로드 서비스에서도 내부 IP 대역 차단, MIME 검증, 다운로드 바이트 제한을 중복 적용한다. `allowed-media-domains` 하나를 네트워크 격리의 대체재로 보면 안 된다.

## 5. 장애 분기와 롤백

제한 적용 뒤에도 OOM이 나면 먼저 실제 리사이즈 후 크기와 프레임 수를 확인한다. 다음으로 비전 인코더 메모리와 KV cache 경쟁을 분리한다. 입력 제한을 낮췄는데도 긴 텍스트 요청에서 같은 실패가 난다면 컨텍스트 길이, 동시성, KV cache가 원인일 가능성이 크다.

품질 문제가 나오면 전체 제한을 즉시 해제하지 않는다. 영상 프레임 또는 해상도를 직전 검증값으로 되돌리고, 이미지 수는 유지한 채 샘플별 평가를 다시 한다. OOM 완화가 급하면 동시 요청 상한을 임시로 낮춘 뒤 재측정한다.

## 결론

VLM의 멀티모달 입력 제한은 성능 튜닝의 부가 옵션이 아니라 요청 계약이다. 이미지·영상의 개수만 세지 말고 프레임과 해상도까지 상한으로 선언하고, TTFT·품질·오류율을 같은 실험에서 측정해야 한다.

## 참고 출처

- https://docs.vllm.ai/en/stable/features/multimodal_inputs/
- https://docs.vllm.ai/en/stable/configuration/engine_args/
- https://docs.vllm.ai/en/latest/api/vllm/config/multimodal/
