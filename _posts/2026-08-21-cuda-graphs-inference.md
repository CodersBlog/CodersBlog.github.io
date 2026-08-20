---
title: "[CUDA] CUDA Graphs로 반복 추론의 커널 실행 오버헤드 줄이기"
excerpt: "A practical guide to reducing repeated GPU inference launch overhead with CUDA Graphs by sehoon-lee"
description: "CUDA Graphs가 반복 GPU 추론의 커널 실행 오버헤드를 줄이는 원리와 캡처·재실행 흐름, 적용 조건과 주의사항을 정리합니다."

categories:
    - Infra
tags:
    - [CUDA, CUDA Graphs, GPU Inference, Kernel Launch, NVIDIA]

toc: true
toc_sticky: true

date: 2026-08-21
last_modified_at: 2026-08-21

math: false
---

## 핵심 요약

- CUDA Graphs는 반복되는 커널·메모리 복사·동기화 순서를 그래프로 묶어 한 번의 호출로 제출한다.
- 짧은 커널을 많이 실행하는 추론처럼 계산 시간에 비해 실행 요청 비용이 큰 작업에서 효과가 크다.
- 그래프 생성과 인스턴스화 비용이 있으므로 같은 실행 구조를 충분히 재사용할 수 있는지 먼저 확인해야 한다.

## 1. GPU가 빠른데도 추론이 끊기는 이유

작은 배치로 실시간 추론을 수행하면 GPU 연산 자체보다 커널을 하나씩 제출하는 비용이 눈에 띌 수 있다. CPU는 전처리, 프레임워크 실행, 커널 인자 준비를 거쳐 GPU에 작업을 전달한다. 각 커널이 수 마이크로초 안에 끝나는 상황에서 이 제출 과정이 반복되면 프로파일러 타임라인에 커널 사이의 빈 구간이 생긴다. GPU 계산량을 줄였는데도 지연 시간이 기대만큼 내려가지 않는 이유 중 하나다.

CUDA Graphs는 반복되는 작업 순서를 미리 기록하고 재사용한다. 커널 실행뿐 아니라 메모리 복사와 의존 관계까지 하나의 그래프로 표현한 뒤, 실행 가능한 그래프를 한 번 호출해 GPU에 제출한다. 모델 구조와 텐서 크기가 비교적 일정한 추론 루프, 반복 시뮬레이션, 여러 개의 짧은 전처리 커널이 이어지는 파이프라인이 대표적인 적용 대상이다.

## 2. 일반 스트림 실행과 CUDA Graphs

| 구분 | 일반 스트림 실행 | CUDA Graphs |
| --- | --- | --- |
| 작업 제출 | 커널과 복사를 매번 개별 호출 | 기록된 작업 묶음을 한 번에 호출 |
| 초기 비용 | 작음 | 정의와 인스턴스화 비용 발생 |
| 동적 구조 | 매 반복 변경이 쉬움 | 토폴로지 변경 시 갱신 또는 재생성 필요 |
| 적합한 작업 | 호출 수가 적거나 구조가 자주 바뀜 | 동일 구조의 짧은 작업을 반복 |

CUDA Graphs는 커널 퓨전과 목적이 겹쳐 보이지만 적용 계층이 다르다. 커널 퓨전은 여러 연산을 하나의 커널로 합쳐 중간 메모리 접근과 개별 실행을 줄인다. CUDA Graphs는 커널 구현을 바꾸지 않고 여러 GPU 작업의 제출과 의존 관계를 묶는다. 따라서 그래프를 적용해도 각 커널 사이의 전역 메모리 왕복은 남을 수 있으며, 메모리 대역폭이 병목이라면 커널 퓨전이나 연산 재구성이 추가로 필요하다.

## 3. 정의·인스턴스화·실행의 세 단계

1. **정의**: 커널, 메모리 복사, 이벤트와 각 작업의 의존 관계를 그래프로 만든다. Graph API로 노드를 직접 추가하거나 기존 스트림 코드를 캡처할 수 있다.
2. **인스턴스화**: `cudaGraph_t`를 검증하고 실행 최적화를 적용해 `cudaGraphExec_t`를 만든다. 이 단계의 비용은 반복 실행으로 분산해야 한다.
3. **실행**: `cudaGraphLaunch()`로 실행 가능한 그래프를 스트림에 제출한다. 같은 인스턴스는 다시 인스턴스화하지 않고 여러 번 실행할 수 있다.

> 그래프가 빠른지는 한 번의 실행만 재서 판단할 수 없다. 생성·인스턴스화·첫 실행과 반복 실행을 구분하고, 전체 요청 수에서 초기 비용이 얼마나 상쇄되는지 봐야 한다.

## 4. Stream Capture 기본 예시

기존 코드가 하나의 CUDA 스트림에 순서대로 작업을 넣고 있다면 Stream Capture가 가장 단순한 시작점이다. 캡처 구간에서는 작업이 즉시 실행되지 않고 그래프 노드로 기록된다. 캡처를 끝낸 뒤 실행 그래프를 만들고 반복 구간에서 재사용한다.

```
cudaStream_t stream;
cudaGraph_t graph;
cudaGraphExec_t graph_exec;

cudaStreamCreate(&stream);

cudaStreamBeginCapture(stream, cudaStreamCaptureModeGlobal);
preprocess<<<grid, block, 0, stream>>>(input, work);
infer_step<<<grid, block, 0, stream>>>(work, output);
cudaMemcpyAsync(host_output, output, bytes,
                cudaMemcpyDeviceToHost, stream);
cudaStreamEndCapture(stream, &graph);

cudaGraphInstantiate(&graph_exec, graph, nullptr, nullptr, 0);

for (int request = 0; request < repeat_count; ++request) {
    cudaGraphLaunch(graph_exec, stream);
}
cudaStreamSynchronize(stream);

cudaGraphExecDestroy(graph_exec);
cudaGraphDestroy(graph);
cudaStreamDestroy(stream);
```

실제 코드에서는 모든 API가 캡처 가능한지 확인해야 한다. 레거시 NULL 스트림은 캡처할 수 없고, 여러 스트림을 함께 캡처할 때는 같은 캡처 그래프에 기록된 이벤트로 의존 관계를 연결해야 한다. 캡처 구간의 오류를 무시하면 종료 시 그래프가 무효화될 수 있으므로 각 CUDA 반환값을 검사한다.

## 5. 동적 입력과 Graph Update

추론 요청마다 입력 데이터는 달라도 실행 구조가 같다면 그래프를 그대로 재사용할 수 있다. 반면 커널 인자나 메모리 주소가 바뀌면 실행 그래프의 노드 매개변수를 갱신해야 한다. 변경 노드가 적고 핸들을 알고 있다면 개별 노드 업데이트가 유리하며, 캡처된 라이브러리 호출처럼 여러 노드가 함께 달라지면 새 그래프를 만든 뒤 `cudaGraphExecUpdate()`로 기존 실행 인스턴스를 갱신할 수 있다.

토폴로지나 노드 종류가 크게 달라지면 업데이트가 실패할 수 있고 재인스턴스화가 필요하다. 가변 배치, 입력 해상도, 시퀀스 길이가 자주 바뀌는 서비스에서는 대표 shape별 그래프를 캐시하는 방식과 재캡처 비용을 비교해야 한다. 무조건 모든 요청을 하나의 그래프에 맞추려고 패딩을 크게 늘리면 줄인 실행 오버헤드보다 불필요한 GPU 연산이 더 커질 수 있다.

## 6. 적용 기준과 측정 방법

- **먼저 타임라인을 본다.** Nsight Systems에서 CPU API 호출과 GPU 커널 사이의 빈 구간을 확인한다. 긴 단일 커널이 대부분을 차지하면 그래프 효과가 제한적일 수 있다.
- **워밍업을 분리한다.** 메모리 할당, 라이브러리 초기화, JIT 컴파일이 끝난 뒤 캡처한다. 첫 실행과 안정 상태 반복 실행의 지연 시간을 따로 기록한다.
- **동기화를 줄인다.** 각 커널 뒤의 불필요한 `cudaStreamSynchronize()`부터 제거한다. 같은 스트림의 작업 순서는 유지되므로 마지막에만 동기화해도 되는 경우가 많다.
- **실제 요청 분포로 잰다.** 평균뿐 아니라 p50·p95·p99 지연 시간, 처리량, CPU 사용률을 함께 비교한다. 동적 shape 재캡처가 잦다면 캐시 적중률도 측정한다.
- **자원 수명을 고정한다.** 캡처된 작업이 참조하는 버퍼와 커널 인자가 실행 시점에도 유효한지 관리한다. 요청마다 주소가 바뀌면 업데이트 전략을 명확히 둔다.

NVIDIA의 llama.cpp 적용 사례는 토큰 생성처럼 짧은 커널이 반복되는 추론에서 그래프가 커널 사이의 간격을 줄일 수 있음을 보여준다. 다만 특정 모델과 GPU에서 보고된 향상 수치를 그대로 기대값으로 사용하면 안 된다. CUDA Graphs의 핵심은 계산 자체를 빠르게 만드는 것이 아니라, 이미 정해진 GPU 작업을 반복 제출하는 비용을 줄이는 데 있다. 따라서 프로파일링에서 실행 요청이 병목임을 확인하고, 구조 재사용 횟수가 충분할 때 적용하는 것이 가장 안전하다.

## 참고 출처

- [NVIDIA CUDA Programming Guide — CUDA Graphs](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/cuda-graphs.html)
- [NVIDIA Technical Blog — Getting Started with CUDA Graphs](https://developer.nvidia.com/blog/cuda-graphs/)
- [NVIDIA Technical Blog — Optimizing llama.cpp AI Inference with CUDA Graphs](https://developer.nvidia.com/blog/optimizing-llama-cpp-ai-inference-with-cuda-graphs/)
- [NVIDIA Technical Blog — Kernel Fusion in NVIDIA CUDA](https://developer.nvidia.com/blog/kernel-fusion-in-nvidia-cuda-optimizing-memory-traffic-and-launch-overhead/)

검증 기준일: 2026-08-16. CUDA Programming Guide Release 13.2와 NVIDIA 공식 기술 자료를 기준으로 작성했다. API 지원 범위와 캡처 제한은 CUDA Toolkit 버전에 따라 달라질 수 있으므로 실제 적용 전 설치 버전의 Runtime API 문서를 다시 확인해야 한다.
