---
title: "[Library] Pandas 라이브러리 datetime 함수를 이용한 시계열 데이터 전처리"
excerpt: "Description of file and folder copy function using shutil by Junhyuns"

categories:
    - Python
tags:
    - [Python, pandas, data]

toc: true
toc_sticky: true

date: 2024-07-20
last_modified_at: 2024-07-20

math: true
---

이번 게시물에는 시계열 데이터를 이용한 Regression/Classifiaction 모델을 구축할때 많이 사용되는 데이터 전처리 중 하나를 알아보겠습니다.

## pandas 라이브러리의 datetime 함수로 해당 열의 데이터를 datetime 형태로 변경

```python
import pandas as pd

df = pd.read_csv('csv 파일 이름')

df['타입을 변경할 열 이름'] = pd.to_datetime(df['타입을 변경할 열 이름'])

# 변경 후 확인
df.info()
```
<br>

## datetime의 값을 각각 요소로 변경

```python
df['자른 월'] = df['시간'].dt.month() # 12달 기준의 월
df['자른 날짜'] = df['시간'].dt.day() # 31일 기준의 날짜
df['자른 시간'] = df['시간'].dt.hour() # 24시간 기준의 시간
df['자른 분'] = df['시간'].dt.minute() # 60분 기준의 분

df['자른 일년 기준 날짜'] = df['시간'].dt.dayofyear # 366 기준의 날짜

```

<br>

## 각 요소별로 sine / cosine 함수 적용하여 전처리

```python
import numpy as np

MONTH_LENGTH = 12
DAY_LENGTH = 31
HOUR_LENGTH = 24
MINUTE_LENGTH = 60
YEAR_LENGTH = 366

df['sin_month'] = np.sin(2 * np.pi * df['자른 월'] / MONTH_LENGTH)
df['cos_month'] = np.cos(2 * np.pi * df['자른 월'] / MONTH_LENGTH)

df['sin_day'] = np.sin(2 * np.pi * df['자른 날짜'] / DAY_LENGTH)
df['cos_day'] = np.cos(2 * np.pi * df['자른 날짜'] / DAY_LENGTH)

df['sin_hour'] = np.sin(2 * np.pi * df['자른 시간'] / HOUR_LENGTH)
df['cos_hour'] = np.cos(2 * np.pi * df['자른 시간'] / HOUR_LENGTH)

df['sin_minute'] = np.sin(2 * np.pi * df['자른 분'] / MINUTE_LENGTH)
df['cos_minute'] = np.cos(2 * np.pi * df['자른 분'] / MINUTE_LENGTH)

df['sin_dayofyear'] = np.sin(2 * np.pi * df['자른 일년 기준 날짜'] / YEAR_LENGTH)
df['cos_dayofyear'] = np.cos(2 * np.pi * df['자른 일년 기준 날짜'] / YEAR_LENGTH)
```

**날짜 / 일년기준날짜의 경우 전처리 했을 시 1을 넘지 않기 위해서 가장 컸을 때의 값을사용함**

<br>

## 결과

![img_file](/assets/img/post/timeseris_preprocess/result_1.png){: .align-center}*datetime 형태의 시간 데이터*

<br>

![img_file](/assets/img/post/timeseris_preprocess/result_2.png){: .align-center}*요소별 분할*


<br>

![img_file](/assets/img/post/timeseris_preprocess/result_3.png){: .align-center}*sine / cosine 함수 적용 결과*