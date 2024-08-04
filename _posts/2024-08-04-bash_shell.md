---
title: "[Bash] Bash 쉘 스크립트 문법 [1편]"
excerpt: "Description of linux command by sehoon-lee"

categories:
    - linux, bash
tags:
    - [linux], [bash]

toc: true
toc_sticky: true

date: 2024-08-04
last_modified_at: 2023-08-04

math: true
---

이번 게시물에는 Bash shell 스크립트 문법에 대해 알아보겠습니다.

## 1. echo

echo는 변수 및 문자열을 출력하는데 사용함
printf와 다른점은 printf 는 변수의 타입을 지정해주어야 변수와 함께 출력이 가능합니다.

```bash
#! /usr/bin/bash

name="son"
number=7

echo "my name is mr.${name}."
printf "my back number is %s \n" $number
```
<br>

![img_file](/assets/img/post/bash_shell/result_1.png){: .align-center}

<br>

## 2. 전역 변수와 지역 변수

대부분 사용하는 변수들이 전역 변수 인데 함수 내부에서 local을 붙여서 선언하는 경우 지역 변수로 사용되며 해당 함수 안에서만 사용된다.

```bash
#!/usr/bin/bash

string="hello world"

function string_test() {
        # local을 붙여야 지역변수로 인식함
        local string="hello local @@"
        echo $string
}

# 함수 도출
string_test
echo $string

# 변수 초기화
unset string
```
<br>

![img_file](/assets/img/post/bash_shell/result_2.png){: .align-center}

<br>

## 3. 변수 활용

변수를 선언할 때 declare를 사용하는데, 여기서 - 로 옵션을 부여하여 변수에 대한 권한을 부여하거나 타입을 지정할 수 있음

```bash
#! /usr/bin/bash

# declare를 사용하면 변수를 선언만 함.
# 여기서 -? 를 통해 몇가지 옵션을 부여할 수 있음
# -r 옵션은 읽기 전용으로 아래와 같이 선언할 수 있음
declare -r var1
readonly var1

# 옵션으로 데이터 타입을 지정할 수도 있음
# -i 정수형 타입
declare -i number
number=3
echo "number = $number"

# -a 배열 타입
declare -a indices

# -A 연관배역(MAP) 타입
declare -A map

# -x 환경변수(export) 지정
declare -x var3 # 외부 환경에서도 이 변수를 사용할 수 있게됨
```
<br>

## 4. export 한 변수 사용

export 한 변수는 다른 bash 파일에서 사용 가능합니다.
- study_4_1.sh

```bash
#! /usr/bin/bash

export hello_world="global hello world"

bash ./study_4.sh
```
- study_4.sh

```bash
#! /usr/bin/bash

echo ${hello_world}
```
<br>

![img_file](/assets/img/post/bash_shell/result_3.png){: .align-center}

<br>

## 5. 매개변수

bash 파일을 실행할 때 매개변수를 입력하고 이를 bash 스크립트 안에서 이용하는 방법을 알아보겠습니다.

```bash
#! /usr/bin/bash

echo "script name : ${0}" # 실행하는 스크립트 파일 이름
echo "매개변수 갯수 : ${#}" # 매개변수의 갯수를 나타냄
echo "전체 매개변수 값 : ${*}" # 모든 매개 변수를 보여줌
echo "전체 매개변수 값2 : ${@}"
echo "매개변수 1 : ${1}" # 1번째 매개변수
echo "매개변수 2 : ${2}" # 2번째 매개변수
```

<br>

![img_file](/assets/img/post/bash_shell/result_4.png){: .align-center}

<br>

이후 if, for 등 추가적으로 알아보도록 하겠습니다.