---
title: "[Error] 파일 로드 시 발생하는 Decode 오류 해결 방법"
excerpt: "Solution for decode error by Junhyuns"

categories:
    - Python
tags:
    - [Python, decode error, UnicodeDecodeError, pandas, csv]

toc: true
toc_sticky: true

date: 2024-10-04
last_modified_at: 2024-10-04

math: true
---

Pandas를 활용해서 csv 파일을 불러올 때 발생할 수 있는 에러에 대한 해결 방안입니다.

다음과 같이 pd.read_csv() 함수를 통해 csv 파일을 불러올 때 가끔 아래와 같은 에러가 발생합니다.

```python
data = pd.read_csv(PATH)

UnicodeDecodeError: 'utf-8' codec can't decode byte 0x90 in position 80: invalid start byte
```

Pandas에서는 별도의 encoding argument를 주지 않는 경우 "utf-8"을 이용해서 디코딩을 진행하는데, 해당 파일이 "utf-8"로 인코딩된 파일이 아닌 경우 발생하는 오류입니다.

아래와 같이 pd.read_csv() 함수에 encoding argument를 넣어줌으로써 해결할 수 있습니다. 

```python
data = pd.read_csv(PATH, encoding="cp949")
```

또는

```python
data = pd.read_csv(PATH, encoding="utf-8-sig")
```