---
title: "[VLM] SigLIP 2 — NaFlex로 원본 비율과 고밀도 특징을 함께 지키기"
excerpt: "A review of SigLIP 2 and NaFlex for preserving native aspect ratios and dense visual features by sehoon-lee"
description: "SigLIP 2의 학습 목표와 NaFlex가 원본 종횡비를 보존하는 방식, 고밀도 특징 활용과 실무 적용 시 주의사항을 정리합니다."

categories:
    - Paper
tags:
    - [VLM, SigLIP 2, NaFlex, Vision Encoder, Dense Features]

toc: true
toc_sticky: true

date: 2026-08-21
last_modified_at: 2026-08-21

math: false
---

## 핵심 요약

- SigLIP 2는 이미지·텍스트 정렬에 캡셔닝·위치 학습과 자기지도 손실을 더해 전역 의미와 패치 단위 표현을 함께 개선한 비전-언어 인코더다.
- NaFlex는 이미지를 정사각형으로 강제하지 않고 원본 종횡비를 최대한 유지하면서 패치 수의 상한을 맞춘다.
- 문서·화면·OCR처럼 비율 왜곡에 민감한 입력에 유리하지만, 실제 비용은 해상도가 아니라 생성되는 패치 수와 데이터 분포로 비교해야 한다.

## 1. 정사각형 리사이즈가 놓치는 것

영수증, 긴 웹 화면, 가로로 넓은 표를 VLM에 넣으면 사람에게는 선명한 글자가 모델에는 뭉개져 보일 수 있다. 많은 비전 인코더가 입력을 정해진 정사각형 크기로 맞추기 때문이다. 원본 비율을 무시하면 글자와 객체의 모양이 바뀌고, 비율을 유지한 채 여백을 채우면 실제 정보에 쓰이지 않는 패치가 늘어난다. 이미지 전체의 주제를 분류할 때는 영향이 작아도 OCR, 위치 찾기, 세그멘테이션처럼 패치 단위 정보가 중요한 작업에서는 문제가 커진다.

SigLIP 2는 이 문제를 비전 인코더의 학습 목표와 입력 처리 두 방향에서 다룬다. 기존 SigLIP의 이미지·텍스트 정렬 능력을 유지하면서 지역 특징을 학습하는 손실을 추가하고, NaFlex 변형에서는 한 체크포인트로 여러 패치 길이와 종횡비를 처리한다.

## 2. SigLIP에서 SigLIP 2로

| 구분 | 기존 SigLIP 중심 접근 | SigLIP 2 |
| --- | --- | --- |
| 이미지·텍스트 정렬 | 각 쌍의 일치 여부를 sigmoid loss로 학습 | 같은 정렬 손실을 기반으로 유지 |
| 지역 이해 | 주로 풀링된 전역 표현에 초점 | 캡셔닝·위치 예측과 패치 단위 자기지도 학습 추가 |
| 입력 크기 | 고정 해상도 체크포인트 중심 | FixRes와 가변 비율·길이의 NaFlex 제공 |
| 활용 | 제로샷 분류·검색·VLM 인코더 | 기존 활용에 OCR·위치·고밀도 예측 표현 강화 |

SigLIP 2는 생성형 VLM 자체가 아니라 이미지와 텍스트를 임베딩으로 바꾸는 이중 인코더다. 따라서 단독으로 긴 답변을 생성하지 않는다. 제로샷 분류와 이미지-텍스트 검색에 바로 쓰거나, 비전 타워를 LLM과 연결해 VLM의 앞단으로 사용한다. 논문은 ViT-B, L, So400m, g 네 규모를 공개해 추론 비용과 표현 성능을 선택할 수 있게 했다.

## 3. 전역 의미와 지역 특징을 함께 학습하는 순서

1. **이미지·텍스트 정렬**: 미니배치의 이미지와 텍스트 조합을 일치·불일치 문제로 만들고 sigmoid loss로 학습한다.
2. **디코더 기반 보조 학습**: 풀링 전 비전 특징에 학습용 디코더를 연결해 캡션, 지시 표현의 위치, 영역 캡션을 예측한다. 이 디코더는 표현 학습에만 쓰이며 공개 인코더에는 포함되지 않는다.
3. **지역-전역 자기증류**: 이미지 일부를 본 학생 인코더가 전체 이미지를 본 EMA 교사의 표현을 따라가게 한다.
4. **마스크 패치 예측**: 학생 입력 패치의 50%를 가리고 해당 위치의 교사 특징을 복원하게 해 패치별 의미를 강화한다.

논문에서 동결된 So/14 표현을 384 해상도로 평가했을 때 ADE20k 세그멘테이션 mIoU는 기존 SigLIP의 40.8에서 SigLIP 2의 45.4로 높아졌다. 이는 특정 프로브 설정의 결과이지 모든 데이터에서 보장되는 향상 수치는 아니다. 중요한 점은 이미지 전체 임베딩만 좋아진 것이 아니라, 깊이·표면 법선·세그멘테이션에 재사용할 수 있는 풀링 전 특징도 함께 개선됐다는 것이다.

## 4. NaFlex의 처리 과정

NaFlex는 먼저 목표 패치 수의 상한을 정한다. 그 안에서 높이와 너비가 패치 크기의 배수가 되도록 이미지를 리사이즈하되, 원본 종횡비의 왜곡이 가장 작아지는 격자를 선택한다. 이후 이미지를 패치 시퀀스로 만들고, 실제 길이가 목표보다 짧으면 패딩 마스크를 추가한다. 학습된 위치 임베딩은 직사각형 패치 격자에 맞게 보간하며, attention은 패딩 토큰을 무시한다.

> NaFlex의 핵심은 모든 이미지를 크게 만드는 것이 아니다. 문서는 더 많은 패치로 읽고, 단순한 자연 이미지는 더 적은 패치로 처리할 수 있도록 한 모델에서 계산 예산을 조절하는 것이다.

논문에서는 NaFlex가 OCR·문서·화면 중심 검색 벤치마크 대부분에서 고정 정사각형 변형보다 유리했고, 특히 패치 길이가 짧아 비율 왜곡의 영향이 큰 구간에서 차이가 컸다. 반면 자연 이미지 중심 평가에서는 B 크기의 고정 해상도 모델이 더 나은 경우도 있었다. NaFlex를 무조건 상위 모델로 보기보다 입력 형태와 패치 예산에 맞춰 선택해야 한다.

## 5. Transformers로 확인하기

2026-08-17 기준 Hugging Face 공식 안정 문서의 Transformers 5.12.0과 Google 공식 모델 카드를 기준으로 한 최소 예시다. 아래 체크포인트는 Apache-2.0 라이선스로 공개되어 있으며, 첫 실행에는 모델 가중치 다운로드가 필요하다.

```
pip install "transformers==5.12.0" torch pillow

from transformers import pipeline

classifier = pipeline(
    task="zero-shot-image-classification",
    model="google/siglip2-base-patch16-naflex",
)

result = classifier(
    "receipt.png",
    candidate_labels=["a receipt", "a product label", "a web page"],
)
print(result)
```

실제 서비스에서는 설치된 PyTorch와 GPU 드라이버의 호환성을 별도로 확인해야 한다. NaFlex 전처리는 공식 `AutoProcessor`가 패치 격자와 마스크를 생성하므로, 이미지를 임의의 정사각형으로 먼저 리사이즈하지 않는 것이 좋다. 텍스트는 학습 시 소문자화와 길이 64의 고정 패딩·잘림을 사용했으며, 공식 프로세서가 이 기본값을 처리한다.

## 6. 실무 적용 기준과 주의사항

- **문서와 자연 이미지를 분리해 측정한다.** 전체 평균만 보면 종횡비 보존의 효과가 가려질 수 있다. OCR 정확도, 검색 recall, 위치 정확도를 입력 유형별로 기록한다.
- **픽셀 크기보다 패치 수를 본다.** 패치 수가 늘면 attention 비용과 후단 VLM으로 전달할 이미지 토큰 수가 함께 증가할 수 있다. 지연 시간과 GPU 메모리를 같은 조건에서 비교한다.
- **고밀도 특징과 전역 임베딩을 구분한다.** 검색에는 풀링된 특징이 적합하지만 세그멘테이션과 깊이 추정에는 패치 특징과 별도 디코더가 필요하다.
- **다국어를 자동 보장으로 해석하지 않는다.** 논문 학습 혼합은 109개 언어를 포함하지만 언어별 데이터 양과 성능은 다르다. 한국어 라벨과 실제 업무 문서로 별도 검증한다.
- **모델 카드와 버전을 고정한다.** 체크포인트, 프로세서, Transformers 버전을 함께 기록해야 전처리 차이로 생기는 재현 오류를 줄일 수 있다.

정리하면 SigLIP 2의 변화는 더 큰 비전 인코더를 만드는 데만 있지 않다. 이미지-텍스트 정렬, 위치를 포함한 캡셔닝, 자기증류, 마스크 패치 예측을 단계적으로 결합해 전역 의미와 지역 정보를 함께 남긴다. 여기에 NaFlex가 입력 비율과 패치 예산을 조절할 수 있게 한다. 문서 이해나 화면 기반 VLM을 설계한다면 LLM 크기만 비교하기 전에 비전 인코더가 원본 구조를 얼마나 보존하는지부터 확인할 필요가 있다.

## 참고 출처

- [Tschannen et al., SigLIP 2: Multilingual Vision-Language Encoders with Improved Semantic Understanding, Localization, and Dense Features](https://arxiv.org/abs/2502.14786)
- [Google Research big_vision — SigLIP 2 공식 설정과 체크포인트 안내](https://github.com/google-research/big_vision/tree/main/big_vision/configs/proj/image_text)
- [Google — siglip2-base-patch16-naflex 모델 카드](https://huggingface.co/google/siglip2-base-patch16-naflex)
- [Hugging Face Transformers — SigLIP 2 공식 문서](https://huggingface.co/docs/transformers/en/model_doc/siglip2)

검증 기준일: 2026-08-17. 원 논문 arXiv:2502.14786v1, Google 공식 모델 카드와 저장소, Hugging Face Transformers 안정 문서 v5.12.0을 기준으로 작성했다. 벤치마크 수치는 논문의 동결 특징 프로빙 설정에 한정되며, 실제 성능과 자원 사용량은 입력 분포·패치 수·하드웨어에 따라 달라진다.
