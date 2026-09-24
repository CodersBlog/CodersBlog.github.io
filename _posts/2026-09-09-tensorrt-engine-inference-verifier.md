---
title: "[TensorRT] 엔진을 실제로 한 번 돌려 배포 가능 상태를 검증하는 법"
excerpt: "TensorRT 엔진을 지정 GPU에서 실제 enqueue하고 기준 출력까지 비교하는 배포 전 검증 절차 by sehoon-lee"
description: "TensorRT 10과 cuda.bindings로 엔진 역직렬화, shape 확정, 버퍼 바인딩, execute_async_v3, 출력 검증을 수행하는 운영 가이드입니다."
categories:
  - Infra
tags:
  - [TensorRT, CUDA, GPU Inference, Deployment, NVIDIA]
toc: true
toc_sticky: true
date: 2026-09-09
last_modified_at: 2026-09-09
---

<div style="max-width:860px;margin:0 auto;padding:28px 24px;background:#ffffff;color:#172033;font-family:Arial,'Noto Sans KR',sans-serif;line-height:1.72;">
<p style="margin:0 0 16px;font-size:16px;">대상 환경은 NVIDIA GPU가 여러 장인 Linux 서버에서 TensorRT 10 계열 Python 런타임과 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">cuda.bindings</code>로 단일 입력 TensorRT 엔진을 배포하는 경우입니다. 엔진 파일은 만들어졌는데 운영 워커에서 첫 요청이 실패하거나, 프로세스가 떠 있으면서도 출력이 전부 0·NaN·엉뚱한 클래스가 되는 증상을 다룹니다.</p>
  <p style="margin:0 0 20px;font-size:16px;">이 글은 전날 작성한 <a href="https://codersblog.github.io/posts/tensorrt-multi-gpu-context/" style="color:#2563eb;text-decoration:underline;">멀티 GPU 디바이스·컨텍스트 진단 글</a>의 다음 단계입니다. 이전 글은 물리 GPU와 논리 번호를 구분하고 TensorRT 객체보다 먼저 current device를 고정하는 데 집중했습니다. 그러나 엔진 역직렬화 성공은 입력 shape, 장치 버퍼, tensor address, enqueue, 출력 복사까지 성공했다는 뜻이 아닙니다. 그래서 이번에는 실제 기준 입력 한 건을 끝까지 실행해 “프로세스 시작 성공”과 “추론 가능”을 분리합니다.</p>

  <h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">1. 배포 전 검증의 합격선을 먼저 정한다</h2>
  <p style="margin:0 0 14px;font-size:16px;">검증기는 다음 네 단계를 모두 통과해야 성공으로 종료해야 합니다. 하나라도 실패하면 트래픽을 붙이지 않습니다.</p>
  <ol style="margin:0 0 18px;padding-left:24px;font-size:16px;">
    <li style="margin:7px 0;">지정한 논리 CUDA device를 선택한 뒤 엔진을 역직렬화한다.</li>
    <li style="margin:7px 0;">입력 shape를 확정하고 모든 출력 shape가 양수인지 확인한다.</li>
    <li style="margin:7px 0;">같은 device에서 버퍼와 stream을 만들고 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">execute_async_v3</code>를 실제 호출한다.</li>
    <li style="margin:7px 0;">출력이 유한값인지 확인하고, 기준 출력이 있으면 오차 허용값 안인지 비교한다.</li>
  </ol>
  <p style="margin:0 0 16px;font-size:16px;">대상 엔진은 신뢰할 수 있는 빌드 파이프라인에서 만든 파일이어야 합니다. TensorRT plan에는 실행 가능한 CUDA tactic이 들어 있으므로 출처가 불명확한 엔진은 역직렬화하지 않습니다.</p>

  <h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">2. 실행 환경과 물리 GPU를 먼저 기록한다</h2>
  <p style="margin:0 0 12px;font-size:16px;">장애 보고에 정수 index만 남기면 컨테이너나 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">CUDA_VISIBLE_DEVICES</code> 때문에 실제 장치를 다시 찾기 어렵습니다. 실행 전 아래 두 명령의 결과를 보관합니다.</p>
  <pre style="margin:12px 0 18px;padding:16px;overflow-x:auto;border-radius:8px;background:#0b1220;color:#e5eefc;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;color:#e5eefc;">nvidia-smi --query-gpu=index,uuid,pci.bus_id,name,memory.used --format=csv
python -c "import tensorrt as trt; from cuda.bindings import runtime as c; print('TensorRT', trt.__version__); print('CUDA runtime', c.cudaRuntimeGetVersion()[1])"</code></pre>
  <p style="margin:0 0 16px;font-size:16px;">기대 관찰값은 배포 설정의 GPU UUID와 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">nvidia-smi</code>의 UUID가 같고, 워커 이미지에 TensorRT 및 CUDA Runtime 버전이 숫자로 출력되는 것입니다. 여기서 import나 shared library 오류가 나면 엔진 문제가 아니라 런타임 이미지 문제로 분류합니다.</p>

  <h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">3. 애플리케이션 전에 trtexec로 엔진 경계를 확인한다</h2>
  <p style="margin:0 0 12px;font-size:16px;">동일한 GPU UUID만 노출한 상태에서 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">trtexec</code>를 실행합니다. 아래의 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">images</code>와 shape는 실제 엔진의 입력 이름과 profile 범위 안 값으로 바꿉니다.</p>
  <pre style="margin:12px 0 18px;padding:16px;overflow-x:auto;border-radius:8px;background:#0b1220;color:#e5eefc;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;color:#e5eefc;">CUDA_VISIBLE_DEVICES=GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
trtexec --loadEngine=model.engine \
  --shapes=images:1x3x640x640 \
  --warmUp=1000 --duration=10 --verbose</code></pre>
  <ul style="margin:0 0 18px;padding-left:24px;font-size:16px;">
    <li style="margin:7px 0;"><code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">trtexec</code>도 역직렬화에 실패하면 TensorRT 버전, plugin, GPU 호환성 또는 손상된 파일을 먼저 봅니다.</li>
    <li style="margin:7px 0;"><code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">trtexec</code>는 성공하고 Python 검증기만 실패하면 tensor 이름·dtype·shape·버퍼와 stream 수명 문제로 범위를 좁힙니다.</li>
    <li style="margin:7px 0;">두 경로가 모두 실행되지만 기준 출력과 다르면 전처리, layout, dtype, 정규화 순서를 비교합니다.</li>
  </ul>

  <h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">4. 실제 1회 추론 검증기를 둔다</h2>
  <p style="margin:0 0 12px;font-size:16px;">아래 검증기는 단일 입력과 하나 이상의 정적 또는 입력 shape로 계산 가능한 출력을 가진 엔진을 대상으로 합니다. 입력은 전처리까지 끝낸 NumPy 배열이고, 기준 출력은 tensor 이름을 key로 저장한 NPZ입니다. 데이터 의존적 출력 shape를 쓰는 엔진은 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">IOutputAllocator</code>가 필요하므로 이 검증기는 명시적으로 실패시킵니다.</p>
  <pre style="margin:12px 0 18px;padding:16px;overflow-x:auto;border-radius:8px;background:#0b1220;color:#e5eefc;font-size:13px;line-height:1.5;"><code style="font-family:Consolas,'Courier New',monospace;color:#e5eefc;">import argparse
import json
import os
import time

import numpy as np
from cuda.bindings import runtime as cudart


def check_cuda(result):
    err, *values = result
    if err != cudart.cudaError_t.cudaSuccess:
        raise RuntimeError(f"CUDA error: {err}")
    if not values:
        return None
    return values[0] if len(values) == 1 else tuple(values)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--expected")
    parser.add_argument("--device", type=int, default=0)
    parser.add_argument("--profile", type=int, default=0)
    parser.add_argument("--warmup", type=int, default=10)
    parser.add_argument("--runs", type=int, default=50)
    parser.add_argument("--rtol", type=float, default=1e-3)
    parser.add_argument("--atol", type=float, default=1e-4)
    args = parser.parse_args()

    check_cuda(cudart.cudaSetDevice(args.device))
    current = check_cuda(cudart.cudaGetDevice())
    if current != args.device:
        raise RuntimeError(f"device mismatch: requested={args.device}, current={current}")

    import tensorrt as trt

    logger = trt.Logger(trt.Logger.WARNING)
    runtime = trt.Runtime(logger)
    with open(args.engine, "rb") as f:
        engine = runtime.deserialize_cuda_engine(f.read())
    if engine is None:
        raise RuntimeError("engine deserialize failed")

    context = engine.create_execution_context()
    if context is None:
        raise RuntimeError("execution context creation failed")

    names = [engine.get_tensor_name(i) for i in range(engine.num_io_tensors)]
    input_names = [n for n in names if engine.get_tensor_mode(n) == trt.TensorIOMode.INPUT]
    output_names = [n for n in names if engine.get_tensor_mode(n) == trt.TensorIOMode.OUTPUT]
    if len(input_names) != 1:
        raise RuntimeError(f"this verifier expects one input, got {input_names}")

    input_name = input_names[0]
    host_input = np.ascontiguousarray(np.load(args.input))
    expected_dtype = np.dtype(trt.nptype(engine.get_tensor_dtype(input_name)))
    if host_input.dtype != expected_dtype:
        raise RuntimeError(f"input dtype mismatch: file={host_input.dtype}, engine={expected_dtype}")

    stream = check_cuda(cudart.cudaStreamCreate())
    device_buffers = []
    output_device_buffers = {}
    try:
        if args.profile != 0:
            ok = context.set_optimization_profile_async(args.profile, stream)
            if not ok:
                raise RuntimeError(f"cannot select optimization profile {args.profile}")

        declared_shape = tuple(engine.get_tensor_shape(input_name))
        if any(dim &lt; 0 for dim in declared_shape):
            if not context.set_input_shape(input_name, host_input.shape):
                raise RuntimeError(f"input shape rejected: {host_input.shape}")
        elif declared_shape != host_input.shape:
            raise RuntimeError(f"input shape mismatch: file={host_input.shape}, engine={declared_shape}")

        unresolved = context.infer_shapes()
        if unresolved:
            raise RuntimeError(f"unresolved tensor shapes: {list(unresolved)}")

        host_outputs = {}
        d_input = check_cuda(cudart.cudaMalloc(host_input.nbytes))
        device_buffers.append(d_input)
        if not context.set_tensor_address(input_name, int(d_input)):
            raise RuntimeError(f"cannot bind input tensor {input_name}")

        for name in output_names:
            shape = tuple(context.get_tensor_shape(name))
            if not shape or any(dim &lt; 0 for dim in shape):
                raise RuntimeError(f"unresolved or data-dependent output: {name} {shape}")
            dtype = np.dtype(trt.nptype(engine.get_tensor_dtype(name)))
            host_outputs[name] = np.empty(shape, dtype=dtype)
            ptr = check_cuda(cudart.cudaMalloc(host_outputs[name].nbytes))
            device_buffers.append(ptr)
            output_device_buffers[name] = ptr
            if not context.set_tensor_address(name, int(ptr)):
                raise RuntimeError(f"cannot bind output tensor {name}")

        check_cuda(cudart.cudaMemcpyAsync(
            d_input,
            host_input.ctypes.data,
            host_input.nbytes,
            cudart.cudaMemcpyKind.cudaMemcpyHostToDevice,
            stream,
        ))

        for _ in range(args.warmup):
            if not context.execute_async_v3(stream):
                raise RuntimeError("warm-up enqueue failed")
        check_cuda(cudart.cudaStreamSynchronize(stream))

        started = time.perf_counter()
        for _ in range(args.runs):
            if not context.execute_async_v3(stream):
                raise RuntimeError("inference enqueue failed")
        check_cuda(cudart.cudaStreamSynchronize(stream))
        avg_latency_ms = (time.perf_counter() - started) * 1000.0 / args.runs

        for name, host_output in host_outputs.items():
            ptr = output_device_buffers[name]
            check_cuda(cudart.cudaMemcpyAsync(
                host_output.ctypes.data,
                ptr,
                host_output.nbytes,
                cudart.cudaMemcpyKind.cudaMemcpyDeviceToHost,
                stream,
            ))
        check_cuda(cudart.cudaStreamSynchronize(stream))

        expected = np.load(args.expected) if args.expected else None
        checks = {}
        passed = True
        for name, actual in host_outputs.items():
            finite = bool(np.isfinite(actual).all())
            item = {"shape": list(actual.shape), "dtype": str(actual.dtype), "finite": finite}
            passed = passed and finite
            if expected is not None:
                if name not in expected.files:
                    raise RuntimeError(f"missing expected tensor: {name}")
                reference = expected[name]
                close = bool(np.allclose(actual, reference, rtol=args.rtol, atol=args.atol))
                item["max_abs_error"] = float(np.max(np.abs(actual - reference)))
                item["matches_expected"] = close
                passed = passed and close
            checks[name] = item

        report = {
            "status": "PASS" if passed else "FAIL",
            "pid": os.getpid(),
            "logical_device": current,
            "profile": args.profile,
            "input": {"name": input_name, "shape": list(host_input.shape), "dtype": str(host_input.dtype)},
            "outputs": checks,
            "warmup": args.warmup,
            "runs": args.runs,
            "average_latency_ms": round(avg_latency_ms, 3),
        }
        print(json.dumps(report, ensure_ascii=False, indent=2))
        if not passed:
            raise SystemExit(2)
    finally:
        for ptr in reversed(device_buffers):
            cudart.cudaFree(ptr)
        if stream:
            cudart.cudaStreamDestroy(stream)


if __name__ == "__main__":
    main()</code></pre>
  <p style="margin:0 0 12px;font-size:16px;">실행 명령은 다음과 같습니다. GPU UUID 하나만 노출했으므로 프로세스 내부의 선택 번호는 0입니다.</p>
  <pre style="margin:12px 0 18px;padding:16px;overflow-x:auto;border-radius:8px;background:#0b1220;color:#e5eefc;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;color:#e5eefc;">CUDA_VISIBLE_DEVICES=GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
python verify_trt_engine.py \
  --engine model.engine \
  --input sample_input.npy \
  --expected golden_outputs.npz \
  --device 0 --profile 0 --warmup 10 --runs 50</code></pre>
  <p style="margin:0 0 16px;font-size:16px;">기대 관찰값은 JSON의 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">status</code>가 PASS이고, <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">logical_device</code>가 0이며, 모든 출력의 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">finite</code>와 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">matches_expected</code>가 true인 것입니다. 기준 NPZ는 새 엔진의 첫 결과를 그대로 저장하지 말고, 검증된 기존 엔진이나 ONNX Runtime에서 같은 전처리 입력으로 만든 출력이어야 합니다.</p>

  <h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">5. 실제로 어느 GPU에서 실행됐는지 PID로 교차 확인한다</h2>
  <p style="margin:0 0 12px;font-size:16px;">검증기 JSON의 PID와 호스트의 프로세스 모니터 결과를 맞춥니다. 아래 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,monospace;">-i 1</code>은 호스트의 물리 index 예시이며, 검증기 안의 논리 device 0과 같은 UUID여야 합니다.</p>
  <pre style="margin:12px 0 18px;padding:16px;overflow-x:auto;border-radius:8px;background:#0b1220;color:#e5eefc;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;color:#e5eefc;">nvidia-smi pmon -i 1 -s um -d 1 -c 10</code></pre>
  <p style="margin:0 0 16px;font-size:16px;">기대 관찰값은 검증기 PID가 목표 물리 GPU 행에 나타나고, warm-up과 반복 실행 구간에 SM 사용률 또는 framebuffer memory가 관찰되는 것입니다. MIG에서는 일부 utilization 지표가 지원되지 않을 수 있으므로 UUID, PID, 메모리와 애플리케이션 결과를 함께 판단합니다.</p>

  <h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">6. 실패 위치별 진단 분기</h2>
  <table style="width:100%;border-collapse:collapse;margin:14px 0 20px;font-size:15px;">
    <thead style="background:#eaf2ff;">
      <tr style="border:1px solid #b9cff2;">
        <th style="border:1px solid #b9cff2;padding:10px;text-align:left;color:#12355b;">실패 지점</th>
        <th style="border:1px solid #b9cff2;padding:10px;text-align:left;color:#12355b;">우선 확인</th>
        <th style="border:1px solid #b9cff2;padding:10px;text-align:left;color:#12355b;">판정</th>
      </tr>
    </thead>
    <tbody style="background:#ffffff;">
      <tr style="border:1px solid #d7e1ef;"><td style="border:1px solid #d7e1ef;padding:10px;">import 또는 엔진 역직렬화</td><td style="border:1px solid #d7e1ef;padding:10px;">TensorRT·CUDA 버전, plugin 로드, 엔진 해시</td><td style="border:1px solid #d7e1ef;padding:10px;">런타임 이미지 또는 엔진 호환성 문제</td></tr>
      <tr style="border:1px solid #d7e1ef;"><td style="border:1px solid #d7e1ef;padding:10px;">input shape 거부</td><td style="border:1px solid #d7e1ef;padding:10px;">입력 이름, NCHW/NHWC, profile min·opt·max</td><td style="border:1px solid #d7e1ef;padding:10px;">전처리 또는 profile 계약 문제</td></tr>
      <tr style="border:1px solid #d7e1ef;"><td style="border:1px solid #d7e1ef;padding:10px;">unresolved output</td><td style="border:1px solid #d7e1ef;padding:10px;">shape tensor 입력, 데이터 의존적 출력 여부</td><td style="border:1px solid #d7e1ef;padding:10px;">추가 shape 입력 또는 IOutputAllocator 필요</td></tr>
      <tr style="border:1px solid #d7e1ef;"><td style="border:1px solid #d7e1ef;padding:10px;">enqueue·stream 오류</td><td style="border:1px solid #d7e1ef;padding:10px;">current device, 포인터 소유 GPU, stream 수명</td><td style="border:1px solid #d7e1ef;padding:10px;">CUDA 컨텍스트와 버퍼 소유권 문제</td></tr>
      <tr style="border:1px solid #d7e1ef;"><td style="border:1px solid #d7e1ef;padding:10px;">실행 성공, 출력 불일치</td><td style="border:1px solid #d7e1ef;padding:10px;">dtype, 정규화, 채널 순서, FP16 허용 오차</td><td style="border:1px solid #d7e1ef;padding:10px;">모델보다 입출력 계약을 먼저 비교</td></tr>
    </tbody>
  </table>

  <h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">7. 배포와 롤백 기준</h2>
  <h3 style="margin:20px 0 8px;font-size:19px;color:#24486d;">배포 허용</h3>
  <ul style="margin:0 0 18px;padding-left:24px;font-size:16px;">
    <li style="margin:7px 0;">목표 UUID만 노출한 환경에서 검증기가 3회 연속 PASS한다.</li>
    <li style="margin:7px 0;">기준 출력과의 오차가 모델 정밀도별 합의값 안이고 NaN·Inf가 없다.</li>
    <li style="margin:7px 0;">PID가 목표 물리 GPU에서만 보이며, warm-up과 반복 실행 latency가 기존 허용 범위 안이다.</li>
  </ul>
  <h3 style="margin:20px 0 8px;font-size:19px;color:#24486d;">즉시 롤백</h3>
  <p style="margin:0 0 16px;font-size:16px;">엔진 역직렬화, shape 확정, enqueue, 출력 비교 중 하나라도 실패하거나 비대상 GPU에서 검증기 PID가 관찰되면 새 워커를 트래픽에서 제외합니다. CUDA 오류가 발생한 프로세스는 예외를 삼키고 재사용하지 말고 종료한 뒤 마지막으로 검증된 이미지·엔진·GPU UUID 조합으로 되돌립니다. 새 엔진만 실패하면 이전 엔진으로, 새 런타임 이미지에서도 이전 엔진이 실패하면 이미지까지 함께 롤백해야 원인을 섞지 않을 수 있습니다.</p>

  <h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">결론</h2>
  <p style="margin:0 0 16px;font-size:16px;">TensorRT 배포의 최소 성공 단위는 엔진 파일 생성이나 역직렬화가 아니라, 지정 GPU에서 기준 입력을 복사하고 실제 enqueue를 끝낸 뒤 기준 출력과 비교하는 것입니다. 이 검증을 readiness 조건으로 두면 GPU 매핑 오류, profile 불일치, 잘못된 버퍼, 전처리 회귀를 첫 사용자 요청 전에 분리할 수 있습니다.</p>

  <h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">공식 출처</h2>
  <ul style="margin:0 0 20px;padding-left:24px;font-size:16px;">
    <li style="margin:7px 0;"><a href="https://docs.nvidia.com/deeplearning/tensorrt/latest/inference-library/python-api-docs.html" style="color:#2563eb;text-decoration:underline;">NVIDIA TensorRT Python API Documentation</a></li>
    <li style="margin:7px 0;"><a href="https://docs.nvidia.com/deeplearning/tensorrt/latest/getting-started/quick-start-runtime-tutorial.html" style="color:#2563eb;text-decoration:underline;">NVIDIA TensorRT Runtime API Tutorial</a></li>
    <li style="margin:7px 0;"><a href="https://docs.nvidia.com/deeplearning/tensorrt/latest/inference-library/dynamic-shapes-basics.html" style="color:#2563eb;text-decoration:underline;">NVIDIA TensorRT Dynamic Shapes: Core Concepts</a></li>
    <li style="margin:7px 0;"><a href="https://nvidia.github.io/cuda-python/cuda-bindings/latest/module/runtime.html" style="color:#2563eb;text-decoration:underline;">NVIDIA cuda.bindings Runtime API</a></li>
    <li style="margin:7px 0;"><a href="https://docs.nvidia.com/deploy/nvidia-smi/index.html" style="color:#2563eb;text-decoration:underline;">NVIDIA System Management Interface Documentation</a></li>
  </ul>
</div>
