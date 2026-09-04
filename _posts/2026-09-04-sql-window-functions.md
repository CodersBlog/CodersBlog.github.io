---
title: "[SQL] 윈도우 함수로 시계열 집계하기 — 그리고 pandas와 답이 갈리는 지점"
excerpt: "Window functions for time series, and where SQL and pandas silently disagree by Junhyuns"
description: "LAG, 이동평균, 누적합을 SQL 윈도우 함수로 한 번에 계산하는 법을 정리합니다. 같은 계산을 pandas로 했을 때 답이 달라지는 원인과, SQLite·DuckDB·pandas 실행 시간 실측을 함께 담았습니다."

categories:
    - Dev
tags:
    - [SQL, window function, Time Series, DuckDB, Pandas]

toc: true
toc_sticky: true

date: 2026-09-04
last_modified_at: 2026-09-04

math: true
---

설비 데이터를 다루면 늘 같은 것을 계산합니다. **직전 값 대비 증감**, **이동평균**, **누적합**. 파이썬으로 내려받아서 하기 전에, SQL에서 한 번에 끝낼 수 있습니다.

그런데 같은 계산을 SQL과 pandas로 각각 짜서 맞춰보면 **답이 다르게 나오는 경우가 있습니다.** 오류도 경고도 없이요.

## 확인 환경

아래 결과는 전부 직접 실행한 것입니다.

```
Python 3.13.7 · pandas 3.0.2 · SQLite 3.50.4 (파이썬 내장) · DuckDB 1.5.5
```

데이터는 [NAB](https://github.com/numenta/NAB)의 실제 산업 설비 온도 센서 기록입니다. **22,695행**, 2013-12-02부터 2014-02-19까지 5분 간격입니다.

## 문법 — 세 계산을 한 쿼리로

```sql
SELECT ts, v,
       v - LAG(v) OVER w                                       AS diff,
       AVG(v) OVER (PARTITION BY device ORDER BY ts
                    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)  AS ma7,
       SUM(v) OVER w                                           AS cum
FROM readings
WINDOW w AS (PARTITION BY device ORDER BY ts)
```

실행 결과입니다.

```
                 ts     v  diff   ma7   cum
2013-12-02 21:15:00 73.97   NaN 73.97  74.0
2013-12-02 21:20:00 74.94  0.97 74.45 148.9
2013-12-02 21:25:00 76.12  1.19 75.01 225.0
2013-12-02 21:30:00 78.14  2.02 75.79 303.2
2013-12-02 21:35:00 79.33  1.19 76.50 382.5
2013-12-02 21:40:00 78.71 -0.62 76.87 461.2
2013-12-02 21:45:00 80.27  1.56 77.35 541.5
2013-12-02 21:50:00 80.27  0.00 78.25 621.8
```

읽는 법은 세 가지만 알면 됩니다.

| 조각 | 뜻 |
|---|---|
| `PARTITION BY device` | 설비별로 나눠서 계산 — `GROUP BY`와 달리 **행이 줄지 않습니다** |
| `ORDER BY ts` | 그 안에서 어떤 순서로 볼지 |
| `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` | 현재 행 포함 뒤로 7행 — 이동평균의 창 |

`WINDOW w AS (...)` 로 창을 이름 붙여두면 같은 정의를 반복하지 않아도 됩니다. 이동평균만 창이 다르므로 그것만 따로 씁니다.

> `PARTITION BY` 없이 쓰면 설비 경계를 넘어 계산됩니다. 다른 설비의 마지막 값과 다음 설비의 첫 값 사이에 `diff`가 생기는데, 값이 그럴듯해서 눈에 잘 안 띕니다.
{: .prompt-warning }

## pandas로 같은 것

```python
g = df.groupby("device", sort=False)["v"]
df.assign(
    diff=g.diff(),
    ma7=g.transform(lambda s: s.rolling(7, min_periods=1).mean()),
    cum=g.cumsum(),
)
```

한눈에 대응됩니다.

| SQL | pandas |
|---|---|
| `LAG(v) OVER w` | `g.diff()` |
| `AVG(v) OVER (... ROWS BETWEEN 6 PRECEDING ...)` | `g.rolling(7).mean()` |
| `SUM(v) OVER w` | `g.cumsum()` |

## 그런데 답이 갈렸습니다

세 방식이 같은 값을 내는지 22,695행 전체로 맞춰봤습니다.

| 조건 | pandas 대비 최대 오차 |
|---|---|
| ① 데이터를 그대로 두고 `ORDER BY ts` | **1,125** |
| ② 시간순 정렬 후 `ORDER BY ts` | **94.6** |
| ③ 시간순 정렬 + `ORDER BY ts, rid` | **2.3e-10** |

③에서야 일치합니다. 앞의 둘은 **오류 없이 그냥 다른 값**입니다.

원인이 두 겹입니다.

**하나, 원본이 시간순이 아니었습니다.** SQL은 `ORDER BY ts`로 순서를 직접 정하지만, **pandas는 DataFrame에 지금 담긴 행 순서를 그대로 씁니다.** `cumsum()`은 위에서부터 더할 뿐 타임스탬프를 보지 않습니다. 두 순서가 다르면 답이 달라집니다.

**둘, 타임스탬프가 겹쳤습니다.** 이 데이터에는 같은 시각이 **12건** 있습니다.

```
2014-01-07 02:00:00  94.423406
2014-01-07 02:00:00  94.139723
2014-01-07 02:05:00  94.698730
2014-01-07 02:05:00  94.111970
```

`ORDER BY ts` 만으로는 이 둘 중 무엇이 먼저인지 정해지지 않습니다. **정렬이 결정적이지 않으니 누적합도 이동평균도 실행마다 달라질 수 있습니다.**

22,695행 중 12행, **0.05%** 입니다. 그런데 누적합은 한 번 어긋나면 그 뒤가 전부 밀립니다.

> **`ORDER BY` 에는 순서를 유일하게 정하는 키를 넣으십시오.** `ORDER BY ts, id` 처럼요. pandas 쪽은 계산 전에 `sort_values()` 를 먼저 합니다.
{: .prompt-tip }

[resample 편](/posts/pandas-resample/), [pandas 3.0 편](/posts/pandas-3-migration/)에서 본 것과 같은 종류입니다. 예외가 안 나고 결과만 달라지는 쪽이 늘 더 위험합니다.

## 그럼 어디서 계산하나

순서를 맞췄다면 다음 질문은 속도입니다. 같은 쿼리를 SQLite와 DuckDB에서, 같은 계산을 pandas에서 돌려 재봤습니다.

![img_file](/assets/img/post/sql-window-functions/scaling.svg){: .align-center}*설비 50대로 나눈 합성 데이터. 세 방식 모두 같은 값을 냅니다*

| 행 수 | SQLite 질의 | DuckDB 질의 | pandas 계산 |
|---|---|---|---|
| 1만 | 0.03초 | 0.01초 | 0.007초 |
| 10만 | 0.39초 | 0.04초 | 0.010초 |
| 100만 | 3.76초 | 0.19초 | 0.049초 |
| 500만 | **20.23초** | **0.93초** | **0.215초** |

500만 행에서 SQLite와 DuckDB가 **22배** 벌어집니다. 쿼리는 한 글자도 안 바꿨습니다.

느린 쪽이 질의인지 결과를 파이썬으로 옮기는 과정인지 갈라봤습니다. 100만 행 기준입니다.

| 단계 | SQLite | DuckDB |
|---|---|---|
| 질의만 (결과 반환 억제) | 2.02초 | 0.11초 |
| + `fetchall()` | 2.93초 | — |
| + DataFrame 변환 | 3.38초 | 0.17초 |

**질의 자체가 병목입니다.** DataFrame 변환이 아닙니다.

적재 비용도 무시할 수 없습니다. 500만 행을 넣는 데 SQLite는 6.39초, DuckDB는 0.09초였습니다.

## 언제 무엇을 쓰나

실측을 근거로 정리하면 이렇습니다.

**데이터가 이미 DB에 있고 규모가 수십만 행 이하라면** SQL 윈도우 함수가 낫습니다. 내려받고 다시 올리는 왕복이 없고, 쿼리 한 줄이 pandas 세 줄보다 읽기 쉽습니다.

**규모가 백만 행을 넘어가면** SQLite가 먼저 무너집니다. 쿼리를 그대로 두고 DuckDB로 옮기는 것이 가장 싼 개선입니다. 표준 SQL이라 수정할 게 없었습니다.

**데이터가 이미 DataFrame으로 메모리에 있다면** pandas가 제일 빠릅니다. 굳이 DB에 넣었다 뺄 이유가 없습니다.

> SQLite가 느린 것을 결함으로 볼 일은 아닙니다. 임베디드 트랜잭션 엔진이지 분석용 엔진이 아닙니다. 500만 행 윈도우 집계는 원래 이 도구의 용도가 아닙니다.
{: .prompt-info }

## 한계

**합성 데이터로 쟀습니다.** 실제 데이터는 분포와 카디널리티가 다르므로 절대 수치는 달라집니다. 크기에 따른 경향으로만 보시면 됩니다.

**단일 장비 CPU 기준입니다.** 서버 사양, 메모리, 동시 부하에 따라 달라집니다.

**pandas 쪽은 데이터가 이미 메모리에 있다고 가정했습니다.** 파일을 읽는 시간은 뺐습니다. 실무에서는 그 비용이 붙습니다.

## 정리

윈도우 함수는 `PARTITION BY` · `ORDER BY` · 창 범위 세 조각으로 읽힙니다. 이것만 알면 전기 대비 증감·이동평균·누적합을 SQL 한 번에 끝낼 수 있습니다.

다만 **순서를 명시하는 방식이 pandas와 다르다**는 것을 기억하셔야 합니다. SQL은 `ORDER BY`로 정하고 pandas는 현재 행 순서를 씁니다. 원본이 정렬돼 있지 않거나 타임스탬프가 겹치면 조용히 다른 값이 나옵니다.

그리고 규모가 커지면 **같은 SQL이라도 엔진에 따라 20배 차이**가 납니다. 쿼리를 최적화하기 전에 어디서 돌리고 있는지부터 보는 편이 빠릅니다.

## 참고

- [SQLite Window Functions](https://sqlite.org/windowfunctions.html) — 공식 문서 (2026-09-04 확인)
- [DuckDB Window Functions](https://duckdb.org/docs/stable/sql/functions/window_functions) — 공식 문서 (2026-09-04 확인)
- [numenta/NAB](https://github.com/numenta/NAB) — 실측에 쓴 설비 센서 데이터 (`realKnownCause/machine_temperature_system_failure.csv`)
- [DDL, DML, DCL, TCL 알아보기](/posts/SQL/) — SQL 기본 문법 편
- [resample이 구간을 어디서 끊는가](/posts/pandas-resample/) — 같은 결의 조용한 오차
- [pandas 3.0 — 오류 없이 결과만 달라지는 것들](/posts/pandas-3-migration/)
- [Pandas datetime 함수를 이용한 시계열 데이터 전처리](/posts/timeseris_preprocess/)
