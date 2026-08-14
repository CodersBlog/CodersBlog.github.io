---
title: "[Time Series] 시계열에도 파운데이션 모델이 왔다 — 학습 없이 예측한다는 것"
excerpt: "Where time series foundation models stand in 2026 by Junhyuns"
description: "데이터셋마다 모델을 새로 학습하던 시계열 예측에 사전학습 모델이 들어왔습니다. Chronos와 TimesFM을 중심으로 제로샷 예측이 어디까지 왔는지, 그리고 아직 무엇이 안 되는지 정리합니다."

categories:
    - Paper
tags:
    - [Time Series, Foundation Model, Zero-shot, Forecasting, Chronos, TimesFM]

toc: true
toc_sticky: true

date: 2026-08-14
last_modified_at: 2026-08-14

math: true
---

이 블로그에서 시계열을 마지막으로 다룬 것이 [SegRNN](/posts/SegRNN/) 리뷰였고, 2024년 1월이었습니다. 2년 반이 지났습니다.

그 사이에 이 분야에서 전제 하나가 바뀌었습니다. 그때 우리가 당연하게 깔고 있던 것, **"데이터셋마다 모델을 새로 학습한다"** 는 전제입니다.

## 무엇이 달라졌나

[SegRNN](/posts/SegRNN/)도, 그 앞의 [서베이](/posts/TS_Survey/)에서 정리한 CNN·RNN·Attention 계열도 전부 같은 방식이었습니다. 예측할 데이터셋을 정하고, 그 데이터로 모델을 학습시키고, 그 데이터에 대해 예측합니다.

지금은 여기에 다른 선택지가 생겼습니다. 여러 도메인의 시계열을 대규모로 사전학습한 모델에 **내 데이터를 넣기만 하면** 예측이 나옵니다. 학습 단계가 아예 없습니다.

![img_file](/assets/img/post/ts-foundation-models/shift.svg){: .align-center}*두 방식의 차이만 남겨 그린 개념도입니다*

LLM에서 익숙한 그림입니다. 다만 시계열은 여기 도달하는 데 텍스트보다 오래 걸렸습니다.

## 왜 시계열은 늦었나

텍스트에는 **공통 어휘**가 있습니다. 어느 문서에서 온 "사과"든 같은 토큰입니다.

시계열에는 그게 없습니다. 전력 사용량은 kW 단위로 수천을 오가고, 주가는 원 단위로 수만을 오가고, 센서값은 0과 1 사이입니다. 주기도 도메인마다 다릅니다. **같은 숫자 100이 데이터셋마다 전혀 다른 것을 뜻합니다.**

[Chronos](https://openreview.net/forum?id=gerNCVqqtR)(TMLR 2024)의 접근이 이 지점을 정면으로 다룹니다. 시계열을 **스케일링한 뒤 양자화해서 토큰 열로 바꾸고**, 그 토큰들로 언어모델을 교차 엔트로피 손실로 학습시킵니다.

논문 제목이 "Learning the Language of Time Series" 인 이유입니다. 스케일을 걷어내고 나면 시계열도 **공통 어휘로 쓸 수 있다**는 것이 핵심 주장입니다.

> 토큰화가 왜 필요한지, 왜 모델이 텍스트를 그대로 못 보는지는 [토큰이란 무엇인가](/posts/llm-token-basics/) 편에서 다뤘습니다. 시계열도 같은 문제를 같은 방식으로 풀고 있는 셈입니다.
{: .prompt-info }

## 지금 무엇이 있나

주요 구현들을 정리하면 이렇습니다.

| 모델 | 만든 곳 | ★ | 최근 푸시 |
|---|---|---|---|
| [TimesFM](https://github.com/google-research/timesfm) | Google Research | 27,306 | 2026-07-14 |
| [Chronos](https://github.com/amazon-science/chronos-forecasting) | Amazon Science | 5,705 | 2026-08-14 |
| [Moirai (uni2ts)](https://github.com/SalesforceAIResearch/uni2ts) | Salesforce AI Research | 1,572 | 2026-06-02 |
| [Time-MoE](https://github.com/Time-MoE/Time-MoE) | ICLR 2025 Spotlight | 991 | 2026-03-21 |

*(별 수와 푸시 날짜는 2026-08-14 `gh api` 로 직접 확인했습니다. 이 목록이 전부는 아닙니다.)*

네 곳 모두 **최근 6개월 안에 푸시**가 있습니다. 연구용으로 한 번 내고 만 프로젝트들이 아니라는 뜻입니다.

## 제로샷에서 인컨텍스트로

더 흥미로운 건 최근 1년의 방향입니다. 두 진영이 비슷한 곳으로 움직였습니다.

### Chronos-2 — 계열 사이에 정보를 공유한다

[Chronos-2](https://arxiv.org/abs/2510.15821)(Ansari 외, 2025-10)는 앞 세대의 한계를 이렇게 짚습니다.

> 기존 접근들은 대체로 **일변량 예측에 집중**해서, 다변량 데이터와 공변량이 중요한 실제 상황에서는 적용 범위가 제한된다.

해법은 **그룹 어텐션**입니다. 관련된 계열들, 다변량 계열의 각 변량, 또는 타깃과 공변량을 한 그룹으로 묶어 **그 안에서 정보를 공유**하게 합니다. 논문은 이것을 인컨텍스트 학습(ICL)이라고 부릅니다.

학습 데이터를 만든 방식도 눈에 띕니다. **합성 데이터로 일변량 계열에 다양한 다변량 구조를 씌워서** 학습시켰습니다. 실제 다변량 데이터가 부족한 문제를 우회한 것입니다.

저자들은 fev-bench, GIFT-Eval, Chronos Benchmark II 세 벤치마크에서 최고 성능을 보고하고 있습니다.

### TimesFM-ICF — 추론할 때 예시를 몇 개 준다

구글 쪽은 다른 각도에서 같은 곳에 닿았습니다. [TimesFM-ICF](https://research.google/blog/time-series-foundation-models-can-be-few-shot-learners/)(2025-09)는 **추론 시점에 예시 몇 개를 함께 넣어** 성능을 올립니다.

구분자 토큰으로 인컨텍스트 예시와 예측 대상 이력을 나누는 방식으로 계속 사전학습을 했고, 그 결과 **기본 모델 대비 6.8% 정확도 향상**을 보고했습니다.

여기서 중요한 건 수치보다 다음 문장입니다.

> **데이터셋별 파인튜닝 없이도 지도 파인튜닝에 준하는 성능**에 도달했다.

LLM에서 few-shot 프롬프팅이 하는 일과 정확히 같은 구조입니다. 시계열이 언어모델 쪽 기법을 그대로 흡수하고 있습니다.

## 그래서 지금 쓸 만한가

여기가 중요합니다. 벤치마크 수치는 대부분 모델을 만든 쪽이 보고한 것이라, 제3자 평가를 따로 봐야 합니다.

마침 적절한 연구가 있습니다. Sun과 Sun의 [하천유량 예측 평가](https://iopscience.iop.org/article/10.1088/3049-4753/ae4982)(*Machine Learning: Earth*, 2026-03)는 제목부터 "are we there yet?" 입니다.

CAMELS 데이터셋으로 최신 파운데이션 모델 네 개를 평가했고, 결과가 갈렸습니다.

| 조건 | 결과 |
|---|---|
| **일변량 제로샷** | 최고 성능 모델이 **CAMELS로 학습한 LSTM과 대등** |
| **다변량 제로샷** | 도메인 특화 모델에 **여전히 못 미침** |
| 파인튜닝을 붙이면 | 가능성 있음 |

일변량 결과가 인상적입니다. **그 데이터를 한 번도 본 적 없는 모델**이, 그 데이터로 학습시킨 LSTM과 비슷한 수준을 냈다는 뜻이니까요.

동시에 다변량 결과가 현실입니다. 전용 모델이 사라질 단계는 아닙니다.

> 제로샷의 의미는 "학습한 모델을 이긴다"가 아니라 **"학습 없이 거기 근처까지 온다"** 입니다. 학습 비용이 0이라는 점을 함께 놓고 봐야 제대로 된 비교가 됩니다.
{: .prompt-warning }

## 2년 전 글을 다시 보면

[서베이](/posts/TS_Survey/) 편에서 정리했던 숙제 하나가 기억납니다. 딥러닝 모델은 시계열을 일정 간격으로 이산화해야 해서, **결측이 있거나 불규칙한 간격으로 들어오는 데이터**에 약하다는 것이었습니다.

이번에 훑은 범위에서는 이 문제가 해결됐다는 근거를 찾지 못했습니다. 사전학습으로 옮겨간 것은 "어떤 데이터로 학습하느냐"이지 "어떤 모양의 데이터를 받느냐"가 아니었습니다.

[SegRNN](/posts/SegRNN/) 같은 전용 모델이 무의미해진 것도 아닙니다. **데이터가 충분하고 도메인이 고정돼 있다면** 그 데이터에 맞춘 모델이 여전히 유리합니다. 위 평가의 다변량 결과가 그 근거입니다.

바뀐 것은 **출발점**입니다. 예전에는 학습 데이터를 모으는 것이 첫 단계였는데, 이제는 사전학습 모델을 먼저 돌려보고 그 성능을 기준선으로 삼을 수 있습니다.

## 정리

시계열 예측에서 **학습이 놓이는 자리**가 바뀌었습니다.

데이터셋마다 모델을 학습시키던 것에서, 사전학습된 모델에 데이터를 넣는 쪽으로 선택지가 하나 늘었습니다. 스케일링과 양자화로 공통 어휘를 만드는 접근이 통했고, 최근에는 인컨텍스트 학습까지 들어왔습니다.

다만 만능은 아닙니다. 일변량 제로샷은 학습한 모델에 근접했지만 다변량은 아직이고, 불규칙 데이터 문제는 그대로 남아 있습니다.

**실무 관점에서 달라진 건 순서입니다.** 데이터를 모아 모델을 학습시키기 전에, 사전학습 모델을 먼저 돌려서 기준선을 잡아보는 것이 이제 합리적인 첫 수가 됐습니다.

## 참고

- [Chronos: Learning the Language of Time Series](https://openreview.net/forum?id=gerNCVqqtR) — TMLR 2024. 스케일링·양자화로 시계열을 토큰화하는 접근
- [Chronos-2: From Univariate to Universal Forecasting](https://arxiv.org/abs/2510.15821) — Ansari 외, 2025-10-17 (2026-08-14 arXiv 원문 확인). 그룹 어텐션과 인컨텍스트 학습
- [Time series foundation models can be few-shot learners](https://research.google/blog/time-series-foundation-models-can-be-few-shot-learners/) — Google Research, 2025-09-23 (2026-08-14 확인). TimesFM-ICF
- [Zero-shot forecasting of streamflow using time series foundation models: are we there yet?](https://iopscience.iop.org/article/10.1088/3049-4753/ae4982) — Sun & Sun, *Machine Learning: Earth* 2(1), 2026-03-20. 제3자 평가로 인용했습니다
- [Time Series Forecasting With Deep Learning: A Survey](/posts/TS_Survey/) — 이 글이 되짚는 출발점
- [SegRNN](/posts/SegRNN/) — 데이터셋별 학습을 전제하던 시기의 모델
- [토큰이란 무엇인가](/posts/llm-token-basics/) — 토큰화 개념
