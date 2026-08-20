---
title: "[Python] resample이 구간을 어디서 끊는가 — closed와 label"
excerpt: "How resample decides bin edges, and why totals will not catch the mistake by Junhyuns"
description: "pandas resample의 closed와 label 인자가 집계 결과를 어떻게 바꾸는지 직접 실행한 결과로 정리합니다. 라벨이 같아 보이는데 값이 다른 경우, resample과 asfreq의 차이도 함께 다룹니다."

categories:
    - Dev
tags:
    - [Python, Pandas, Time Series, resample, asfreq]

toc: true
toc_sticky: true

date: 2026-08-20
last_modified_at: 2026-08-20

math: true
---

시간별 데이터를 3시간 단위로 묶는다고 해봅시다. 인자 하나 차이로 결과가 이렇게 갈립니다.

```python
s.resample("3h").sum()                            # [3, 12, 6]
s.resample("3h", closed="right", label="right").sum()   # [0, 6, 15]
```

값이 완전히 다른데 **첫 라벨은 둘 다 `00:00`** 이고, **총합도 둘 다 21**입니다. 인덱스를 훑어봐도, 합계로 검산해도 안 걸립니다.

## 확인 환경

아래는 전부 직접 실행한 결과입니다.

```
Python 3.13.7 · pandas 3.0.2
```

입력은 0시부터 6시까지 시간별 7개 점이고, 값은 0부터 6까지입니다.

```python
idx = pd.date_range("2026-01-01 00:00", periods=7, freq="h")
s = pd.Series(range(7), index=idx)
# 00h=0, 01h=1, 02h=2, 03h=3, 04h=4, 05h=5, 06h=6
```

## 같은 라벨, 다른 값

네 조합을 돌려본 결과입니다.

| 인자 | 값 | 라벨 |
|---|---|---|
| (기본) | `[3, 12, 6]` | 00:00, 03:00, 06:00 |
| `closed="right"` | `[0, 6, 15]` | **전날 21:00**, 00:00, 03:00 |
| `label="right"` | `[3, 12, 6]` | 03:00, 06:00, 09:00 |
| `closed="right", label="right"` | `[0, 6, 15]` | 00:00, 03:00, 06:00 |

첫 줄과 마지막 줄을 비교해 보세요. **라벨이 완전히 같습니다.** 값만 다릅니다.

총합도 도움이 안 됩니다.

```
default      : [3, 12, 6]  total = 21
closed=right : [0, 6, 15]  total = 21
raw total    : 21
```

원본 합계가 21이니 어느 쪽이든 21이 나옵니다. **집계 결과의 총합으로 검산하는 습관은 이 오류를 못 잡습니다.**

## 구간은 반열림입니다

왜 이렇게 되는지는 각 점이 어느 칸에 들어가는지 보면 바로 보입니다.

![img_file](/assets/img/post/pandas-resample/bins.svg){: .align-center}*pandas 3.0.2에서 실제로 실행한 결과입니다*

`closed`는 **구간의 어느 쪽 끝을 포함할지**를 정합니다.

```
closed='left'  (기본)
  bin 00:00 <- [00h, 01h, 02h]  sum=3
  bin 03:00 <- [03h, 04h, 05h]  sum=12
  bin 06:00 <- [06h]            sum=6

closed='right'
  bin 전날 21:00 <- [00h]            sum=0
  bin 00:00     <- [01h, 02h, 03h]  sum=6
  bin 03:00     <- [04h, 05h, 06h]  sum=15
```

`closed='right'` 로 두면 `00:00` 이 `(21:00, 00:00]` 구간에 혼자 들어갑니다. 그래서 **전날 21시짜리 칸이 생기고**, 이후 모든 점이 한 칸씩 밀립니다.

`03:00` 이 어디로 가는지가 갈림길입니다. 기본값에서는 두 번째 칸의 **시작점**이고, `closed='right'` 에서는 두 번째 칸의 **끝점**입니다.

> 경계에 정확히 걸리는 값이 하나라도 있으면 `closed` 가 결과를 바꿉니다. 정각 데이터는 거의 항상 경계에 걸립니다.
{: .prompt-warning }

## label은 값을 바꾸지 않습니다

`closed` 와 `label` 을 한 덩어리로 기억하면 헷갈립니다. 둘은 하는 일이 다릅니다.

```python
a = s.resample("3h", label="left").sum()   # [3, 12, 6]
b = s.resample("3h", label="right").sum()  # [3, 12, 6]
a.tolist() == b.tolist()                   # True
```

값이 똑같습니다. 달라지는 건 이름표뿐입니다.

```
label='left'  labels: 00:00, 03:00, 06:00
label='right' labels: 03:00, 06:00, 09:00
```

정리하면 이렇습니다.

| 인자 | 하는 일 |
|---|---|
| `closed` | **어느 점이 어느 칸에 들어가는지** — 값이 바뀐다 |
| `label` | **칸에 붙일 이름** — 값은 그대로 |

앞의 표에서 `closed='right', label='right'` 가 기본값과 같은 라벨을 갖게 된 것도 이 때문입니다. `closed` 가 칸을 한 칸 왼쪽으로 밀었고, `label` 이 이름표를 다시 오른쪽으로 옮겨서 **원래 자리로 돌아온 것처럼 보이게** 만든 것입니다.

## 그러면 언제 closed='right'를 쓰나

여기부터는 제 판단입니다.

데이터가 **"지난 한 시간의 집계"** 라면 `07:00` 이라는 타임스탬프는 06시부터 07시까지를 뜻합니다. 전력 사용량, 트래픽 카운터, 배치 집계 결과가 대개 이렇습니다.

이런 데이터를 기본값으로 묶으면 각 칸이 의도보다 한 시간씩 앞으로 당겨집니다. 이때 `closed='right', label='right'` 가 원래 의미에 맞습니다.

반대로 **그 시각의 관측값**이라면 — 센서 값, 주가, 온도 — 기본값이 자연스럽습니다.

**결국 인자를 고르는 기준은 데이터의 의미**이지 관례가 아닙니다. 원본 타임스탬프가 구간의 시작을 가리키는지 끝을 가리키는지부터 확인하시면 됩니다.

## resample과 asfreq는 다른 일을 합니다

이름이 비슷해서 자주 헷갈리는 짝입니다.

```python
s.resample("2h").sum()   # [1, 5, 9, 6]
s.asfreq("2h")           # [0, 2, 4, 6]
```

`resample` 은 **구간으로 묶어서 집계**하고, `asfreq` 는 **그 시각의 값만 뽑습니다.** 위 결과에서 `asfreq` 쪽이 0, 2, 4, 6 인 것은 2시간 간격 시각의 원래 값을 그대로 가져왔기 때문입니다.

업샘플링에서는 성격이 더 분명해집니다.

```python
s.asfreq("30min").head(4)              # [0.0, nan, 1.0, nan]
s.resample("30min").mean().head(4)     # [0.0, nan, 1.0, nan]
s.resample("30min").ffill().head(4)    # [0, 0, 1, 1]
```

없던 시각을 만들어내면 그 자리는 `NaN` 입니다. **채우는 것은 별도 단계**이고, `ffill` 같은 메서드를 명시적으로 붙여야 합니다.

## origin — 데이터가 정각에 안 떨어질 때

`origin` 은 구간의 기준점을 정합니다. 30분 단위로 어긋난 데이터로 확인해봤습니다.

```
입력: 00:30=0, 01:30=1, 02:30=2, 03:30=3, 04:30=4, 05:30=5

origin='start_day'  첫 칸 00:00  values=[1, 5, 9]
origin='start'      첫 칸 00:30  values=[1, 5, 9]
origin='epoch'      첫 칸 00:00  values=[1, 5, 9]
```

이 예시에서는 **값이 안 바뀌고 첫 라벨만 달라졌습니다.** `origin='start'` 가 첫 데이터 시각에 기준을 맞추기 때문입니다.

값까지 달라지는 조건을 만들 수는 있겠지만, 이번에 확인한 범위에서는 재현하지 못했습니다. `closed` 만큼 자주 문제를 일으키는 인자는 아니라고 봅니다.

## 정리

`resample` 에서 값을 바꾸는 건 `closed` 이고, `label` 은 이름표만 옮깁니다. 둘을 분리해서 기억하는 것이 첫 단추입니다.

그리고 **이 실수는 조용합니다.** 예외도 경고도 없고, 총합 검산도 통과합니다. [pandas 3.0 편](/posts/pandas-3-migration/)에서 본 것들과 같은 종류의 사고입니다.

집계 코드를 새로 짜거나 남의 코드를 받았을 때 확인할 것은 셋입니다.

- 원본 타임스탬프가 **구간의 시작인가 끝인가**
- `closed` 를 명시했는가, 아니면 기본값에 맡겼는가
- 경계에 정확히 걸리는 값이 있는가 — 정각 데이터라면 거의 항상 있습니다

한 칸이 밀린 집계는 그래프로 그려도 잘 안 보입니다. 시작할 때 확인하는 편이 낫습니다.

## 참고

- [pandas.Series.resample](https://pandas.pydata.org/docs/reference/api/pandas.Series.resample.html) — `closed`, `label`, `origin` 인자 설명 (2026-08-20 확인)
- [pandas.Series.asfreq](https://pandas.pydata.org/docs/reference/api/pandas.Series.asfreq.html) — 집계가 아닌 추출 (2026-08-20 확인)
- [Time series / date functionality](https://pandas.pydata.org/docs/user_guide/timeseries.html) — 리샘플링 전반을 다룬 공식 사용자 가이드
- [pandas 3.0 — 오류 없이 결과만 달라지는 것들](/posts/pandas-3-migration/) — 같은 결의 조용한 변경들
- [Pandas 라이브러리 datetime 함수를 이용한 시계열 데이터 전처리](/posts/timeseris_preprocess/) — 이 글의 앞 단계
