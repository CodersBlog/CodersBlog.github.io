---
title: "[TensorRT] IOutputAllocator로 데이터 의존적 출력 버퍼를 안전하게 받는 법"
excerpt: "TensorRT 데이터 의존적 출력의 바이트 상한과 실제 shape를 IOutputAllocator로 검증하는 운영 가이드 by sehoon-lee"
description: "TensorRT 10과 cuda.bindings에서 데이터 의존적 출력의 메모리 상한, bounded IOutputAllocator, callback shape를 검증하는 방법입니다."
categories:
  - Infra
tags:
  - [TensorRT, CUDA, IOutputAllocator, Dynamic Shapes, GPU Inference]
toc: true
toc_sticky: true
date: 2026-09-15
last_modified_at: 2026-09-15
---

<div style="max-width:860px;margin:0 auto;padding:28px 24px;background:#ffffff;color:#172033;font-family:Arial,'Noto Sans KR',sans-serif;line-height:1.72;">
<p style="margin:0 0 16px;font-size:16px;">대상 환경은 Linux, NVIDIA GPU, TensorRT 10 계열의 name-based Python API, <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">cuda.bindings</code>를 사용하는 추론 워커입니다. 입력 shape는 정상적으로 지정했지만 출력에 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">-1</code>이 남거나, 출력 버퍼를 고정 크기로 잡은 뒤 enqueue 실패·잘못된 복사 크기·간헐적 OOM이 발생하는 증상을 다룹니다.</p>
<p style="margin:0 0 20px;font-size:16px;">이 글은 <a href="https://codersblog.github.io/posts/tensorrt-dynamic-shape-profiles/" style="color:#2563eb;text-decoration:underline;">TensorRT Dynamic Shape Profile 실전 글</a>의 후속입니다. 이전 글은 입력의 min·opt·max shape와 latency를 기준으로 profile을 설계했지만, 입력 크기가 같아도 실제 데이터에 따라 결과 개수가 달라지는 출력 버퍼는 다루지 않았습니다. 운영에서는 이 빈틈을 큰 버퍼 하나로 덮으면 profile 상한이 커질 때 워커 전체 VRAM을 흔들 수 있습니다. 이번에는 상한을 먼저 확인하고, 바이트 예산 안에서만 버퍼를 등록한 뒤 실제 shape를 callback으로 받는 다음 단계를 구성합니다.</p>

<h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">1. 입력 동적 shape와 데이터 의존적 출력을 구분한다</h2>
<p style="margin:0 0 14px;font-size:16px;">입력의 batch·높이·너비가 바뀌는 것은 optimization profile과 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">set_input_shape</code>로 해결합니다. 반면 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">INonZeroLayer</code>처럼 실제 값에 따라 출력 원소 수가 달라지면 enqueue 전에는 최종 shape를 알 수 없습니다. 이때는 다음 세 값을 따로 관리해야 합니다.</p>
<ul style="margin:0 0 18px;padding-left:24px;font-size:16px;">
<li style="margin:7px 0;">profile과 입력 shape로 계산한 출력 메모리 상한</li>
<li style="margin:7px 0;">allocator callback이 요청받은 실제 바이트 수</li>
<li style="margin:7px 0;"><code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">notify_shape</code>가 알려 준 실제 출력 shape</li>
</ul>
<p style="margin:0 0 16px;font-size:16px;">최종 shape에 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">-1</code>이 남아 있다는 이유만으로 엔진 오류로 판정하지 않습니다. 먼저 입력이 충분히 지정됐는지 확인하고, 데이터 의존적 출력이면 allocator 경로로 넘깁니다.</p>

<h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">2. 엔진 I/O와 profile을 애플리케이션 밖에서 확인한다</h2>
<p style="margin:0 0 12px;font-size:16px;">배포 이미지와 같은 TensorRT 설치에서 엔진의 I/O, layer, profile 정보를 먼저 덤프합니다. <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">images</code>와 shape는 실제 이름과 profile 범위 안 값으로 바꿉니다.</p>
<pre style="margin:12px 0 18px;padding:16px;overflow-x:auto;border-radius:8px;background:#0b1220;color:#e5eefc;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;color:#e5eefc;">trtexec --loadEngine=model.engine \
  --shapes=images:1x3x640x640 \
  --profilingVerbosity=detailed \
  --dumpLayerInfo --exportLayerInfo=engine_layers.json</code></pre>
<p style="margin:0 0 16px;font-size:16px;">기대 관찰값은 입력 이름과 dtype이 애플리케이션 계약과 같고, 문제 출력의 차원에 동적 표시가 있으며, 해당 출력을 만드는 layer를 추적할 수 있는 것입니다. <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">trtexec</code> 자체가 같은 shape에서 실패하면 Python 버퍼 코드보다 엔진·plugin·profile 호환성을 먼저 봅니다.</p>

<h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">3. 상한을 VRAM 예산으로 바꾼다</h2>
<p style="margin:0 0 14px;font-size:16px;">TensorRT의 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">get_max_output_size</code>는 현재 profile과 입력 shape를 기준으로 출력 바이트 상한을 제공합니다. 입력 shape를 지정하기 전에 호출하거나 출력 이름이 아니면 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">-1</code>을 반환할 수 있습니다. 따라서 device 선택, runtime·engine·context 생성, profile 선택, 입력 shape·주소 지정, shape inference, 출력 상한 조회 순서를 지킵니다.</p>
<p style="margin:0 0 16px;font-size:16px;">아래 검증기는 모든 출력 상한 합계가 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">--max-total-output-mib</code>를 넘으면 메모리를 할당하기 전에 실패시킵니다. 상한을 그대로 허용할 수 없는 서비스에서는 profile을 줄이거나 모델의 후보 개수 상한을 낮추는 것이 우선입니다.</p>

<h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">4. bounded IOutputAllocator 검증기</h2>
<p style="margin:0 0 12px;font-size:16px;">예시는 단일 DEVICE·LINEAR 입력과 하나 이상의 DEVICE·LINEAR 출력을 대상으로 합니다. shape inference I/O나 vectorized format은 별도 주소·stride 계약이 필요하므로 중단합니다. 최신 경로인 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">reallocate_output_async</code>와 이전 10.x 호환 callback을 모두 구현하되, callback 안에서 새 메모리를 무제한 할당하지 않습니다.</p>
<pre style="margin:12px 0 18px;padding:16px;overflow-x:auto;border-radius:8px;background:#0b1220;color:#e5eefc;font-size:13px;line-height:1.5;"><code style="font-family:Consolas,'Courier New',monospace;color:#e5eefc;">import argparse
import json
import os

import numpy as np
import tensorrt as trt
from cuda.bindings import runtime as cudart


def check_cuda(result):
    err, *values = result
    if err != cudart.cudaError_t.cudaSuccess:
        raise RuntimeError(f&quot;CUDA error: {err}&quot;)
    if not values:
        return None
    return values[0] if len(values) == 1 else tuple(values)


def tensor_nbytes(shape, dtype):
    return int(np.prod(shape, dtype=np.int64)) * np.dtype(dtype).itemsize


class BoundedOutputAllocator(trt.IOutputAllocator):
    def __init__(self, pointer, capacity_bytes):
        trt.IOutputAllocator.__init__(self)
        self.pointer = int(pointer)
        self.capacity_bytes = int(capacity_bytes)
        self.requested_bytes = 0
        self.output_shape = None

    def _accept(self, size):
        self.requested_bytes = int(size)
        if self.requested_bytes &gt; self.capacity_bytes:
            return None
        return self.pointer

    def reallocate_output(self, tensor_name, current_memory, size, alignment):
        return self._accept(size)

    def reallocate_output_async(
        self, tensor_name, current_memory, size, alignment, stream
    ):
        return self._accept(size)

    def notify_shape(self, tensor_name, dims):
        self.output_shape = tuple(int(dim) for dim in dims)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(&quot;--engine&quot;, required=True)
    parser.add_argument(&quot;--input&quot;, required=True)
    parser.add_argument(&quot;--device&quot;, type=int, default=0)
    parser.add_argument(&quot;--profile&quot;, type=int, default=0)
    parser.add_argument(&quot;--max-total-output-mib&quot;, type=int, default=512)
    args = parser.parse_args()

    check_cuda(cudart.cudaSetDevice(args.device))
    current_device = check_cuda(cudart.cudaGetDevice())
    if current_device != args.device:
        raise RuntimeError(
            f&quot;device mismatch: requested={args.device}, current={current_device}&quot;
        )

    logger = trt.Logger(trt.Logger.WARNING)
    runtime = trt.Runtime(logger)
    with open(args.engine, &quot;rb&quot;) as file:
        engine = runtime.deserialize_cuda_engine(file.read())
    if engine is None:
        raise RuntimeError(&quot;engine deserialize failed&quot;)
    context = engine.create_execution_context()
    if context is None:
        raise RuntimeError(&quot;execution context creation failed&quot;)

    names = [engine.get_tensor_name(i) for i in range(engine.num_io_tensors)]
    inputs = [
        name for name in names
        if engine.get_tensor_mode(name) == trt.TensorIOMode.INPUT
    ]
    outputs = [
        name for name in names
        if engine.get_tensor_mode(name) == trt.TensorIOMode.OUTPUT
    ]
    if len(inputs) != 1:
        raise RuntimeError(f&quot;expected one input, got {inputs}&quot;)
    input_name = inputs[0]

    for name in names:
        if engine.is_shape_inference_io(name):
            raise RuntimeError(f&quot;shape inference I/O is unsupported: {name}&quot;)
        if engine.get_tensor_location(name) != trt.TensorLocation.DEVICE:
            raise RuntimeError(f&quot;only DEVICE tensors are supported: {name}&quot;)
        if engine.get_tensor_format(name) != trt.TensorFormat.LINEAR:
            raise RuntimeError(f&quot;only LINEAR tensors are supported: {name}&quot;)

    host_input = np.ascontiguousarray(np.load(args.input))
    input_dtype = np.dtype(trt.nptype(engine.get_tensor_dtype(input_name)))
    if host_input.dtype != input_dtype:
        raise RuntimeError(
            f&quot;input dtype mismatch: file={host_input.dtype}, engine={input_dtype}&quot;
        )

    stream = None
    device_pointers = []
    allocators = {}
    try:
        stream = check_cuda(cudart.cudaStreamCreate())
        stream_handle = int(stream)
        if args.profile != 0:
            if not context.set_optimization_profile_async(
                args.profile, stream_handle
            ):
                raise RuntimeError(f&quot;cannot select profile {args.profile}&quot;)

        declared = tuple(engine.get_tensor_shape(input_name))
        if any(dim &lt; 0 for dim in declared):
            if not context.set_input_shape(input_name, host_input.shape):
                raise RuntimeError(f&quot;input shape rejected: {host_input.shape}&quot;)
        elif declared != host_input.shape:
            raise RuntimeError(
                f&quot;input shape mismatch: file={host_input.shape}, engine={declared}&quot;
            )

        input_pointer = check_cuda(cudart.cudaMalloc(host_input.nbytes))
        device_pointers.append(input_pointer)
        if not context.set_tensor_address(input_name, int(input_pointer)):
            raise RuntimeError(f&quot;cannot bind input {input_name}&quot;)
        unresolved = context.infer_shapes()
        if unresolved:
            raise RuntimeError(f&quot;insufficient shape inputs: {list(unresolved)}&quot;)

        capacities = {}
        for name in outputs:
            shape_before = tuple(context.get_tensor_shape(name))
            dtype = np.dtype(trt.nptype(engine.get_tensor_dtype(name)))
            if shape_before and all(dim &gt;= 0 for dim in shape_before):
                capacity = tensor_nbytes(shape_before, dtype)
            else:
                capacity = int(context.get_max_output_size(name))
            if capacity &lt;= 0:
                raise RuntimeError(f&quot;invalid output upper bound: {name}={capacity}&quot;)
            capacities[name] = capacity

        total_capacity = sum(capacities.values())
        budget = args.max_total_output_mib * 1024 * 1024
        if total_capacity &gt; budget:
            raise RuntimeError(
                f&quot;output upper bound exceeds budget: &quot;
                f&quot;required={total_capacity}, budget={budget}&quot;
            )

        for name, capacity in capacities.items():
            pointer = check_cuda(cudart.cudaMalloc(capacity))
            device_pointers.append(pointer)
            allocator = BoundedOutputAllocator(pointer, capacity)
            allocators[name] = allocator
            if not context.set_tensor_address(name, int(pointer)):
                raise RuntimeError(f&quot;cannot bind output {name}&quot;)
            if not context.set_output_allocator(name, allocator):
                raise RuntimeError(f&quot;cannot set output allocator: {name}&quot;)

        check_cuda(cudart.cudaMemcpyAsync(
            input_pointer,
            host_input.ctypes.data,
            host_input.nbytes,
            cudart.cudaMemcpyKind.cudaMemcpyHostToDevice,
            stream,
        ))
        if not context.execute_async_v3(stream_handle):
            raise RuntimeError(&quot;inference enqueue failed&quot;)
        check_cuda(cudart.cudaStreamSynchronize(stream))

        report_outputs = {}
        for name, allocator in allocators.items():
            if allocator.output_shape is None:
                raise RuntimeError(f&quot;notify_shape was not called: {name}&quot;)
            if any(dim &lt; 0 for dim in allocator.output_shape):
                raise RuntimeError(
                    f&quot;unresolved output after enqueue: {name}={allocator.output_shape}&quot;
                )
            dtype = np.dtype(trt.nptype(engine.get_tensor_dtype(name)))
            actual_bytes = tensor_nbytes(allocator.output_shape, dtype)
            if actual_bytes &gt; allocator.capacity_bytes:
                raise RuntimeError(
                    f&quot;actual output exceeds capacity: {name}, &quot;
                    f&quot;actual={actual_bytes}, capacity={allocator.capacity_bytes}&quot;
                )
            host_output = np.empty(allocator.output_shape, dtype=dtype)
            if actual_bytes:
                check_cuda(cudart.cudaMemcpyAsync(
                    host_output.ctypes.data,
                    allocator.pointer,
                    actual_bytes,
                    cudart.cudaMemcpyKind.cudaMemcpyDeviceToHost,
                    stream,
                ))
            check_cuda(cudart.cudaStreamSynchronize(stream))
            report_outputs[name] = {
                &quot;shape&quot;: list(allocator.output_shape),
                &quot;dtype&quot;: str(dtype),
                &quot;requested_bytes&quot;: allocator.requested_bytes,
                &quot;capacity_bytes&quot;: allocator.capacity_bytes,
                &quot;finite&quot;: bool(np.isfinite(host_output).all()),
            }

        print(json.dumps({
            &quot;status&quot;: &quot;PASS&quot;,
            &quot;pid&quot;: os.getpid(),
            &quot;logical_device&quot;: current_device,
            &quot;profile&quot;: args.profile,
            &quot;total_output_capacity_bytes&quot;: total_capacity,
            &quot;outputs&quot;: report_outputs,
        }, ensure_ascii=False, indent=2))
    finally:
        if stream is not None:
            cudart.cudaStreamSynchronize(stream)
        for pointer in reversed(device_pointers):
            cudart.cudaFree(pointer)
        if stream is not None:
            cudart.cudaStreamDestroy(stream)


if __name__ == &quot;__main__&quot;:
    main()</code></pre>

<h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">5. 실행하고 관찰할 값</h2>
<p style="margin:0 0 12px;font-size:16px;">GPU UUID 하나만 노출하면 프로세스 내부의 논리 device는 0입니다. 출력 전체의 사전 할당 상한을 512 MiB로 제한한 예시는 다음과 같습니다.</p>
<pre style="margin:12px 0 18px;padding:16px;overflow-x:auto;border-radius:8px;background:#0b1220;color:#e5eefc;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;color:#e5eefc;">CUDA_VISIBLE_DEVICES=GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
python verify_dynamic_outputs.py \
  --engine model.engine \
  --input sample_input.npy \
  --device 0 --profile 0 \
  --max-total-output-mib 512</code></pre>
<p style="margin:0 0 14px;font-size:16px;">기대 관찰값은 JSON의 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">status</code>가 PASS이고, 모든 출력의 shape가 0 이상의 정수이며, <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">requested_bytes</code>가 <code style="padding:2px 5px;border-radius:4px;background:#eef2f7;color:#b42318;font-family:Consolas,'Courier New',monospace;">capacity_bytes</code> 이하인 것입니다. 데이터 의존적 출력은 입력 내용에 따라 actual shape가 달라져도 상한과 서비스 예산 안에 머물러야 합니다.</p>
<p style="margin:0 0 12px;font-size:16px;">최소·일반·최악 입력 세트로 반복해 상한 대비 실제 사용률과 GPU 메모리를 함께 기록합니다.</p>
<pre style="margin:12px 0 18px;padding:16px;overflow-x:auto;border-radius:8px;background:#0b1220;color:#e5eefc;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;color:#e5eefc;">for sample in empty_case.npy normal_case.npy crowded_case.npy; do
  python verify_dynamic_outputs.py \
    --engine model.engine --input "$sample" \
    --device 0 --profile 0 --max-total-output-mib 512
done

nvidia-smi --query-compute-apps=pid,gpu_uuid,used_memory \
  --format=csv -l 1</code></pre>
<p style="margin:0 0 16px;font-size:16px;">기대 관찰값은 빈 결과도 0차원을 포함한 정상 shape로 처리되고, 혼잡 입력에서도 예산 초과나 비대상 GPU 사용이 없으며, 같은 profile의 capacity는 입력 값에 따라 흔들리지 않는 것입니다.</p>

<h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">6. 실패 위치별 진단 분기</h2>
<table style="width:100%;border-collapse:collapse;margin:14px 0 20px;font-size:15px;">
<thead style="background:#eaf2ff;"><tr style="border:1px solid #b9cff2;">
<th style="border:1px solid #b9cff2;padding:10px;text-align:left;color:#12355b;">실패 지점</th>
<th style="border:1px solid #b9cff2;padding:10px;text-align:left;color:#12355b;">우선 확인</th>
<th style="border:1px solid #b9cff2;padding:10px;text-align:left;color:#12355b;">판정</th>
</tr></thead>
<tbody style="background:#ffffff;">
<tr style="border:1px solid #d7e1ef;"><td style="border:1px solid #d7e1ef;padding:10px;">infer_shapes가 이름 반환</td><td style="border:1px solid #d7e1ef;padding:10px;">입력 shape와 shape tensor 주소</td><td style="border:1px solid #d7e1ef;padding:10px;">입력 계약 누락</td></tr>
<tr style="border:1px solid #d7e1ef;"><td style="border:1px solid #d7e1ef;padding:10px;">상한이 -1 또는 0</td><td style="border:1px solid #d7e1ef;padding:10px;">profile 선택 순서, 출력 이름</td><td style="border:1px solid #d7e1ef;padding:10px;">상한 조회 시점 또는 I/O 식별 오류</td></tr>
<tr style="border:1px solid #d7e1ef;"><td style="border:1px solid #d7e1ef;padding:10px;">상한 합계가 예산 초과</td><td style="border:1px solid #d7e1ef;padding:10px;">profile max, 후보 개수 상한</td><td style="border:1px solid #d7e1ef;padding:10px;">할당 전 배포 거부, profile 재설계</td></tr>
<tr style="border:1px solid #d7e1ef;"><td style="border:1px solid #d7e1ef;padding:10px;">enqueue가 false</td><td style="border:1px solid #d7e1ef;padding:10px;">TensorRT 로그, callback 요청 바이트, plugin</td><td style="border:1px solid #d7e1ef;padding:10px;">버퍼 부족 또는 실행 오류</td></tr>
<tr style="border:1px solid #d7e1ef;"><td style="border:1px solid #d7e1ef;padding:10px;">notify_shape 미호출</td><td style="border:1px solid #d7e1ef;padding:10px;">allocator 객체 수명, 출력 연결</td><td style="border:1px solid #d7e1ef;padding:10px;">callback 등록 오류</td></tr>
<tr style="border:1px solid #d7e1ef;"><td style="border:1px solid #d7e1ef;padding:10px;">첫 실행 뒤 latency 변동</td><td style="border:1px solid #d7e1ef;padding:10px;">CUDA memory pool과 동기화 구간</td><td style="border:1px solid #d7e1ef;padding:10px;">실행 중 재할당·pool release 가능성</td></tr>
</tbody></table>

<h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">7. 배포와 롤백 기준</h2>
<h3 style="margin:20px 0 8px;font-size:19px;color:#24486d;">배포 허용</h3>
<ul style="margin:0 0 18px;padding-left:24px;font-size:16px;">
<li style="margin:7px 0;">최소·일반·최악 입력이 각각 3회 연속 PASS한다.</li>
<li style="margin:7px 0;">출력 상한 합계가 워커별 VRAM 예산 안이고 동시 worker 수를 곱한 값도 노드 여유 메모리를 넘지 않는다.</li>
<li style="margin:7px 0;">모든 callback 요청이 capacity 이하고, 실제 shape·dtype·유한값 검사와 후처리 결과가 기준 구현과 일치한다.</li>
<li style="margin:7px 0;">PID와 GPU UUID가 배포 설정과 일치하며 반복 실행 latency가 기존 허용 범위 안이다.</li>
</ul>
<h3 style="margin:20px 0 8px;font-size:19px;color:#24486d;">즉시 롤백</h3>
<p style="margin:0 0 16px;font-size:16px;">출력 상한이 예산을 넘거나 callback이 capacity보다 큰 크기를 요구하면 해당 엔진·profile을 배포하지 않습니다. enqueue 실패, 잘못된 최종 shape, 비유한 출력, 다른 GPU에서의 PID 관찰 중 하나라도 발생하면 새 워커를 트래픽에서 제외하고 마지막으로 검증된 엔진과 profile로 되돌립니다. CUDA 오류가 난 프로세스는 예외를 삼켜 재사용하지 말고 종료해야 오류 상태가 다음 요청과 섞이지 않습니다.</p>

<h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">결론</h2>
<p style="margin:0 0 16px;font-size:16px;">데이터 의존적 출력의 핵심은 최종 shape를 미리 맞히는 것이 아니라, profile 기반 바이트 상한을 서비스 예산으로 제한하고 TensorRT가 알려 주는 실제 요청 크기와 shape를 실행 후 검증하는 것입니다. 상한 조회, bounded allocator, callback 관측, 최악 입력 테스트를 하나의 readiness gate로 묶으면 고정 버퍼의 overflow와 무제한 재할당의 OOM을 모두 배포 전에 차단할 수 있습니다.</p>

<h2 style="margin:30px 0 12px;font-size:23px;color:#12355b;border-bottom:2px solid #dbeafe;padding-bottom:7px;">공식 출처</h2>
<ul style="margin:0 0 8px;padding-left:24px;font-size:16px;">
<li style="margin:7px 0;"><a href="https://docs.nvidia.com/deeplearning/tensorrt/latest/inference-library/dynamic-shapes-basics.html" style="color:#2563eb;text-decoration:underline;">NVIDIA TensorRT Dynamic Shapes: Core Concepts</a></li>
<li style="margin:7px 0;"><a href="https://docs.nvidia.com/deeplearning/tensorrt/latest/_static/python-api/infer/Core/ExecutionContext.html" style="color:#2563eb;text-decoration:underline;">NVIDIA TensorRT Python API: IExecutionContext and IOutputAllocator</a></li>
<li style="margin:7px 0;"><a href="https://docs.nvidia.com/deeplearning/tensorrt/latest/performance/benchmarking.html" style="color:#2563eb;text-decoration:underline;">NVIDIA TensorRT Performance Benchmarking and trtexec</a></li>
<li style="margin:7px 0;"><a href="https://docs.nvidia.com/deeplearning/tensorrt/latest/inference-library/engine-tools.html" style="color:#2563eb;text-decoration:underline;">NVIDIA TensorRT Engine Tools and Debugging</a></li>
<li style="margin:7px 0;"><a href="https://nvidia.github.io/cuda-python/cuda-bindings/12.9.0/module/runtime.html" style="color:#2563eb;text-decoration:underline;">NVIDIA cuda.bindings Runtime API</a></li>
<li style="margin:7px 0;"><a href="https://docs.nvidia.com/deploy/nvidia-smi/index.html" style="color:#2563eb;text-decoration:underline;">NVIDIA System Management Interface Documentation</a></li>
</ul>
</div>
