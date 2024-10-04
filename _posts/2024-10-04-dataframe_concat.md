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

이때, 간단하게 아래와 같이 for 반복문과 Pandas의 concat, append 함수를 이용해서 원하는 바를 이룰 수 있습니다.

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

하지만 위와 같은 방식은 생성하는 데이터프레임의 행이 많을수록, csv 파일이 많을수록 시간이 오래 걸리게 됩니다.

아래와 같이 데이터프레임을 list에 담아두고 마지막에 병합하는 방법을 통해 해당 작업의 속도를 향상시킬 수 있습니다.

```python
list_tmp = [] # 빈 리스트 생성

for PATH_FILE in list_file:
    df_tmp = pd.read_csv(PATH_FILE) # 하나의 csv 파일 로드

    list_tmp.append(df_tmp) # 매 반복마다 list에 데이터프레임을 적재

df_wanted = pd.concat(list_tmp)
```