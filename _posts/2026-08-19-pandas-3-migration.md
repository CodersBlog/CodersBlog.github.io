---
title: "[Python] pandas 3.0 — 오류 없이 결과만 달라지는 것들"
excerpt: "What silently changes when you upgrade to pandas 3.0 by Junhyuns"
description: "pandas 3.0으로 올리면 예외 없이 결과만 바뀌는 지점들이 있습니다. 연쇄 할당, Copy-on-Write, str dtype, datetime 해상도 변화를 직접 실행한 결과로 정리하고 고치는 법을 붙입니다."

categories:
    - Dev
tags:
    - [Python, Pandas, Copy-on-Write, dtype, migration]

toc: true
toc_sticky: true

date: 2026-08-19
last_modified_at: 2026-08-19

math: true
---

pandas 3.0이 2026년 1월 21일에 나왔습니다. 올리고 나면 **터지는 코드는 금방 찾습니다.** 예외가 나니까요.

문제는 안 터지는 쪽입니다. 예외도 없고 결과만 달라지는 지점이 몇 군데 있고, 그게 조용히 잘못된 숫자로 이어집니다.

## 확인 환경

아래 결과는 전부 이 환경에서 **직접 실행한 것**입니다.

```
Python 3.13.7 · pandas 3.0.2 · numpy 2.4.4
```

가장 흔한 진입점부터 보겠습니다.

```python
df = pd.read_csv("t.csv", parse_dates=["ts"])
print(df.dtypes)
```

```
id               int64
name               str          ← object 아님
ts      datetime64[us]          ← ns 아님
```

`read_csv` 한 줄에서 이미 둘이 바뀌었습니다. 하나씩 보겠습니다.

## 1. 연쇄 할당 — 이름은 Error인데 Warning입니다

가장 널리 쓰이던 관용구가 이제 동작하지 않습니다.

```python
df = pd.DataFrame({"score": [10, 20, 30]})

df["score"][0] = 999          # 옛날 방식
print(df["score"].tolist())   # [10, 20, 30]  ← 안 바뀜

df.loc[0, "score"] = 999      # 올바른 방식
print(df["score"].tolist())   # [999, 20, 30]
```

pandas가 알려주기는 합니다.

```
ChainedAssignmentError: A value is being set on a copy of a DataFrame or Series
through chained assignment. ... Try using '.loc[row_indexer, col_indexer] = value'
```

그런데 이게 함정입니다. **이름은 `Error`인데 실제로는 `Warning` 서브클래스입니다.**

```python
>>> issubclass(pd.errors.ChainedAssignmentError, Warning)
True
```

예외가 아니라 경고라서 **스크립트는 그냥 계속 돕니다.** 로그를 안 보고 있으면 할당이 안 된 채로 다음 단계로 넘어갑니다.

참고로 2.x 시절의 `SettingWithCopyWarning`은 아예 사라졌습니다.

```python
>>> hasattr(pd.errors, "SettingWithCopyWarning")
False
```

전에는 "될 때도 있고 안 될 때도 있어서" 경고했는데, 이제는 **일관되게 안 되기 때문에** 경고 대신 안내로 바뀐 셈입니다.

> `df[col][row] = v` 패턴을 코드베이스에서 찾아 `df.loc[row, col] = v` 로 바꾸는 것이 이번 마이그레이션에서 가장 먼저 할 일입니다.
{: .prompt-warning }

## 2. 떼어둔 열은 원본을 따라가지 않습니다

이쪽이 진짜 조용합니다. **경고조차 없습니다.**

```python
df = pd.DataFrame({"a": [1, 2, 3]})
v = df["a"]              # 열을 하나 잡아둔다
df.loc[0, "a"] = 99      # 원본을 고친다

print(df["a"].tolist())  # [99, 2, 3]
print(v.tolist())        # [1, 2, 3]   ← 2.x 였다면 [99, 2, 3]
```

![img_file](/assets/img/post/pandas-3-migration/cow.svg){: .align-center}*pandas 3.0.2에서 실제로 실행한 결과입니다*

Copy-on-Write가 기본이 되면서 **인덱싱 결과는 언제나 복사본처럼 동작**합니다. 공식 문서의 표현을 빌리면 이렇습니다.

> 모든 인덱싱 연산의 결과는, 그리고 새 DataFrame·Series를 반환하는 모든 메서드는, 사용자 API 관점에서 **언제나 복사본처럼 동작한다.**

규칙이 일관돼진 것은 분명한 개선입니다. 다만 **중간 결과를 변수에 담아두고 나중에 쓰는 코드**는 가정이 깨집니다. 전처리 함수를 길게 이어 붙인 코드에서 나오기 쉽습니다.

## 3. 문자열 dtype이 object가 아닙니다

```python
>>> s = pd.Series(["a", "b"])
>>> s.dtype
str
>>> s.dtype == object
False
```

`dtype == object` 로 문자열 열을 골라내던 코드가 **아무것도 못 고르게 됩니다.** 예외는 안 납니다. 빈 결과가 나올 뿐입니다.

두 가지가 더 딸려옵니다.

```python
>>> pd.Series(["a", None]).iloc[1]
nan                       # 결측 표식은 NaN

>>> s.iloc[0] = 1
TypeError                 # 문자열 열에 숫자를 넣으면 거부
```

전에는 `object` 열이라 뭐든 들어갔는데, 이제 **문자열 아니면 거부**합니다. 이건 오히려 예외가 나므로 찾기 쉬운 축입니다.

## 4. datetime이 나노초가 아닐 수 있습니다

가장 위험한 항목이라고 봅니다.

```python
>>> pd.to_datetime(["2026-03-22 11:36"]).dtype
datetime64[us]
>>> pd.to_datetime([0], unit="s").dtype
datetime64[s]
>>> pd.date_range("2026-01-01", periods=3, freq="h").dtype
datetime64[us]
```

전에는 뭘 넣든 `datetime64[ns]` 로 통일됐는데, 이제 **입력에 맞춰 해상도를 추론**합니다.

여기서 조용한 사고가 납니다.

```python
>>> t = pd.to_datetime(["2026-03-22 11:36"])
>>> t.astype("int64")[0]
1774179360000000            # us 기준

>>> pd.Timestamp("2026-03-22 11:36").value
1774179360000000000         # ns 기준
```

**정확히 1000배 차이입니다.** 타임스탬프를 정수로 바꿔 다른 시스템에 넘기거나, DB에 넣거나, 파일명으로 쓰던 코드는 값이 1000분의 1이 됩니다. 예외는 나지 않습니다.

공식 문서도 이 지점을 명시적으로 경고하고 있습니다.

> 많은 사용자가 예전에 `datetime64[ns]` 를 받던 곳에서 이제 `datetime64[us]` 를 받게 된다. 큰 예외 하나는 **정수로 변환하는 경우로, 1000배 작은 정수가 나온다.**

시계열을 다룬다면 [Pandas datetime 함수를 이용한 시계열 데이터 전처리](/posts/timeseris_preprocess/) 편에서 쓴 코드도 한 번 확인해보시는 게 좋겠습니다. 해상도를 고정하고 싶으면 `.astype("datetime64[ns]")` 로 명시하면 됩니다.

## 5. Day(1)은 24시간이 아닙니다

서머타임 경계에서 `Day` 오프셋과 `Timedelta` 가 갈라집니다.

```python
>>> ts = pd.Timestamp("2026-03-07 08:00", tz="US/Eastern")
>>> ts + pd.offsets.Day(1)
Timestamp('2026-03-08 08:00:00-04:00')   # 시각 유지 (달력 하루)

>>> ts + pd.Timedelta(days=1)
Timestamp('2026-03-08 09:00:00-04:00')   # 정확히 24시간
```

`Day(1)` 이 **달력상 하루**를 뜻하도록 바뀌어서, 서머타임을 넘어도 시각이 유지됩니다. 의도로 보면 자연스러운 정의이지만, 예전 결과에 맞춰둔 코드는 한 시간씩 어긋납니다.

한국은 서머타임이 없어서 **국내 데이터만 다룬다면 영향이 없습니다.** 해외 타임스탬프를 다룰 때만 신경 쓰면 됩니다.

시간대 처리 자체도 바뀌었습니다.

```python
>>> type(ts.tz)
zoneinfo.ZoneInfo          # 전에는 pytz.DstTzInfo
```

표준 라이브러리 `zoneinfo` 를 쓰게 되면서 **pytz가 필수 의존성에서 빠졌습니다.** `pytz` 객체를 직접 다루던 코드가 있다면 확인이 필요합니다.

## 올리기 전에 훑을 것

코드베이스에서 이 패턴들을 먼저 찾아보시면 됩니다.

| 찾을 패턴 | 왜 |
|---|---|
| `df[...][...] = ` | 연쇄 할당. 동작 안 함 |
| `dtype == object` | 문자열 열을 못 고름 |
| `astype("int64")` 가 datetime에 붙은 곳 | 1000배 오차 |
| `.value` / `.view("int64")` | 위와 동일 |
| `import pytz` | 더 이상 필수 의존성 아님 |
| `offsets.Day(` | 서머타임 경계에서 결과 변경 |

연쇄 할당은 경고를 예외로 올려두면 확실히 잡힙니다. **스크립트 안에서** 걸어야 합니다.

```python
import warnings
import pandas as pd

warnings.simplefilter("error", pd.errors.ChainedAssignmentError)
```

이렇게 두면 그 자리에서 예외로 멈추므로, 조용히 지나가는 대신 스택 트레이스가 남습니다.

> 명령줄 `-W error::...` 로는 안 잡힙니다. `python -W error::FutureWarning` 도, 클래스 경로를 정확히 준 `-W error::pandas.errors.ChainedAssignmentError` 도 시도해봤는데 둘 다 스크립트가 그냥 통과했습니다. `-W` 는 pandas를 import 하기 전에 해석되기 때문으로 보입니다.
{: .prompt-tip }

## 정리

pandas 3.0의 변경은 대체로 **규칙을 일관되게 만드는 방향**입니다. "될 때도 있고 안 될 때도 있던" Copy-on-Write가 항상 복사본으로 정리됐고, 문자열에 전용 dtype이 생겼고, datetime 해상도가 입력을 따라갑니다.

다만 옮기는 입장에서는 **예외가 나는 쪽보다 안 나는 쪽이 위험합니다.** 이 글에서 본 것 중 예외가 나는 건 문자열 열에 숫자를 넣는 경우뿐이고, 나머지는 전부 조용히 결과만 달라집니다.

특히 **datetime을 정수로 바꾸는 코드**가 있다면 그것부터 확인하시길 권합니다. 1000배는 눈으로 보면 티가 나지만, 파이프라인 중간에 있으면 한참 뒤에 발견됩니다.

## 참고

- [What's new in 3.0.0](https://pandas.pydata.org/docs/whatsnew/v3.0.0.html) — pandas 공식 문서 (2026-08-19 확인). 릴리스일 2026-01-21, 인용문은 이 문서에서 옮겼습니다
- [Copy-on-Write 사용자 가이드](https://pandas.pydata.org/pandas-docs/stable/user_guide/copy_on_write.html) — 연쇄 할당이 왜 안 되는지에 대한 공식 설명
- [Pandas 라이브러리 datetime 함수를 이용한 시계열 데이터 전처리](/posts/timeseris_preprocess/) — 해상도 변경의 영향을 받는 코드
- [여러 개의 csv 파일을 불러와서 하나의 데이터프레임으로 만들기](/posts/dataframe_concat/) — `read_csv` 로 들어오는 dtype이 달라집니다
