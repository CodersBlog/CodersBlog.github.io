---
title: "[Python] logger를 사용하여 코드 기록 남기기"
excerpt: "Description of python logging by sehoon-lee"

categories:
    - python
tags:
    - [python]

toc: true
toc_sticky: true

date: 2024-11-14
last_modified_at: 2024-11-14

math: true
---

이번 게시물에는 파이썬의 logging 라이브러리를 이용해 코드 진행상황을 기록하여 활용하는 방법을 알아보겠습니다.

## 1. 로그(log)란?

로그는 시스템이나 어플리케이션에서 발생하는 다양한 이벤트와 활동을 기록한 데이터를 의미합니다. 로그에는 주로 아래와 같은 내용들을 기록합니다.
- 타임 스탬프 : 시스템상 로그를 기록한 시간 정보를 의미합니다.
- 이벤트 유형 : 이벤트 유형에는 Error, Warning, Info 등 이 있습니다. 이는 로깅 레벨에도 사용하는 것들입니다.
- 이벤트 원본 : 어떤 프로그램 또는 프로세스 등이 이벤트를 발생 시켰는지 지록합니다.
- 메세지 내용 : 유저가 기록하고 싶은 메세지 내용을 의미합니다.

<br>

## 2. 로깅 레벨

로그를 기록할 때 파일이나 스트림으로 어떤 로그 레벨부터 나타낼 것인지 설정을 할 수 있습니다. 중요도에 따라 각 레벨이 나누어 집니다. 아래에 중요도가 높은 순서 대로 나열 해 보았습니다.

- Debug : 디버깅 정보, 개발 중 기록할만한 상세 정보를 나타냄
- Info : 일반 적인 메세지를 의미함. 주로 정상 작동에 대한 내용을 기록함
- Warning : 문제가 될 수 있는 가능성에 대한 정보를 기록함
- Error : 오류 내용에 대한 기록

특정 중요도로 로깅 레벨을 설정하면 해당 로깅 레벨보다 중요도가 약한 정보들은 모두 기록됨


## 3. 예시 로깅 설정

```python
import os
import logging
from datetime import datetime
from logging.handlers import TimedRotatingFileHandler

class Logger:
    def __init__(self, logger_name="my_logger", log_dir="logs"):
        # 날짜별 폴더 생성
        current_date = datetime.now().strftime("%Y-%m-%d")
        self.log_dir = os.path.join(log_dir, current_date)  # logs/YYYY-MM-DD 폴더 생성
        os.makedirs(self.log_dir, exist_ok=True)  # 폴더가 없으면 생성

        # 로그 파일 이름 설정 (logger name 포함)
        log_file = os.path.join(self.log_dir, f"{logger_name}_{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.log")

        # 로거 설정
        self.logger = logging.getLogger(logger_name)
        self.logger.setLevel(logging.DEBUG)  # 원하는 로그 레벨 설정

        # 파일 핸들러 생성
        file_handler = TimedRotatingFileHandler(log_file, when="midnight", interval=1)
        file_handler.suffix = "%Y-%m-%d_%H-%M-%S.log"  # 파일명에 날짜 및 시간 형식 추가
        file_handler.setLevel(logging.DEBUG)

        # 콘솔 핸들러 생성
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.DEBUG)
        
        # 로그 형식 설정 (파일 이름과 함수 이름 포함)
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(funcName)s] - %(message)s'
        )
        file_handler.setFormatter(formatter)
        console_handler.setFormatter(formatter)

        # 로거에 핸들러 추가
        self.logger.addHandler(file_handler)
        self.logger.addHandler(console_handler)

    def get_logger(self):
        return self.logger
```
위 설정대로 파일을 작성하여 import 하여 사용이 가능하다. 현재 설정으로는 파일에도 기록하고, 스트림으로 커맨드창에도 나타내게 설정을 하였습니다.

위 코드에서 중요한 부분은 우선 TimedRotationgFileHandler 를 사용한 부분으로 로그를 계속 기록하다가 자정이 넘어가면 새로운 파일에 기록이 되도록 설정하였습니다.

다음으로는 foratter 로 로그가 기록되는 형태에 대해 설정하는 부분이다. 각자가 표현하고 싶은대로 순서를 변환하여 사용할 수 있습니다.

위 코드는 기본 설정이므로 각자 상황에 맞게 설정을 추가하거나 변형하여 사용이 가능합니다.

