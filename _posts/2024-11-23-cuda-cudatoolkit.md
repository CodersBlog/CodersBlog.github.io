---
title: "[Cuda] Cuda 경로가 설정 되지 않아도 pytorch나 tensorflow가 gpu에서 작동할까?"
excerpt: "Will PyTorch or TensorFlow work on the GPU even if the CUDA path is not set? by sehoon-lee"

categories:
    - cuda
tags:
    - [cuda]

toc: true
toc_sticky: true

date: 2024-11-23
last_modified_at: 2024-11-23

math: true
---

최근 onnx-runtime 및 tensorrt 관련 작업을 하면서 최신 cuda 버전에 맞는 버전을 설치하다 보니 직접 빌드를 해야할 일이 생겼고,
여기에서 의존성 관련하여 cuda 및 cudnn 경로 관련 이슈가 있었다.
하지만 지금까지 pytorch를 gpu에서 이상없이 사용을 하였기에 의문이 생겨 알아보게 되었다.

## 1. CUDA Driver

pytorch 나 tensorflow 의 gpu 버전에서 필요로 하게 되는 cuda란 CUDA Driver를 의미한다.
CUDA Driver는 nvidia의 NVIDA Driver를 설치하면 같이 설치가 되어 드라이버만 설치가 되면
pytorch나 tensorflow의 gpu 버전을 gpu 에서 사용하는 것에 무리가 없다.

<br>

## 2. pytorch 나 tensorflow 설치시 주의!
Nvidia Driver를 설치하고 nvidia-smi 명령어를 입력한 후 보이는 CUDA Version을 우선 확인한다.
여기에 보이는 CUDA Version은 해당 버전까지 NVIDIA Driver가 호환이 가능하다는 것을 의미한다.
그러므로 nvidia-smi 명령어에서 볼 수 있는 CUDA 버전보다 이하 버전에 호환되는 pytorch나 tensorflow를 설치해야한다.


![img_file](/assets/img/post/cuda_cudatoolkit/nvidia_smi.png)



## 3. CUDA Toolkit

위에서 언급한 cuda 관련 의존성 문제의 원인이 CUDA Toolkit이 였다.
기본 경로가 /usr/local/cuda 로 잡히는데 cudnn도 해당경로에 설치해주면 된다.
만약 다양한 버전의 CUDA Toolkit이 있다면 심볼릭 링크로 해당 버전을 기본 경로로 잡아주면 된다.
CUDA Toolkit은 cuda 관련 고급기능을 사용할 때 필요한 것이다.

## 4. 결론
일반 pytorch 와 tensorflow 사용자들은 현재 gpu에 맞는 NVIDA Driver를 설치해주면 gpu 기능을 사용할 수 있다.<br>
하지만 cuda 관련 고급기능을 사용할 경우 CUDA Toolkit을 필요로하고, nvcc -V 명령어도 CUDA Toolkit 경로를 잡아줘야 사용이 가능하다. <br>
즉, nvcc -V 에서 보이는 CUDA 버전은 CUDA Toolkit 버전이며, pytorch 나 tensorflow 에서 직접 코드로 찍는 것이 정확히 해당 라이브러리에서 사용하는 cuda 버전을 알 수 있다.

