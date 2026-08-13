---
title: "[Vision] DINOv3 — Gram Anchoring으로 고밀도 특징을 지키는 자기지도 학습"
excerpt: "An introduction to DINOv3 and Gram Anchoring for preserving dense visual features by sehoon-lee"
description: "DINOv3의 자기지도 학습 흐름과 장시간 학습에서 고밀도 패치 특징을 보존하는 Gram Anchoring, 특징 추출과 실무 적용 시 주의사항을 정리합니다."

categories:
    - Paper
tags:
    - [DINOv3, Computer Vision, Self-Supervised Learning, Vision Transformer, Dense Features]

toc: true
toc_sticky: true

date: 2026-08-14
last_modified_at: 2026-08-14

math: false
---

## 핵심 요약

- DINOv3는 라벨이나 캡션 없이 학습한 비전 백본으로, 이미지 전체 의미뿐 아니라 패치 단위의 위치 정보까지 재사용할 수 있게 설계되었다.
- 장시간 학습에서 패치 특징의 품질이 무너지는 문제를 Gram Anchoring으로 억제한다.
- 실무에서는 먼저 백본을 고정하고 선형 헤드나 작은 디코더를 붙여 검증한 뒤, 마지막 수단으로 전체 파인튜닝을 고려하는 편이 안전하다.

## 1. 왜 또 하나의 비전 백본이 필요한가

불량 검출, 위성 영상 분석, 깊이 추정처럼 픽셀 위치가 중요한 문제에서는 이미지가 무엇인지 맞히는 것만으로 부족하다. 어느 영역이 같은 물체인지, 서로 다른 시점의 어느 패치가 대응하는지까지 표현해야 한다. 분류 데이터로 학습한 백본은 이미지 전체 의미에는 강하지만 패치 단위 특징이 필요한 작업에서는 별도 파인튜닝과 많은 라벨이 필요할 수 있다.

DINOv3는 이 문제를 라벨 없는 대규모 이미지에서 범용 시각 특징을 학습하는 방식으로 접근한다. Meta 연구진은 67억 파라미터 ViT-7B/16을 중심으로 작은 ViT와 ConvNeXt 모델까지 공개했다. 핵심은 모델 크기만 키운 것이 아니라, 긴 학습에서도 고밀도 특징이 흐려지지 않도록 학습 절차를 보완한 데 있다.

## 2. 기존 학습 방식과의 차이

| 방식 | 학습 신호 | 강점 | 주의점 |
| --- | --- | --- | --- |
| 지도 학습 | 클래스 라벨 | 목표 분류에 직접 최적화 | 라벨 비용과 클래스 범위 의존 |
| CLIP 계열 | 이미지-텍스트 쌍 | 언어 기반 zero-shot 활용 | 고품질 캡션·메타데이터 필요 |
| DINOv3 | 이미지 자체 | 전역·패치 특징을 함께 재사용 | 텍스트 정렬은 별도 후처리 필요 |

DINOv3가 바로 객체 탐지기나 세그멘테이션 모델인 것은 아니다. 입력 이미지를 범용 특징으로 바꾸는 백본이며, 목적에 따라 선형 분류기·DPT 디코더·탐지 헤드 등을 뒤에 붙인다. 따라서 완성 모델끼리 비교하기보다 같은 헤드를 사용했을 때 백본 특징이 얼마나 잘 전이되는지를 봐야 한다.

## 3. DINOv3의 학습 흐름

1. **여러 크롭 생성**: 한 이미지에서 전역 크롭과 지역 크롭을 만들어 서로 다른 시야를 구성한다.
2. **교사-학생 자기증류**: 학생은 다른 크롭을 보더라도 교사의 전역 표현과 일관된 출력을 만들도록 학습한다.
3. **마스킹 패치 예측**: iBOT 손실로 가린 패치의 표현을 복원하며 지역 구조를 학습한다.
4. **표현 분산 유지**: KoLeo 정규화로 특징이 일부 지점에 몰리는 것을 줄인다.
5. **Gram Anchoring과 고해상도 적응**: 패치 관계를 안정화한 뒤 높은 해상도 입력에 맞춘다.

공식 모델 카드에 따르면 웹 이미지용 LVD-1689M은 약 16억 8,900만 장으로 구성되며, 별도로 4억 9,300만 장 규모의 위성 영상용 SAT-493M 모델도 제공된다. 즉 같은 자기지도 알고리즘을 자연 이미지와 항공 영상에 적용하되, 도메인에 맞는 사전학습 데이터와 정규화를 선택한다.

## 4. Gram Anchoring의 역할

모델을 오래 학습하면 분류 같은 전역 지표는 좋아져도 패치 특징 사이의 경계가 흐려질 수 있다. DINOv3 논문은 특히 ViT-Large보다 큰 모델의 긴 학습에서 이 현상을 관찰했다. 객체 내부의 비슷한 패치는 가깝고 경계 밖 패치는 멀어야 하는데, 학습이 진행되면서 이 관계가 변하면 깊이 추정이나 패치 매칭 같은 고밀도 작업이 손해를 본다.

Gram Anchoring은 기준 교사가 만든 패치 특징의 쌍별 유사도 구조, 즉 Gram 행렬을 현재 모델이 유지하도록 제약한다. 개별 패치 값을 그대로 복사시키기보다 패치와 패치 사이의 관계를 고정점으로 삼는 방식이다. 공식 학습 절차도 사전학습, Gram Anchoring, 고해상도 적응의 세 단계로 나뉜다.

> 전역 분류 정확도만 확인하면 고밀도 특징의 열화를 놓칠 수 있다. 세그멘테이션, 깊이, 대응점처럼 공간 정보를 쓰는 다운스트림 평가를 함께 봐야 한다.

## 5. 특징 추출 예시

2026-08-12 기준 Hugging Face Transformers는 4.56.0부터 DINOv3 백본을 지원한다. 다음 예시는 비교적 작은 ViT-S/16 모델에서 이미지 전체를 나타내는 CLS 특징과 16×16 패치 특징을 분리한다.

```text
pip install "transformers>=4.56.0" torch pillow

from PIL import Image
import torch
from transformers import AutoImageProcessor, AutoModel

model_id = "facebook/dinov3-vits16-pretrain-lvd1689m"
processor = AutoImageProcessor.from_pretrained(model_id)
model = AutoModel.from_pretrained(model_id).eval()

image = Image.open("image.jpg").convert("RGB")
inputs = processor(images=image, return_tensors="pt")

with torch.inference_mode():
    hidden = model(**inputs).last_hidden_state

cls_feature = hidden[:, 0]
start = 1 + model.config.num_register_tokens
patch_features = hidden[:, start:]

print(cls_feature.shape, patch_features.shape)
```

CLS 특징은 이미지 검색이나 분류에, 패치 특징은 세그멘테이션·유사 영역 탐색·키포인트 매칭에 사용할 수 있다. 운영 환경에서는 입력 해상도와 배치 크기, 모델 크기에 따른 지연 시간과 메모리를 직접 측정해야 한다.

## 6. 실무 적용과 주의사항

- **작게 시작한다.** ViT-7B는 67억 파라미터다. 먼저 2,100만 파라미터 ViT-S/16이나 2,900만 파라미터 ConvNeXt-Tiny로 전이 가능성을 확인하는 편이 현실적이다.
- **백본을 먼저 고정한다.** 공식 모델 카드는 동결 특징이 충분히 강하므로 전체 파인튜닝을 마지막 수단으로 권장한다. 선형 프로브나 작은 헤드부터 비교한다.
- **도메인 차이를 검증한다.** 자연 이미지 모델을 의료·제조·위성 영상에 바로 적용하면 색상, 해상도, 촬영 장비 차이로 성능이 달라질 수 있다.
- **편향과 라이선스를 확인한다.** 모델 카드는 지역·소득 구간별 성능 차이를 보고하며, 코드와 가중치는 DINOv3 License를 따른다. 배포 전 사용 조건을 별도로 검토해야 한다.

DINOv3의 실무적 가치는 모든 문제를 하나의 거대 모델로 끝내는 데 있지 않다. 한 번 계산한 범용 특징을 여러 비전 작업에서 공유하고, 적은 라벨과 작은 헤드로 빠르게 가능성을 검증할 수 있다는 데 있다. 특히 픽셀 위치가 중요한 문제라면 분류 정확도뿐 아니라 패치 특징의 안정성을 함께 보는 것이 핵심이다.

## 참고 출처

- [DINOv3 원논문 — arXiv:2508.10104](https://arxiv.org/abs/2508.10104)
- [Meta AI — DINOv3 공식 소개](https://ai.meta.com/blog/dinov3-self-supervised-vision-model/)
- [facebookresearch/dinov3 — 공식 코드와 모델 목록](https://github.com/facebookresearch/dinov3)
- [DINOv3 Model Card — 데이터, 사용 범위, 한계](https://github.com/facebookresearch/dinov3/blob/main/MODEL_CARD.md)
- [Hugging Face Transformers — DINOv3 문서](https://huggingface.co/docs/transformers/model_doc/dinov3)

검증 기준일: 2026-08-12. 공식 저장소의 전체 학습·평가 코드는 Python 3.11, PyTorch 2.7.1 이상, Linux 환경을 요구한다. 위 코드는 사전학습 가중치를 이용한 간단한 특징 추출 예시이며, 실제 배포 전 선택한 모델의 라이선스·가중치 접근 조건·메모리 요구량을 다시 확인해야 한다.
