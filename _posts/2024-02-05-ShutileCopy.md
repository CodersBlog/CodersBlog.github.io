---
title: "[Library] shutil을 이용한 파일 복사와 폴더 복사"
excerpt: "Description of file and folder copy function using shutil by Junhyuns"

categories:
    - Python
tags:
    - [Python, shutil, file copy, folder copy]

toc: true
toc_sticky: true

date: 2024-02-05
last_modified_at: 2024-02-05

math: true
---

이번 게시물에서는 shutil 라이브러리를 활용하여 파일과 폴더를 복사하는 방법에 대해서 알아보도록 하겠습니다.

## shutil을 이용한 파일 복사 (File copy)

먼저 shutil에는 파일을 복사하기 위한 세 함수가 있습니다.


```python
import shutil

shutil.copy("Original Path", "Copied Path")
shutil.copyfile("Original Path", "Copied Path")
shutil.copy2("Original Path", "Copied Path")
```

<br>

세 함수 모두 사용법은 같으며 괄호 안에 첫 번째 인자로 복사할 파일의 경로를 넣어주고 두 번째 인자로 파일을 복사할 새로운 경로를 넣어주면 됩니다. 만약 기존 경로와 동일한 경로로 두 번째 인자를 입력했다면 덮어쓰기가 됩니다.

세 함수의 차이점은 shutil.copy와 shutil.copyfile은 파일을 복사하면서 해당 파일의 메타 데이터를 복사하지 않으므로 수정한 날짜가 복사 시점으로 변경됩니다. 하지만 shutil.copy2는 해당 파일의 메타 데이터를 복사하므로 수정한 날짜가 원본 파일의 수정한 날짜와 동일합니다.

<br>

```python
import shutil

original_file = "./data/Original.txt"
Copied_file = "./data/Copied.txt"

shutil.copy(original_file, Copied_file)
```

<br>

```python
import shutil

original_file = "./data/Original.txt"
Copied_file = "./data/Copied.txt"

shutil.copy2(original_file, Copied_file)
```

<br>

![img_file](/assets/img/post/shutilcopy/post.png){: .align-center}*좌: shutil.copy, 우: shutil.copy2*

## shutil을 이용한 폴더 복사 (Folder copy)

폴더를 복사하기 위해서는 shutil.copytree 함수를 이용할 수 있습니다.

```python
import shutil

shutil.copytree("Original Path", "Copied Path")
```

<br>

사용법은 앞선 파일 복사 함수들과 같이 첫 번째 인자에 기존 폴더의 경로를 입력하고 두 번째 인자에 복사할 위치의 경로를 입력하면 됩니다.

하지만 앞선 파일 복사 함수들과 다르게 shutil.copytree 함수는 덮어쓰기가 되지 않는다는 점을 신경써야 합니다. 만약 두 번째 인자에 기존에 있는 폴더의 경로가 입력이 되면 아래와 같은 오류가 발생합니다.

<br>

![img_folder](/assets/img/post/shutilcopy/folder.png){: .align-center}*copytree 오류*

<br>

이러한 문제를 해결하기 위해서는 shutil.copytree 함수에서 아래와 같이 dirs_exist_ok 인자에 True를 넣어주면 됩니다. 해당 인자를 추가해주면 새로운 경로에 똑같은 폴더가 존재하면 덮어쓰기가 진행됩니다.

<br>

```python
import shutil

original_folder = "./data/original_folder"
Copied_folder = "./data/copied_folder"

shutil.copytree(original_folder, Copied_folder, dirs_exist_ok=True)
```