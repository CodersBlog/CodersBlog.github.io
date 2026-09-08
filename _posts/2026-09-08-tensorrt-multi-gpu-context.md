---
title: "[TensorRT] 멀티 GPU 서버에서 엉뚱한 GPU를 잡는 문제 진단하기"
excerpt: "TensorRT 멀티 GPU 환경에서 논리 디바이스 매핑과 CUDA 컨텍스트 오류를 진단하는 방법 by sehoon-lee"
description: "GPU UUID와 논리 번호를 확인하고 TensorRT 객체, 스트림, 버퍼를 같은 CUDA 컨텍스트에 만드는 운영 절차를 정리합니다."
categories:
  - Infra
tags:
  - [TensorRT, CUDA, Multi GPU, GPU Inference, NVIDIA]
toc: true
toc_sticky: true
date: 2026-09-08
last_modified_at: 2026-09-08
---

대상 환경은 NVIDIA GPU가 두 장 이상인 Linux 서버에서 TensorRT Python 런타임으로 단일 GPU 추론 워커를 여러 개 운영하는 경우다. GPU 1을 지정했는데 GPU 0의 메모리가 늘거나, `invalid resource handle`, `invalid device context`, 예상 밖 OOM이 발생한다면 엔진 파일보다 디바이스 매핑과 CUDA 컨텍스트 생성 순서를 먼저 확인해야 한다.

이 글은 기존 [Dynamic Shape Profile 실전 절차](https://codersblog.github.io/posts/tensorrt-dynamic-shape-profiles/)의 다음 단계다. 이전 글은 입력 shape와 성능 계약을 다뤘지만, 엔진·스트림·버퍼가 어느 CUDA 컨텍스트에 만들어지는지는 가정으로 남겼다. 멀티 GPU 배포에서는 그 가정이 깨지기 때문에, 지금은 “엔진이 호환되는가”, “물리 GPU가 어떤 논리 번호로 보이는가”, “현재 컨텍스트가 어느 GPU인가”를 분리해야 한다.

## 1. 같은 GPU 문제처럼 보여도 세 층이 다르다

| 구분 | 확인 질문 | 대표 증상 |
| --- | --- | --- |
| 엔진 호환성 | 이 plan을 대상 GPU와 TensorRT 버전에서 역직렬화할 수 있는가? | compute capability 또는 버전 불일치로 로드 실패 |
| 논리 디바이스 매핑 | 프로세스의 `cuda:0`은 어느 물리 GPU인가? | 로그 번호와 nvidia-smi 번호를 같은 것으로 오해 |
| 활성 CUDA 컨텍스트 | Runtime, ExecutionContext, 스트림, 버퍼를 만들 때 어느 GPU가 current였는가? | 다른 GPU의 포인터와 스트림을 섞어 실행 오류 |

엔진이 GPU 1에서 로드된다는 사실만으로 버퍼와 스트림도 GPU 1에 있다는 뜻은 아니다. 반대로 GPU 0으로 보이는 로그가 반드시 물리 GPU 0을 뜻하지도 않는다.

## 2. 먼저 index 대신 UUID와 PCI bus ID를 기록한다

재부팅, 드라이버 구성, 컨테이너 설정이 달라지면 정수 index만으로는 배포 대상을 안정적으로 식별하기 어렵다. 실행 전 아래 결과를 배포 로그에 남긴다.

```bash
nvidia-smi --query-gpu=index,uuid,pci.bus_id,name,memory.used --format=csv
```

기대 관찰값은 각 index와 UUID, PCI bus ID가 한 줄씩 대응하는 것이다. 서비스 설정에는 가능하면 UUID를 저장하고, 장애 보고에는 세 값을 함께 남긴다. MIG를 사용한다면 물리 GPU UUID가 아니라 할당된 MIG 식별자를 기준으로 같은 절차를 적용한다.

## 3. 보이는 GPU를 하나로 줄인 뒤 논리 번호를 다시 읽는다

`CUDA_VISIBLE_DEVICES`는 가시성뿐 아니라 열거 순서도 바꾼다. 예를 들어 물리 GPU 2만 노출하면 프로세스 안에서는 그 장치가 논리 GPU 0이다.

```bash
export CUDA_DEVICE_ORDER=PCI_BUS_ID
export CUDA_VISIBLE_DEVICES=GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
python infer.py
```

이때 `infer.py` 안에서 선택할 번호는 원래의 2가 아니라 0이다. 정수 index와 UUID를 섞어 설정하거나, 외부 스케줄러가 이미 가시성을 제한했는데 코드에서 물리 index를 다시 지정하면 `invalid device ordinal`이 날 수 있다.

## 4. TensorRT 객체보다 먼저 current device를 고정한다

가시 GPU를 하나로 제한했더라도 워커 시작 시 current device를 확인하는 방어 코드를 둔다. 자동으로 CUDA 컨텍스트를 만드는 모듈은 피하고, 디바이스 선택 뒤에 TensorRT Runtime, 엔진, ExecutionContext, 스트림과 버퍼를 순서대로 만든다.

```python
from cuda.bindings import runtime as cudart

err, = cudart.cudaSetDevice(0)
assert err == cudart.cudaError_t.cudaSuccess

err, current = cudart.cudaGetDevice()
assert err == cudart.cudaError_t.cudaSuccess
assert current == 0

import tensorrt as trt

logger = trt.Logger(trt.Logger.INFO)
runtime = trt.Runtime(logger)

with open("model.engine", "rb") as f:
    engine = runtime.deserialize_cuda_engine(f.read())

if engine is None:
    raise RuntimeError("engine deserialize failed")

context = engine.create_execution_context()
if context is None:
    raise RuntimeError("execution context creation failed")

err, stream = cudart.cudaStreamCreate()
assert err == cudart.cudaError_t.cudaSuccess
print("logical CUDA device:", current)
```

기대 관찰값은 `logical CUDA device: 0`이고, 앞에서 지정한 UUID의 메모리만 엔진 역직렬화와 context 생성 시 증가하는 것이다. 입력·출력 버퍼도 반드시 이 코드 뒤에서 할당한다. PyTorch 텐서를 버퍼로 쓴다면 같은 논리 장치에서 만들고, 다른 장치의 `data_ptr()`를 TensorRT에 넘기지 않는다.

## 5. 애플리케이션과 trtexec를 같은 조건에서 비교한다

엔진 자체 문제인지 애플리케이션 초기화 순서 문제인지 분리하려면 같은 UUID만 노출한 상태에서 `trtexec`로 먼저 로드한다.

```bash
CUDA_DEVICE_ORDER=PCI_BUS_ID \
CUDA_VISIBLE_DEVICES=GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
trtexec --loadEngine=model.engine --verbose
```

- trtexec도 역직렬화에 실패하면 TensorRT 버전, platform, compute capability와 플러그인 로딩을 확인한다.
- trtexec는 성공하고 애플리케이션만 실패하면 import 시점의 자동 초기화, 스레드별 current device, 버퍼와 스트림 소유 장치를 확인한다.
- 실행은 성공하지만 다른 GPU 메모리도 증가하면 별도 프로세스, 모니터링 에이전트, 다른 워커의 PID를 분리해 본다.

## 6. 엔진 호환성 실패는 디바이스 선택 실패와 다르게 처리한다

TensorRT 엔진은 기본적으로 빌드한 버전과 GPU 아키텍처 조건의 영향을 받는다. 다른 GPU에서 역직렬화 오류가 난다면 current device를 여러 번 바꾸는 것으로 해결되지 않는다. 대상 UUID만 노출한 상태에서 ONNX로 엔진을 다시 빌드해 기준을 만든다.

```bash
CUDA_VISIBLE_DEVICES=GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
trtexec --onnx=model.onnx --saveEngine=model-target.engine
```

여러 아키텍처에 하나의 엔진을 배포해야 한다면 TensorRT 버전에 맞는 hardware compatibility 옵션을 검토하되, 범용성이 늘어나는 대신 일부 tactic이 제외되어 지연이나 처리량이 나빠질 수 있음을 별도 벤치마크로 확인한다.

## 7. 운영 분기와 롤백 기준

### 권장 배포 단위

가장 단순한 운영 경계는 GPU 한 장당 프로세스 한 개다. 스케줄러가 각 프로세스에 UUID 하나만 노출하고, 프로세스 내부는 항상 논리 GPU 0을 사용한다. 한 프로세스에서 여러 GPU를 스레드로 운영해야 한다면 각 스레드 시작 시 device를 선택한 뒤 그 스레드 소유의 ExecutionContext와 CUDA stream을 생성한다.

### 배포 전 관측값

- 워커 로그의 논리 번호, 대상 UUID, PCI bus ID가 배포 설정과 일치한다.
- 엔진 로드, warm-up, 실추론 동안 대상 GPU 한 장의 메모리만 증가한다.
- 기준 입력의 출력, p95 latency, peak VRAM이 변경 전 허용 범위 안이다.

### 즉시 롤백

대상 UUID가 로그와 다르거나, 비대상 GPU에 새 메모리 사용이 생기거나, warm-up에서 컨텍스트·핸들 오류가 한 번이라도 나오면 새 워커를 트래픽에서 제외한다. 마지막으로 검증된 GPU별 프로세스 설정으로 되돌리고, CUDA 오류가 난 프로세스는 예외 처리만으로 재사용하지 말고 재시작한다. 엔진 호환성 문제라면 기존 엔진으로 매핑만 되돌리지 말고 대상 GPU용 엔진을 다시 빌드해 별도 검증한다.

## 결론

멀티 GPU TensorRT 장애는 “GPU 번호를 바꿨다”만으로 해결되지 않는다. 먼저 UUID로 물리 장치를 고정하고, 프로세스 안의 논리 번호가 다시 매겨진다는 점을 확인한 뒤, current device를 설정하고 모든 TensorRT 객체·스트림·버퍼를 같은 컨텍스트에서 만들어야 한다. 엔진 호환성 오류는 이 실행 순서와 분리해 재빌드 또는 hardware compatibility 정책으로 다뤄야 재현 가능한 배포가 된다.

## 공식 출처

- [NVIDIA CUDA Programming Guide: CUDA environment variables](https://docs.nvidia.com/cuda/cuda-programming-guide/05-appendices/environment-variables.html)
- [NVIDIA TensorRT: Python API documentation](https://docs.nvidia.com/deeplearning/tensorrt/latest/inference-library/python-api-docs.html)
- [NVIDIA TensorRT: Engine compatibility](https://docs.nvidia.com/deeplearning/tensorrt/latest/inference-library/engine-compatibility.html)
- [NVIDIA TensorRT: Runtime API tutorial](https://docs.nvidia.com/deeplearning/tensorrt/latest/getting-started/quick-start-runtime-tutorial.html)

