---
title: "[Linux] 리눅스에서 자주 사용하는 명령어 [2편]"
excerpt: "Description of linux command by sehoon-lee"

categories:
    - linux
tags:
    - [linux]

toc: true
toc_sticky: true

date: 2024-08-21
last_modified_at: 2023-08-21

math: true
---

이번 게시물에는 지난번 게시글에서 알아보던 리눅스 명렁어를 계속해서 알아보도록 하겠습니다.

## 1. netstat

netstat 명령어는 네트워크 연결 상태를 모니터링 하는 명령어 입니다. 다만, 처음에 설치가 필요한 경우가 있습니다.

```bash
netstat -al # -a 옵션은 모든 연결을 표시함, l은 listening 상태인 것만 표시함
# 리스닝 상태라는 말은 성공적으로 연결된 것을 의미함
```

<br>

## 2. grep

grep 명령어는 다양한 명령어와 함께 사용이 가능하고, 함께 사용하는 명령어의 결과 중 특정 값을 가진 것들만 보이게 할 수 있습니다.

다양한 명렁어 중 몇 가지 예시를 알아보겠습니다.

#### 2.1 ps

먼저 실행중인 프로세스 중 | grep <조건> 을 통해 조건에 일치하는 프로세스들을 나타낼 수 있습니다.

```bash
ps -ef | grep <PID> # process id를 통한 조건
ps -ef | grep python # python 프로세스만 나타냄
```
<br>

#### 2.2 netstat

netstat 명령어와 함께 사용하여 연결된 네트워크 중 특정 ip 와 port를 조건으로 하여 해당 네트워크에 대한 내용만 나타낼 수 있습니다.

```bash
netstat | grep <port number> # process id를 통한 조건
netstat | grep <ip> # python 프로세스만 나타냄
```
<br>

#### 2.3 ls

ls 명령어와 함께 사용하여 특정 조건을 포함하는 폴더 및 파일만 보이게 할 수 있습니다.

```bash
ls-al | grep <조건> # 파일 이름 일부 또는 확장자를 통한 조건
```
<br>



## 3. top

top 명령어는 프로세스 관리를 위한 명령어로 ps 와 다르게 실시간 프로세스 현황을 보여줍니다.
top 명령어 화면이 보여진 상태에서 다양한 단축키로 컨트롤이 가능합니다.

top 명령어를 보는 방법은 다음에 자세히 설명하겠습니다.

<br>

q : top 명령어 종료
c : 프로세스 명령어 전체 표시
M : 프로세스들을 메모리 사용량을 기준으로 정렬
P : 프로세스들을 cpu 사용량을 기준으로 정렬
1 : cpu 코어별 사용량을 나타냄


<br>

```bash
top
```

<br>

![img_file](/assets/img/post/linux_command_v2/top_showing.png){: .align-center}