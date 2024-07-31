---
title: "[Linux] 리눅스에서 자주 사용하는 명령어 [1편]"
excerpt: "Description of linux command by sehoon-lee"

categories:
    - linux
tags:
    - [linux]

toc: true
toc_sticky: true

date: 2024-08-01
last_modified_at: 2023-08-01

math: true
---

이번 게시물에는 리눅스에서 프로그램 개발 및 운영 시 자주 사용하는 명령어에 대해서 알아보겠습니다.

## 1. ls

ls 명령어는 파일 또는 디렉토리 목록들을 보여주는 명령어 입니다.

```bash
ls -a # 숨김 파일 포함 모두 출력
ls -l # 자세한 정보 출력
ls -al # 자주 사용 위 두가지 옵션을 합친 것
```
<br>

## 2. cd

cd 명령어는 현재 위치를 지정한 곳으로 옮기는 명령어 입니다.

```bash
cd /path/to/directory
```

<br>

## 3. cp

cp 명령어는 파일 또는 디렉토리를 지정한 위치에 복사하는 명령어 입니다.

```bash
cp file_origin.txt file_new.txt # 파일 복사
cp -r /origin/directory /new/directory # 디렉토리 및 하위 파일들 모두 복사
cp file_origin.txt file_new.txt # 파일 복사 (덮어쓰기 전에 물어보기) 
```

<br>

## 4. mv

mv 명령어는 파일 또는 디렉토리를 이동하는 명령어 입니다.

```bash
cp file_origin.txt file_new.txt # 파일 복사
cp -r /origin/directory /new/directory # 디렉토리 및 하위 파일들 모두 복사
cp -i file_origin.txt file_new.txt # 파일 복사 (덮어쓰기 전에 물어보기) 
```

<br>

## 5. rm

mv 명령어는 파일 또는 디렉토리를 이동하는 명령어 입니다. (파일을 같은 위치에 이동하는 경우 이름 변경 됨)

```bash
mv file_origin.txt file_new.txt # 파일 이름 변경
mv /origin/directory /new/directory # 디렉토리 및 하위 파일들 모두 복사
mv -i file_origin.txt file_new.txt # 파일 복사 (덮어쓰기 전에 물어보기) 
```

<br>


## 6. ps

ps 명령어는 프로세스를 확인하는 명렁어 입니다. 

```bash
ps -ef # 모든 프로세스를 모두 자세히 보여줌
ps -u <username> # 특정 사용자가 실행한 프로세스를 보여줌
```

<br>

추후 다른 명령어들도 정리해 보도록 하겠습니다.