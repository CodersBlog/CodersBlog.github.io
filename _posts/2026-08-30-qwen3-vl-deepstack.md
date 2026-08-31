---
title: "[VLM] Qwen3-VL — DeepStack으로 여러 ViT 층의 시각 특징을 이어 붙이기"
excerpt: "A review of Qwen3-VL DeepStack for injecting multi-level ViT features into early LLM layers by sehoon-lee"
description: "Qwen3-VL의 DeepStack이 여러 ViT 층의 특징을 초기 LLM 층에 주입하는 구조와 처리 순서, 실무 적용 시 주의사항을 정리합니다."

categories:
    - Paper
tags:
    - [VLM, Qwen3-VL, DeepStack, ViT, Multimodal]

toc: true
toc_sticky: true

date: 2026-08-30
last_modified_at: 2026-09-01

math: false
---

## 핵심 요약

- 기존 VLM은 대개 ViT 마지막 층의 시각 토큰을 LLM 입력에 한 번 넣지만, Qwen3-VL의 DeepStack은 여러 ViT 깊이의 특징을 LLM 초기 여러 층에 나누어 더한다.
- 4B 공식 설정은 24층 ViT의 인덱스 5·11·17 특징을 사용한다. 이미지 토큰 길이를 늘리는 방식이 아니라 같은 시각 토큰 위치를 중간 특징으로 보강한다.
- 문서 OCR과 작은 객체처럼 세부 정보가 중요한 작업에 의미가 있지만, 모델 크기·입력 픽셀 예산·실행 런타임을 함께 고정해 검증해야 한다.

## 1. 마지막 ViT 층만 쓰면 생기는 문제

영수증의 작은 숫자, 화면 구석의 아이콘, 복잡한 도면의 선을 VLM에 물으면 이미지 전체의 의미는 맞히면서도 세부 위치나 문자를 놓치는 경우가 있다. 일반적인 VLM은 이미지를 패치로 나누고 ViT를 통과시킨 뒤, 마지막 층의 특징을 LLM 차원으로 투영해 텍스트 토큰과 함께 처리한다. 구조는 단순하지만 LLM이 받는 시각 정보가 비전 인코더의 마지막 표현에 집중된다.

ViT의 얕은 층은 경계와 질감 같은 지역 정보를, 깊은 층은 객체와 장면의 추상적 의미를 더 많이 담는 경향이 있다. 마지막 층만 전달하면 여러 깊이에 남아 있는 정보를 LLM이 직접 활용하기 어렵다. Qwen3-VL은 이 연결부를 DeepStack으로 바꿨다. 더 큰 이미지를 무조건 넣는 대신, 서로 다른 ViT 깊이에서 나온 특징을 LLM의 여러 층에 다시 주입한다.

## 2. DeepStack의 처리 순서

1. **동적 해상도 입력**: 이미지를 패치로 만들고 ViT가 시각 시퀀스를 처리한다.
2. **중간 특징 추출**: 최종 출력뿐 아니라 미리 정한 ViT 중간층의 특징을 꺼낸다. Qwen3-VL-4B-Instruct의 공식 `config.json`에는 24층 ViT와 `[5, 11, 17]`이 기록돼 있다.
3. **패치 병합과 차원 정렬**: 각 중간 특징을 별도 merger가 LLM hidden size에 맞추고, 2×2 공간 병합으로 시각 토큰을 압축한다.
4. **LLM 다층 주입**: 최종 시각 토큰은 입력 임베딩에 들어가고, 세 중간 특징은 LLM의 처음 세 층에서 같은 시각 토큰 위치의 hidden state에 순서대로 더해진다.
5. **텍스트 생성**: 보강된 시각·텍스트 표현을 이후 LLM 층이 함께 처리해 답을 생성한다.

> DeepStack의 핵심은 시각 토큰을 길게 복제하는 것이 아니라, 같은 토큰 자리에 서로 다른 ViT 깊이의 정보를 단계적으로 보충하는 데 있다.

Qwen3-VL 기술 보고서의 ablation은 내부 15B-A2B 모델을 2,000억 토큰으로 사전학습한 조건에서 DeepStack 적용 시 여러 시각 벤치마크 평균이 74.7에서 76.0으로 올랐다고 보고한다. 특정 내부 모델과 평가 묶음의 결과이므로 모든 체크포인트나 업무 데이터에서 1.3점 향상을 보장하는 수치로 해석하면 안 된다.

## 3. 기존 방식과 비교

| 구분 | 마지막 특징 1회 주입 | Qwen3-VL DeepStack |
| --- | --- | --- |
| ViT 활용 | 주로 마지막 층 출력 사용 | 마지막 출력과 여러 중간층 특징 사용 |
| LLM 연결 | 입력 단계에서 시각 토큰 삽입 | 입력 후 초기 LLM 층에도 중간 특징을 잔차 방식으로 추가 |
| 시각 토큰 길이 | 입력 해상도와 병합률에 따라 결정 | 중간 특징 때문에 시퀀스 길이를 복제하지 않음 |
| 기대 효과 | 구조가 단순하고 구현 호환성이 넓음 | OCR·문서·작은 객체 등 세부 시각 정보 보강 |
| 주의점 | 미세 특징이 마지막 표현에 의존 | 런타임이 DeepStack과 interleaved-MRoPE를 정확히 지원해야 함 |

Qwen3-VL은 DeepStack 외에도 시간·높이·너비 위치 차원을 주파수 축에 교차 배치하는 interleaved-MRoPE와, 비디오 프레임 시점을 텍스트 타임스탬프로 맞추는 방식을 함께 사용한다. 따라서 Qwen2.5-VL과의 성능 차이를 DeepStack 하나의 효과로만 설명할 수는 없다.

## 4. Transformers로 확인하기

아래 예시는 2026-09-01 기준 Qwen 공식 저장소가 요구하는 `transformers>=4.57.0`과 공식 4B 체크포인트를 사용한다. 처음 실행할 때 모델 파일을 내려받으며, PyTorch·CUDA·GPU 드라이버 호환성과 실제 메모리 요구량은 실행 환경에서 별도로 확인해야 한다.

```python
# pip install "transformers>=4.57.0" accelerate torch pillow

from transformers import AutoModelForImageTextToText, AutoProcessor

model_id = "Qwen/Qwen3-VL-4B-Instruct"
model = AutoModelForImageTextToText.from_pretrained(
    model_id, dtype="auto", device_map="auto"
)
processor = AutoProcessor.from_pretrained(model_id)

messages = [{
    "role": "user",
    "content": [
        {"type": "image", "image": "receipt.png"},
        {"type": "text", "text": "영수증의 총액과 날짜를 읽어줘."},
    ],
}]

inputs = processor.apply_chat_template(
    messages, tokenize=True, add_generation_prompt=True,
    return_dict=True, return_tensors="pt"
).to(model.device)
output = model.generate(**inputs, max_new_tokens=128)
answer = processor.batch_decode(
    output[:, inputs.input_ids.shape[1]:], skip_special_tokens=True
)
print(answer[0])
```

공식 설정의 `max_position_embeddings`는 262,144이지만, 이미지와 비디오도 컨텍스트 예산을 사용한다. 256K를 곧바로 순수 텍스트 256K와 같은 비용으로 보거나, 임의의 YaRN 설정으로 1M을 켠 뒤 같은 품질을 기대해서는 안 된다.

## 5. 실무 시사점과 주의사항

- **세부 과제로 평가한다.** 일반 VQA 평균만 보지 말고 OCR 정확도, 작은 객체 grounding, 표 셀 복원처럼 DeepStack의 효과가 드러날 지표를 별도로 둔다.
- **입력 예산을 고정한다.** 원본 이미지가 같아도 processor의 최소·최대 픽셀 설정에 따라 시각 토큰 수와 지연 시간이 달라진다. 체크포인트, processor 설정, 프레임 샘플링을 함께 기록한다.
- **포팅 구현을 검증한다.** 양자화나 다른 런타임으로 옮길 때 중간 ViT 특징이 올바른 LLM 층과 시각 토큰 위치에 더해지는지 확인해야 한다. 텍스트 생성만 된다고 멀티모달 경로가 정확하다는 뜻은 아니다.
- **환각 방지는 별도 문제다.** 세부 특징이 풍부해져도 보이지 않는 문자나 수치를 추측할 수 있다. 읽을 수 없는 값은 모른다고 답하게 하고, 좌표·OCR 결과를 원본과 대조한다.

정리하면 Qwen3-VL의 DeepStack은 비전 인코더와 LLM 사이를 한 번 연결하던 관행을 여러 깊이의 연결로 바꾼다. 실제 도입에서는 모델 크기보다 먼저 어떤 ViT 특징이 어느 LLM 층에 들어가는지, 그리고 배포 런타임이 그 경로를 빠짐없이 구현하는지 확인할 필요가 있다.

## 참고 출처

- [Bai et al., Qwen3-VL Technical Report](https://arxiv.org/abs/2511.21631)
- [QwenLM/Qwen3-VL 공식 저장소](https://github.com/QwenLM/Qwen3-VL)
- [Qwen3-VL-4B-Instruct 공식 config.json](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct/blob/main/config.json)
- [Hugging Face Transformers Qwen3-VL 공식 문서](https://huggingface.co/docs/transformers/model_doc/qwen3_vl)
- [Meng et al., DeepStack: Deeply Stacking Visual Tokens is Surprisingly Simple and Effective for LMMs](https://arxiv.org/abs/2406.04334)

검증 기준일: 2026-09-01. 수치와 구조는 Qwen3-VL 원 논문, Qwen 공식 저장소·공식 모델 설정, Transformers 공식 문서를 기준으로 교차 확인했다.
