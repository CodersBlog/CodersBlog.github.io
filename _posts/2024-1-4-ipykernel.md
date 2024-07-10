---
title: "[Library] ipykernel 라이브러리"
excerpt: "Description of ipykernel by Junhyuns"

categories:
    - Python
tags:
    - [Python, ipykernel, jupyter]

toc: true
toc_sticky: true

date: 2024-01-04
last_modified_at: 2023-01-04

math: true
---

이번 게시물에서는 가상환경을 jupyter notebook에서 사용할 수 있도록 해주는 ipykernel의 사용법에 대해서 설명하도록 하겠습니다.


## 가상환경 생성하기

```
conda create -n "가상환경 이름"
conda create -n "가상환경 이름" python="버전"
```

아나콘다 프롬프트에서 해당 명령어를 통해 가상 환경을 생성합니다.

"가상환경 이름" 부분에는 새로 생성되는 가상환경의 이름을 넣어주고 "버전"에는 원하는 파이썬 버전을 입력해줍니다.

원하는 파이썬 버전이 없는 경우에는 python 버전을 정의하지 않는 위의 명령어를 사용해주셔도 됩니다.

<br>

## ipykernel 라이브러리 설치하기
```
pip install ipykernel
```

해당 명령어를 통해 ipykernel 라이브러리를 설치합니다.

<br>

## ipykernel을 활용하여 커널 생성하기
```
python -m ipykernel install --user --name "가상환경 이름"
python -m ipykernel install --user --name "가상환경 이름" --display-name "커널 이름"
```

설치한 ipykernel을 이용하여 가상환경과 jupyter notebook을 연결해주는 커널을 생성해줍니다.

위의 명령어를 사용하면 가상환경과 똑같은 이름의 커널을 생성할 수 있으며 --display-name 옵션을 통해 원하는 이름으로 변경도 가능합니다.

커널을 생성하였다면 jupyter notebook 오른쪽 상단에서 커널을 선택함으로써 원하는 가상환경을 사용할 수 있습니다.

<br>

## 가상환경 커널 확인하기
```
jupyter kernelspec list
```

해당 명령어를 통해 현재 생성된 커널들의 리스트를 확인할 수 있습니다.

<br>

## 가상환경 커널 삭제하기
```
jupyter kernelspec uninstall "커널 이름"
```

해당 명령어를 통해 생성된 커널을 삭제할 수 있습니다.

jupyter notebook과 가상환경을 연결해주는 커널을 삭제한 것일 뿐 가상환경은 변경되지 않습니다.