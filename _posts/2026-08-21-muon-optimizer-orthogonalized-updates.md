---
title: "[Deep Learning] Muon — 행렬 업데이트를 직교화하는 옵티마이저"
excerpt: "An introduction to the Muon optimizer and orthogonalized matrix updates with Newton-Schulz iteration by sehoon-lee"
description: "Muon 옵티마이저가 행렬 업데이트를 직교화하는 이유와 Newton–Schulz 반복, AdamW와의 혼합 구성 및 적용 시 주의사항을 정리합니다."

categories:
    - AI
tags:
    - [Deep Learning, Muon, Optimizer, Newton-Schulz, PyTorch]

toc: true
toc_sticky: true

date: 2026-08-21
last_modified_at: 2026-08-21

math: false
---

## 핵심 요약

- Muon은 은닉층의 2차원 가중치에서 모멘텀 행렬을 Newton–Schulz 반복으로 근사 직교화한 뒤 업데이트한다.
- 임베딩·출력 헤드·편향·정규화 파라미터에는 AdamW를 함께 쓰는 혼합 구성이 기본이다.
- 논문의 계산 효율 향상은 특정 사전학습 실험 결과이며, 실제 도입 전 AdamW 기준선과 같은 데이터·스케줄로 수렴 시간과 메모리를 비교해야 한다.

## 1. AdamW만 바꾸면 학습이 빨라질까

같은 모델과 데이터로 사전학습을 반복하면 옵티마이저 상태가 차지하는 메모리와 목표 손실에 도달하는 시간이 큰 비용이 된다. AdamW는 각 파라미터 원소마다 1차 모멘트와 2차 모멘트를 추적해 안정적으로 학습하지만, 가중치 행렬이 가진 구조를 직접 이용하지는 않는다. 학습률만 키우면 발산 위험이 커지고, 배치를 늘려도 데이터 효율이 그대로 좋아지는 것은 아니다.

Muon은 이 문제를 은닉층 가중치를 하나의 행렬로 보는 방식으로 접근한다. 이름은 *MomentUm Orthogonalized by Newton-Schulz*에서 왔다. 일반적인 모멘텀 업데이트를 만든 뒤 원소별 크기를 보정하는 대신, 행렬의 특이값 방향을 고르게 만드는 근사 직교화 단계를 추가한다. 다만 모델 전체를 Muon 하나로 처리하지 않으며, 적용 범위를 정확히 나누는 것이 첫 번째 조건이다.

## 2. AdamW와 Muon의 차이

| 구분 | AdamW | Muon |
| --- | --- | --- |
| 주요 적용 대상 | 모델의 일반적인 파라미터 | 은닉층의 2차원 가중치 행렬 |
| 업데이트 보정 | 원소별 1·2차 모멘트 | 모멘텀 행렬의 근사 직교화 |
| 상태 버퍼 | 파라미터별 두 모멘트 | Muon 대상에는 모멘텀 버퍼 하나 |
| 추가 계산 | 주로 원소별 연산 | Newton–Schulz 행렬곱 반복 |
| 실제 구성 | 단독 사용 가능 | 나머지 파라미터용 AdamW와 함께 사용 |

직교화는 정사각 행렬만을 뜻하지 않는다. 선형층 가중치처럼 직사각형인 경우에는 행 또는 열이 직교하는 반직교 행렬에 가깝게 만든다. 계산이 비싼 SVD를 매 스텝 수행하는 대신 행렬곱으로 구성된 Newton–Schulz 다항 반복을 사용해 GPU에서 처리하기 쉽게 만든 것이 핵심이다.

## 3. Muon의 업데이트 순서

1. **기울기 계산**: 은닉층 가중치 행렬의 기울기를 구한다.
2. **모멘텀 누적**: 이전 상태와 현재 기울기를 합치고, 기본 설정에서는 Nesterov 모멘텀을 적용한다.
3. **크기 정규화**: 반복 계산이 안정적인 범위에 들어오도록 모멘텀 행렬의 크기를 조정한다.
4. **Newton–Schulz 반복**: PyTorch 2.13 기본값은 5회 반복이며, 모멘텀 행렬의 극분해에서 직교 성분에 가까운 업데이트를 근사한다.
5. **스케일과 감쇠 적용**: 행렬 모양에 따른 업데이트 크기를 보정하고 분리된 weight decay를 적용한 뒤 가중치를 갱신한다.

> Muon은 가중치 자체를 직교 행렬로 제한하지 않는다. 매 스텝의 모멘텀 기반 업데이트 방향을 근사 직교화한다.

이 차이를 놓치면 모델 표현력이 직교 제약으로 줄어든다고 오해하기 쉽다. 실제 목적은 일부 큰 특이 방향이 업데이트를 독점하지 않게 하고, 상대적으로 작은 방향도 학습에 반영되도록 업데이트의 스펙트럼을 재구성하는 데 있다.

## 4. 대규모 학습으로 확장한 방법

초기 Muon은 작은 모델의 학습 기록에서 주목받았지만, 큰 언어 모델에서는 행렬 모양마다 업데이트 RMS가 달라지고 장기 학습에서 가중치가 커지는 문제가 있었다. Moonshot AI의 기술 보고서는 weight decay를 추가하고, 행렬 크기에 따라 업데이트 RMS를 AdamW와 맞추는 방법을 제안했다. 보고서의 scaling-law 실험에서는 같은 성능에 필요한 학습 FLOPs가 AdamW의 약 52%라고 측정했으며, 5.7조 토큰으로 3B 활성·16B 전체 파라미터의 MoE 모델 Moonlight를 학습했다.

이 수치는 Muon이 모든 모델에서 학습 시간을 절반으로 만든다는 뜻이 아니다. 비교는 논문의 모델 구조, 데이터, 계산 최적 설정에 한정된다. Newton–Schulz의 추가 행렬곱, 분산 환경의 통신, 파라미터 그룹 구성에 따라 한 스텝의 시간은 오히려 늘 수 있다. 목표 손실까지의 전체 GPU 시간과 토큰 수를 함께 봐야 한다.

## 5. PyTorch 2.13 적용 예시

2026-08-19 기준 PyTorch 안정 버전 2.13.0에는 `torch.optim.Muon`이 포함되어 있다. 다음 예시는 모델의 은닉 블록을 명시적으로 선택하고, 그 안의 2차원 가중치만 Muon에 전달한다. `model.blocks`는 사용하는 모델 구조에 맞게 바꿔야 한다.

```
python -m pip install "torch==2.13.0"

import torch

# 모델 구조에 맞게 Transformer/CNN의 은닉 스택을 지정한다.
hidden_stack = model.blocks
muon_params = [p for p in hidden_stack.parameters() if p.ndim == 2]
muon_param_ids = {id(p) for p in muon_params}
adamw_params = [p for p in model.parameters() if id(p) not in muon_param_ids]

optim_muon = torch.optim.Muon(
    muon_params,
    lr=0.02,
    momentum=0.95,
    weight_decay=0.1,
)
optim_adamw = torch.optim.AdamW(
    adamw_params,
    lr=3e-4,
    weight_decay=0.01,
)

optim_muon.zero_grad(set_to_none=True)
optim_adamw.zero_grad(set_to_none=True)
loss = loss_fn(model(inputs), targets)
loss.backward()
optim_muon.step()
optim_adamw.step()
```

PyTorch 공식 API는 Muon에 2차원이 아닌 파라미터가 들어오면 오류를 발생시킨다. 임베딩과 최종 출력 헤드는 2차원인 경우에도 AdamW에 남기는 것이 원 설계의 권장 방식이다. 모델이 Q·K·V를 하나의 큰 행렬로 결합한다면 각각 분리했을 때의 차이도 검증해야 한다. 위 학습률은 공식 문서의 시작 예시일 뿐이며 기존 스케줄을 자동으로 보장하지 않는다.

## 6. 실무 검증 기준과 주의사항

- **파라미터 목록을 먼저 출력한다.** 이름, shape, Muon·AdamW 할당을 기록해 임베딩과 출력 헤드가 잘못 들어가지 않았는지 확인한다.
- **같은 예산으로 비교한다.** AdamW 기준선과 데이터 순서, warmup, weight decay, 총 토큰을 맞추고 validation loss까지의 시간과 GPU 메모리를 측정한다.
- **스텝 시간만 보지 않는다.** Muon은 추가 행렬곱이 있으므로 스텝당 시간과 목표 손실 도달 스텝이 서로 다른 방향으로 움직일 수 있다.
- **수치 안정성을 감시한다.** 업데이트 RMS, 가중치 RMS, gradient norm과 loss spike를 함께 기록한다. mixed precision과 분산 학습에서는 구현별 통신·누산 정밀도도 확인한다.
- **버전과 하드웨어를 고정한다.** PyTorch 2.13.0은 Python 3.10~3.15를 지원하며 공식 안정 CUDA 빌드는 12.6과 13.0이다. GPU 설치 명령은 운영체제와 드라이버에 맞춰 PyTorch 공식 선택기에서 정한다.

정리하면 Muon의 장점은 AdamW의 하이퍼파라미터를 단순히 바꾸는 데 있지 않다. 은닉층 가중치를 행렬로 보고 업데이트 방향의 특이값 구조를 직접 다룬다는 데 있다. 그래서 도입 여부도 옵티마이저 이름보다 파라미터 분리, 업데이트 스케일, 분산 통신을 포함한 전체 학습 파이프라인으로 판단해야 한다. 작은 모델에서 목표 손실까지의 시간과 메모리 사용량을 먼저 비교한 뒤 규모를 늘리는 것이 안전하다.

## 참고 출처

- [Keller Jordan — Muon: An optimizer for hidden layers in neural networks](https://kellerjordan.github.io/posts/muon/)
- [Liu et al. — Muon is Scalable for LLM Training](https://arxiv.org/abs/2502.16982)
- [MoonshotAI/Moonlight — 공식 분산 구현과 학습 예시](https://github.com/MoonshotAI/Moonlight)
- [PyTorch 2.13 — torch.optim.Muon 공식 API](https://docs.pytorch.org/docs/stable/generated/torch.optim.Muon.html)
- [PyTorch — 릴리스 호환성 표](https://github.com/pytorch/pytorch/blob/main/RELEASE.md)
- [PyTorch Foundation — Using Muon Optimizer with DeepSpeed](https://pytorch.org/blog/using-muon-optimizer-with-deepspeed/)

검증 기준일: 2026-08-19. PyTorch 2.13.0 안정 문서와 공식 소스, Muon 원 설계 글, arXiv:2502.16982 및 Moonshot AI 공식 저장소를 기준으로 작성했다. 성능 수치는 해당 연구의 사전학습·scaling-law 조건에 한정되며, 실제 결과는 모델 구조, 데이터, 정밀도, GPU와 분산 구성에 따라 달라진다.
