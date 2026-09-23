---
title: "[Git] 브랜치부터 rebase와 PR 병합까지 — 안전하게 push하는 협업 흐름"
excerpt: "commit, fetch, rebase, push, Pull Request가 어떻게 이어지는지 초보자 관점에서 설명하고, merge commit·squash·rebase 병합과 충돌 해결을 예제로 정리합니다."
description: "Git 협업의 전체 흐름을 브랜치와 커밋 그래프부터 설명합니다. fetch와 pull, rebase와 merge, fast-forward push, force-with-lease, GitHub Pull Request 병합 방식의 차이를 안전한 명령 순서와 함께 익힙니다."

categories:
    - Dev
tags:
    - [Git, GitHub, rebase, pull request, 협업]

toc: true
toc_sticky: true

date: 2026-09-23
last_modified_at: 2026-09-23
---

처음 Git을 배울 때는 `git add`, `git commit`, `git push`만 익혀도 혼자 작업을 저장할 수 있습니다. 그런데 여러 사람이 같은 저장소에서 일하기 시작하면 이런 질문이 생깁니다.

- `git pull`을 했는데 왜 merge commit이 생기지?
- `rebase`는 `merge`와 무엇이 다르지?
- push가 `rejected (fetch first)`로 거절되면 무엇을 해야 하지?
- Pull Request를 만들었는데 **Create a merge commit**, **Squash and merge**, **Rebase and merge** 중 무엇을 골라야 하지?

이 글은 명령어 목록보다 먼저, 로컬과 원격 저장소의 커밋이 어떻게 움직이는지를 그림으로 살펴봅니다. 예제는 GitHub 같은 원격 호스트와 `main`을 사용하는 일반적인 팀 저장소를 가정합니다. 실제로 허용되는 push와 병합은 저장소의 권한 및 브랜치 보호 규칙에 따라 달라질 수 있습니다.

## 1. Git은 파일이 아니라 커밋의 흐름을 기록합니다

작업 디렉터리의 파일을 수정했다고 해서 기록이 자동으로 만들어지는 것은 아닙니다. `git add`로 다음 커밋에 넣을 변경을 고르고, `git commit`으로 그 묶음을 로컬 저장소의 기록에 추가합니다.

```text
A ── B ── C  main
```

각 글자는 하나의 커밋이라고 생각하면 됩니다. 브랜치는 커밋을 가리키는 이름표입니다. `main`은 현재 기준 커밋을 가리키고, 새 브랜치 `feature/search`를 만들면 처음에는 둘 다 같은 커밋을 가리킵니다.

```text
A ── B  main, feature/search
```

기능 브랜치에서 두 번 커밋하면 두 이름은 갈라집니다.

![공통 커밋에서 main과 기능 브랜치가 갈라지는 모습](/assets/img/post/git-workflow/branches.svg?v=aa90c9d){: .align-center}
*공통 이력은 함께 사용하고, 분기한 뒤에는 각 브랜치에서 별도로 커밋합니다.*

이 관점이 중요합니다. `push`는 내 커밋을 원격 저장소에 보내 원격 브랜치가 가리키는 위치를 옮기는 일이고, `merge`와 `rebase`는 서로 갈라진 커밋 흐름을 정리하는 방법입니다.

## 2. 원격 저장소와 `origin/main`은 각각 무엇일까요?

`origin`은 보통 GitHub 저장소에 붙인 원격 이름입니다. `origin/main`은 마지막으로 원격 정보를 가져왔을 때 관찰한 원격 `main`의 위치를 로컬에 기록한 원격 추적 브랜치입니다. 이름에 `origin`이 있어도 GitHub가 매번 즉시 갱신해 주는 표시가 아니라, `fetch` 등으로 동기화되는 로컬 기록입니다.

자주 쓰는 확인 및 동기화 명령은 다음과 같습니다.

```bash
git status -sb
git branch -vv
git remote -v
git fetch origin
```

`git fetch origin`은 원격 브랜치의 최신 정보와 커밋을 가져오지만 현재 작업 브랜치의 파일을 바꾸거나 내 브랜치를 합치지는 않습니다. 먼저 원격에 새 작업이 있는지 살펴보고 싶을 때 안전한 첫 단계입니다.

반면 `git pull`은 대략 `fetch` 뒤에 현재 브랜치를 원격 추적 브랜치와 통합하는 동작입니다. 기본 설정에 따라 통합 방식이 merge일 수도, rebase일 수도 있습니다. 팀에서 어느 방식인지 모른다면 `git pull`이 알아서 해 주겠다고 가정하기보다 두 단계를 나눠 실행하고 현재 그래프를 확인하는 편이 이해하기 쉽습니다.

```bash
git fetch origin
git log --oneline --graph --decorate --all -20
```

## 3. 초보자에게 권하는 기능 브랜치 흐름

작업 시작 전 `main`을 최신으로 맞추고, 작업마다 짧고 설명적인 브랜치를 만듭니다.

```bash
git switch main
git fetch origin
git pull --ff-only origin main
git switch -c feature/search-filter
```

`--ff-only`는 현재 브랜치에만 원격 커밋이 추가되어 있는 경우처럼, 기존 커밋을 새 merge commit 없이 앞으로 이동할 수 있을 때만 pull을 허용합니다. 로컬과 원격이 서로 다른 커밋을 가진 상태라면 임의로 merge하지 않고 멈춥니다. 이때는 상태와 그래프를 먼저 확인합니다.

기능을 작은 단위로 저장합니다.

```bash
git status
git diff
git add src/search.py tests/test_search.py
git diff --cached
git commit -m "Add search filters"
```

`git add .`는 편리하지만 원치 않는 파일도 함께 올릴 수 있습니다. 초보자라면 파일을 지정하거나 `git add -p`로 일부 변경을 선택하고, 커밋 전 `git diff --cached`로 실제 포함 내용을 확인하는 습관이 좋습니다.

원격에 같은 이름의 기능 브랜치를 처음 올립니다.

```bash
git push -u origin feature/search-filter
```

`-u`는 로컬 브랜치와 원격 브랜치 사이의 기본 추적 관계를 설정합니다. 다음부터는 그 브랜치에서 `git push`와 `git pull`만으로 대상 원격 브랜치를 지정할 수 있습니다. 저장소의 기본 브랜치에 바로 push할 수 있는지는 권한과 보호 규칙에 달려 있으며, 팀 협업에서는 보통 기능 브랜치에 push한 뒤 Pull Request를 엽니다.

## 4. `merge`는 두 갈래를 함께 보존합니다

기능 브랜치를 작업하는 동안 `main`에도 새 커밋이 들어왔다고 해 봅시다.

`main`을 기능 브랜치에 merge하면 두 갈래를 부모로 가진 새 커밋이 생깁니다.

![merge 전후의 커밋 그래프](/assets/img/post/git-workflow/merge.svg?v=aa90c9d){: .align-center}
*기능 브랜치에 main을 합치면 두 이력을 연결하는 merge 커밋 M이 생깁니다.*

merge는 실제로 어떤 두 흐름을 합쳤는지 기록으로 남깁니다. 팀원이 이미 공유한 커밋을 재작성하지 않아도 된다는 장점이 있습니다. 반면 자주 합치면 히스토리에 merge commit이 늘어날 수 있습니다.

```bash
git fetch origin
git switch feature/search-filter
git merge origin/main
```

병합 충돌(conflict)이 나면 Git이 자동으로 선택하지 못한 파일을 표시합니다. 각 파일에서 최종으로 남길 내용을 편집하고, 충돌 표시인 `<<<<<<<`, `=======`, `>>>>>>>`를 제거한 다음 확인합니다.

```bash
git status
# 파일을 편집하고 충돌 표시를 해결
git add src/search.py
git commit                  # merge를 마무리
```

문제가 생겨 merge 진행을 취소하고 이전 상태로 돌아가려면 완료 전에 다음 명령을 쓸 수 있습니다.

```bash
git merge --abort
```

## 5. `rebase`는 내 커밋을 새 기준 위에 다시 놓습니다

같은 시작점에서 기능 브랜치가 `C`, `D`를 만들고 `main`이 `E`로 이동했다고 합시다. rebase는 내 변경을 `E` 위에 다시 적용합니다.

![rebase 전후의 커밋 그래프](/assets/img/post/git-workflow/rebase.svg?v=aa90c9d){: .align-center}
*C와 D를 E 위에 다시 적용하면 내용이 이어져도 새 커밋 C′와 D′가 만들어집니다.*

`C'`, `D'`는 원래 커밋과 내용이 비슷해도 새 커밋입니다. 부모 커밋이 달라졌기 때문에 커밋 ID도 바뀝니다. 결과는 한 줄로 읽기 쉬워지지만, 기존 커밋을 새 커밋으로 교체하는 기록 재작성(history rewrite)입니다.

```bash
git fetch origin
git switch feature/search-filter
git rebase origin/main
```

충돌이 나면 파일을 고친 뒤 계속하거나, rebase 전으로 돌아갑니다.

```bash
git status
# 충돌 파일 편집
git add src/search.py
git rebase --continue

# 계속하지 않고 rebase를 시작하기 전으로 취소하려면
git rebase --abort
```

`git rebase --skip`은 현재 커밋을 통째로 건너뛰는 명령입니다. 그 커밋의 변경이 이미 다른 곳에 반영된 것을 확인했을 때만 사용하세요. 단순히 충돌이 어렵다는 이유로 건너뛰면 작업이 빠질 수 있습니다.

### rebase를 써도 괜찮은 때

- 아직 다른 사람이 기반으로 작업하지 않는 내 로컬 커밋을 정리할 때
- Pull Request 브랜치를 최신 `main` 위로 올려 선형 히스토리를 만들 때
- 팀의 명시적인 정책과 협의에 따라 공유 브랜치를 함께 관리할 때

### rebase를 피해야 하는 때

- 이미 동료가 가져가서 후속 커밋을 만든 공유 브랜치의 기록을 동의 없이 다시 쓸 때
- `main` 같은 공동 기준 브랜치를 임의로 재작성할 때
- 어떤 커밋을 덮어쓰는지 확인하지 않고 `git push --force`를 할 때

기억할 규칙은 간단합니다. **혼자 쓰는 커밋은 필요하면 다시 정리할 수 있지만, 공유되어 다른 사람이 기반으로 삼은 커밋은 함부로 바꾸지 않습니다.**

## 6. Push 거절은 원격의 작업을 지우지 말라는 신호입니다

로컬과 원격 브랜치가 같은 커밋 `B`에서 시작했지만, 동료는 `E`를 push하고 나는 `C`, `D`를 만들었다고 합시다.

![로컬과 원격의 이력이 갈라져 push가 거절되는 상황](/assets/img/post/git-workflow/push-rejected.svg?v=aa90c9d){: .align-center}
*먼저 원격 커밋을 가져와 내 변경과 통합해야 원격 작업을 보존할 수 있습니다.*

내 `D`를 원격의 `E` 위에 그대로 덮으면 동료의 `E`가 원격 브랜치에서 사라질 수 있습니다. 그래서 Git은 기본적으로 fast-forward가 아닌 push를 거부합니다. 이는 오류라기보다 원격 작업을 보호하는 안전장치입니다.

먼저 원격 기록을 가져오고 통합합니다.

```bash
git fetch origin
git rebase origin/feature/search-filter
# 충돌을 해결하고 git rebase --continue, 또는 git rebase --abort
git push
```

팀이 merge 방식을 쓰기로 했다면 다음처럼 합니다.

```bash
git fetch origin
git merge origin/feature/search-filter
git push
```

rebase를 이미 원격에 올린 내 브랜치에서 진행했다면 커밋 ID가 바뀌므로 일반 push가 거절될 수 있습니다. 브랜치를 정말 나만 수정했고, 덮어쓰려는 원격 변경이 다른 사람 작업이 아닌지 확인한 경우에만 다음을 고려합니다.

```bash
git push --force-with-lease
```

`--force-with-lease`는 내가 마지막으로 알고 있던 원격 위치가 그대로일 때만 강제 갱신하도록 요구하는 안전장치입니다. 그렇더라도 공유 브랜치에 대한 강제 갱신은 동료의 작업을 덮어쓸 수 있습니다. 팀 정책을 먼저 확인하세요. 일반 `--force`는 이 보호 확인을 하지 않으므로 초보자에게 복구 명령처럼 권하지 않습니다.

## 7. Pull Request는 검토와 병합을 위한 제안입니다

기능 브랜치를 push한 뒤 Pull Request(PR)를 열면, “이 브랜치의 변경을 기준 브랜치에 반영해 주세요”라는 검토 가능한 제안이 생깁니다. 리뷰어는 변경 파일과 커밋을 살펴보고, 질문·수정 요청을 남길 수 있습니다. 자동 검사는 테스트, 린트, 빌드 등을 수행할 수 있습니다.

PR을 만든 뒤에도 기능 브랜치에 추가 커밋을 push하면 같은 PR에 자동으로 반영됩니다. 일반적인 순서는 다음과 같습니다.

1. 최신 `main`에서 기능 브랜치를 만듭니다.
2. 작은 단위로 커밋하고 원격 기능 브랜치에 push합니다.
3. Pull Request를 열고 목적, 주요 변경, 확인 방법을 적습니다.
4. 리뷰 의견과 자동 검사 결과를 확인하고, 필요하면 수정 커밋을 push합니다.
5. 저장소의 필수 승인과 검사를 만족하면 정해진 방식으로 병합합니다.
6. 병합 후 로컬 `main`을 동기화하고 이미 끝난 원격 기능 브랜치를 삭제합니다.

브랜치 보호 규칙에 따라 PR 승인, 상태 검사 통과, 대화 해결, 선형 히스토리 등이 필수일 수 있습니다. 어떤 규칙이 적용되는지는 저장소마다 다르므로, 버튼이 보인다는 이유만으로 팀 정책을 추측하면 안 됩니다.

## 8. GitHub의 세 가지 PR 병합 방식

### Create a merge commit

기능 브랜치의 커밋을 그대로 두고 기준 브랜치와 합치는 merge commit을 추가합니다. 브랜치가 갈라졌다 합쳐진 사실과 개별 커밋을 모두 보존합니다. 복잡한 작업 흐름을 그대로 추적해야 할 때 유용하지만, 프로젝트 기록에 merge commit이 추가됩니다.

### Squash and merge

PR의 여러 커밋을 기준 브랜치에 하나의 새 커밋으로 합칩니다. 작업 중의 “WIP”, “fix typo” 같은 세부 커밋은 기준 브랜치 기록에서 숨기고 완성된 변경 단위로 남길 수 있습니다. 기능 브랜치 안의 세부 히스토리가 중요하지 않은 작은 팀이나 기본적인 코드 리뷰 흐름에서 이해하기 쉽습니다.

### Rebase and merge

PR의 커밋들을 기준 브랜치의 최신 끝에 하나씩 다시 적용하고, merge commit 없이 반영합니다. 선형 기록을 만들지만 반영되는 커밋 ID가 새로 만들어집니다. 이미 다른 곳에서 참조 중인 동일 커밋과 ID가 달라질 수 있다는 점을 기억해야 합니다.

세 옵션 중 하나가 모든 팀에 정답인 것은 아닙니다. 프로젝트가 요구하는 이력의 형태, 커밋 단위의 의미, 브랜치 보호 설정을 따르세요. GitHub에서 실제로 제공되는 옵션은 저장소 설정과 보호 규칙에 따라 달라집니다.

## 9. 충돌은 누가 틀렸다는 뜻이 아닙니다

충돌은 Git이 두 변경 중 어떤 결과가 의도된 것인지 자동으로 결정하지 못했다는 뜻입니다. 같은 줄을 양쪽이 다르게 바꾸었을 때 흔하지만, 주변 문맥이나 파일 이동 때문에 생길 수도 있습니다.

충돌 해결 때는 “내 쪽/상대 쪽 중 하나를 선택”하기보다, 두 변경의 목적을 확인해 최종 파일 내용을 직접 만듭니다. 그 뒤 관련 테스트나 검사를 실행하고 `git diff`로 결과를 확인합니다. 해결했다고 표시하는 `git add`는 내용을 검증하는 명령이 아니라 “이 파일의 충돌 표시를 해결했다”는 기록입니다.

현재 진행 중인 작업을 확인하는 데는 다음 명령이 도움이 됩니다.

```bash
git status
git diff
git diff --check
git log --oneline --graph --decorate --all -20
```

## 10. 병합 뒤 정리와 초보자용 체크리스트

PR이 병합되면 로컬 기준 브랜치를 갱신하고 기능 브랜치를 정리합니다.

```bash
git switch main
git pull --ff-only origin main
git branch -d feature/search-filter
git fetch --prune origin
```

`git branch -d`는 병합되지 않은 작업이 남아 있으면 경고하며 삭제를 거부합니다. 그 경고를 무시하기 위해 무조건 `-D`로 바꾸지 말고, 먼저 원격 PR 상태와 해당 브랜치의 커밋을 확인하세요.

처음 협업할 때는 다음 원칙만 지켜도 위험한 상황을 크게 줄일 수 있습니다.

- 작업 전 `git status`와 현재 브랜치를 확인합니다.
- 기능은 별도 브랜치에서 작업하고 PR로 검토받습니다.
- push가 거절되면 원격 변경을 가져와 확인하고 통합합니다.
- rebase는 공유된 커밋을 새 ID로 바꿀 수 있음을 기억합니다.
- 강제 push 전에는 원격과 로컬 로그를 비교하고 동료와 확인합니다.
- 충돌은 최종 내용을 판단해 해결하고, 검사 후 커밋합니다.
- merge 방식과 브랜치 보호 규칙은 저장소 정책을 따릅니다.

Git에서 `merge`와 `rebase` 중 하나만 외우는 것이 목표는 아닙니다. **기록을 보존하며 합칠지, 내 커밋을 새 기준 위에 다시 쓸지**를 상황에 맞게 고르고, 원격 기록을 덮어쓸 수 있는 동작에는 신중해지는 것이 핵심입니다.

## 참고 자료

- [Git 공식 문서: git-rebase](https://git-scm.com/docs/git-rebase)
- [Git 공식 문서: git-push](https://git-scm.com/docs/git-push)
- [Git 공식 문서: git-pull](https://git-scm.com/docs/git-pull)
- [GitHub Docs: About merge methods on GitHub](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/about-merge-methods-on-github)
- [GitHub Docs: Merging a pull request](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-a-pull-request)
- [GitHub Docs: About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
