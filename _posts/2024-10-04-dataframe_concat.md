---
title: "[Library] 여러 개의 csv 파일을 불러와서 하나의 데이터프레임으로 만들기"
excerpt: "How to create one dataframe from multiple csv files by Junhyuns"

categories:
    - Python
tags:
    - [Python, Pandas, Dataframe, concat, list]

toc: true
toc_sticky: true

date: 2024-10-04
last_modified_at: 2024-10-04

math: true
---

여러 개의 csv 파일들을 불러와서 하나의 데이터프레임 형태로 만들고 싶은 경우가 있습니다.

이때, 가장 간단한 방법은 아래와 같이 for 반복문을 통해 데이터를 불러오고 Pandas의 concat 함수나 append 함수를 활용해서 병합하는 형태입니다.

concat 함수를 이용하는 코드는 아래와 같습니다.

```python
df_wanted = pd.DataFrame() # 빈 데이터프레임 생성

for PATH_FILE in list_file:
    df_tmp = pd.read_csv(PATH_FILE) # 하나의 csv 파일 로드

    df_wanted = pd.concat([df_wanted, df_tmp], axis = 0) # concat 함수 이용해서 데이터프레임 병합
```

append 함수를 이용하는 코드는 아래와 같습니다.

```python
df_wanted = pd.DataFrame() # 빈 데이터프레임 생성

for PATH_FILE in list_file:
    df_tmp = pd.read_csv(PATH_FILE) # 하나의 csv 파일 로드

    df_wanted = df_wanted.append(df_tmp) # append 함수 이용해서 데이터프레임 병합
```