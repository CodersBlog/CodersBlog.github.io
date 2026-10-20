---
title: "[Git] .gitignore가 안 먹는 이유를 추적 상태와 규칙 출처로 진단하기"
excerpt: "이미 추적된 파일, 중첩된 부정 패턴, 개인 exclude가 섞인 저장소에서 실제로 이긴 규칙을 찾고 안전하게 원복하는 실무 가이드"
description: "Git .gitignore 문제를 index 추적 상태와 규칙 출처로 진단하고, git rm --cached와 부정 패턴을 안전하게 적용·원복하는 방법을 설명합니다."
categories:
  - Dev
tags:
  - [Git, gitignore, tracking, git-check-ignore, repository-safety]
toc: true
toc_sticky: true
date: 2026-10-17
last_modified_at: 2026-10-17
---
<div style="max-width:860px;margin:0 auto;font-family:Arial,'Malgun Gothic',sans-serif;color:var(--text-color);line-height:1.75;">
<p style="margin:0 0 18px;color:var(--text-color);">앞선 글 <a href="https://codersblog.github.io/posts/git-config-alias-customization/" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 설정과 alias 커스터마이징</a>에서는 설정의 system·global·local·worktree 출처를 확인한 뒤 가장 작은 범위만 바꾸는 방법을 다뤘습니다. 하지만 파일을 ignore하는 규칙은 index의 추적 상태, 저장소 안팎의 exclude 파일, 디렉터리별 패턴이 함께 결정합니다. 이번 글은 “<code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">.gitignore</code>에 썼는데 계속 보인다”와 “필요한 파일까지 사라진다”를 같은 진단 흐름으로 해결합니다.</p>

        <div style="margin:22px 0;padding:18px 20px;border-left:5px solid #d86565;border-radius:10px;background:var(--card-bg);">
          <p style="margin:0 0 8px;color:var(--heading-color);font-weight:700;">대상 환경과 실패 증상</p>
          <p style="margin:0;color:var(--text-color);">Windows PowerShell과 Git 2.x를 사용합니다. 팀 저장소에 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">/config/*.env</code>를 추가했는데 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">config/prod.env</code>가 계속 수정 파일로 표시되고, 반대로 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">cache/keep.txt</code>는 부정 패턴을 넣어도 나타나지 않는 상황을 가정합니다. 먼저 파일 삭제나 강제 add를 하지 않고 index와 규칙 출처를 확인합니다.</p>
        </div>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">1. 같은 증상처럼 보여도 세 문제는 다릅니다</h2>
        <table style="width:100%;margin:0 0 22px;border-collapse:collapse;border:1px solid var(--main-border-color);background:var(--card-bg);font-size:14px;">
          <thead style="background:var(--highlight-bg-color);">
            <tr style="border-bottom:1px solid var(--main-border-color);"><th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">관찰</th><th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">주된 원인</th><th style="padding:11px 12px;text-align:left;color:var(--heading-color);">먼저 실행할 진단</th></tr>
          </thead>
          <tbody style="color:var(--text-color);">
            <tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">ignore 뒤에도 수정으로 표시</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">이미 index에 tracked</td><td style="padding:10px 12px;">git ls-files --error-unmatch</td></tr>
            <tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">새 파일이 add되지 않음</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">어딘가의 exclude 규칙과 일치</td><td style="padding:10px 12px;">git check-ignore --verbose</td></tr>
            <tr><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">!패턴인데도 계속 숨음</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">부모 디렉터리 자체가 제외됨</td><td style="padding:10px 12px;">부모와 자식 경로를 각각 검사</td></tr>
          </tbody>
        </table>
        <p style="margin:0 0 18px;color:var(--text-color);"><code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">.gitignore</code>는 intentionally untracked 파일을 위한 규칙입니다. 이미 commit되었거나 stage된 경로는 ignore 규칙을 추가해도 추적이 멈추지 않습니다. 이 구분 없이 패턴만 반복 수정하면 원인은 그대로인데 규칙만 복잡해집니다.</p>

        <figure style="margin:24px 0 30px;padding:14px;border:1px solid var(--main-border-color);border-radius:14px;background:var(--card-bg);">
          <img src="/assets/img/post/git-ignore/git-ignore-tracking-flow.png" alt="먼저 git ls-files로 index 추적 여부를 확인하고, tracked면 git rm --cached 검토로, untracked면 git check-ignore verbose로 실제 규칙 출처를 찾는 흐름과 부모 디렉터리 부정 패턴 함정을 설명하는 도식" width="1200" height="760" style="display:block;width:100%;height:auto;border:0;border-radius:10px;">
          <figcaption style="margin:10px 4px 0;color:var(--text-muted-color);font-size:13px;text-align:center;">그림 1. tracked 경로와 untracked 경로를 먼저 갈라야 패턴 수정과 index 수정의 책임이 섞이지 않습니다.</figcaption>
        </figure>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">2. index에 있는지부터 확인합니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">아래 네 명령은 파일을 바꾸지 않습니다. status에서 ignored 경로를 함께 보고, 문제 경로가 index에 있는지 확인한 뒤, 기본 ignore 진단과 index를 무시한 규칙 진단을 비교합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git status --short --ignored
git ls-files --error-unmatch -- config/prod.env
git check-ignore --verbose -- config/prod.env
git check-ignore --verbose --no-index -- config/prod.env</code></pre>
        <p style="margin:0 0 14px;color:var(--text-color);"><strong>기대 관찰값:</strong> tracked 파일이면 두 번째 명령이 경로를 출력하고 종료 코드 0을 반환합니다. 세 번째 명령은 tracked 파일을 기본적으로 검사 대상에서 빼므로 아무것도 출력하지 않고 종료 코드 1이 될 수 있습니다. 네 번째 명령은 index를 무시해 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">.gitignore:1:/config/*.env config/prod.env</code>처럼 잠재적으로 맞는 규칙을 보여줍니다.</p>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>진단 분기:</strong> <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">ls-files</code>가 성공하면 패턴 문제가 아니라 추적 상태 문제입니다. 실패하면 untracked 경로이므로 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">check-ignore --verbose</code>의 source·line·pattern을 따라갑니다. status의 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">!!</code>는 ignored, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">??</code>는 untracked입니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">3. 실제로 이긴 규칙의 출처와 범위를 찾습니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">ignore 규칙은 팀이 공유하는 파일과 개인 환경용 파일을 분리해야 합니다. 아래 명령으로 global exclude의 실제 경로, 현재 저장소의 info/exclude 위치, 특정 파일에 최종 적용된 패턴을 함께 기록합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git config --show-origin --get core.excludesFile
git rev-parse --git-path info/exclude
git check-ignore --verbose -- build/app.bin scratch/note.txt .vscode/settings.json</code></pre>
        <table style="width:100%;margin:0 0 22px;border-collapse:collapse;border:1px solid var(--main-border-color);background:var(--card-bg);font-size:14px;">
          <thead style="background:var(--highlight-bg-color);"><tr style="border-bottom:1px solid var(--main-border-color);"><th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">규칙 위치</th><th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">적합한 용도</th><th style="padding:11px 12px;text-align:left;color:var(--heading-color);">공유 여부</th></tr></thead>
          <tbody style="color:var(--text-color);">
            <tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">저장소의 .gitignore</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">빌드 산출물, 팀 공통 비밀 파일 이름</td><td style="padding:10px 12px;">commit해서 팀과 공유</td></tr>
            <tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">.git/info/exclude</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">이 저장소에서만 쓰는 개인 메모·도구 산출물</td><td style="padding:10px 12px;">현재 clone에만 적용</td></tr>
            <tr><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">core.excludesFile</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">모든 저장소의 편집기·운영체제 파일</td><td style="padding:10px 12px;">사용자 환경에만 적용</td></tr>
          </tbody>
        </table>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>중단 기준:</strong> 팀원이 모두 필요한 파일을 global exclude로 숨기거나, 개인 IDE 파일을 팀 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">.gitignore</code>에 무분별하게 쌓지 않습니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">--verbose</code> 출력의 source가 예상과 다르면 그 파일을 직접 열어 마지막으로 일치한 패턴과 더 깊은 디렉터리의 규칙을 확인합니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">4. 패턴은 경로 기준과 부모 탐색 가능성을 함께 설계합니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">루트의 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">.gitignore</code>에서 다음처럼 범위를 드러내면 리뷰가 쉬워집니다. 시작 slash는 저장소 루트에 고정하고, 끝 slash는 디렉터리만 가리킵니다. 단일 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">*</code>는 slash를 넘지 않으며, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">**</code>는 여러 디렉터리 깊이를 표현할 수 있습니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">/config/*.env
/build/
logs/*
!logs/keep.log

/cache/*
!/cache/keep.txt</code></pre>
        <p style="margin:0 0 14px;color:var(--text-color);"><strong>기대 관찰값:</strong> <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">logs/app.log</code>는 무시되고 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">logs/keep.log</code>는 다시 포함됩니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">/cache/</code>로 부모 디렉터리 자체를 제외하면 Git이 내부를 순회하지 않아 뒤의 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">!/cache/keep.txt</code>가 살릴 수 없습니다. 부모는 보이게 두고 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">/cache/*</code>로 내용만 제외해야 합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git check-ignore --verbose -- logs/app.log logs/keep.log
git check-ignore --verbose -- cache/keep.txt
git status --short --ignored -- logs cache</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>관찰 팁:</strong> verbose 모드는 부정 패턴도 출력할 수 있습니다. 출력 자체만 보고 ignored라고 결론 내리지 말고 pattern이 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">!</code>로 시작하는지와 status의 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">??</code>/<code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">!!</code>를 함께 봅니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">5. 이미 tracked라면 디스크가 아니라 index에서만 뺍니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">규칙이 맞고 파일을 앞으로 공유하지 않기로 합의했다면 먼저 현재 변경과 staged 변경을 확인합니다. 그다음 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">--cached</code>로 index에서만 제거하고, working tree 파일이 남았는지와 staged 삭제 범위를 확인합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git diff -- config/prod.env
git diff --cached -- config/prod.env
git rm --cached -- config/prod.env

git diff --cached --name-status
Test-Path .\config\prod.env
git check-ignore --verbose --no-index -- config/prod.env</code></pre>
        <p style="margin:0 0 14px;color:var(--text-color);"><strong>기대 관찰값:</strong> staged 상태에는 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">D config/prod.env</code>가 나타나지만 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">Test-Path</code>는 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">True</code>입니다. 즉 다음 commit부터 저장소가 파일을 추적하지 않을 뿐 로컬 파일을 삭제하지 않습니다.</p>
        <p style="margin:0 0 14px;color:var(--text-color);"><strong>롤백:</strong> commit 전 판단이 바뀌었다면 아래처럼 staged 삭제만 복원합니다. 파일 내용은 건드리지 않습니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git restore --staged -- config/prod.env
git ls-files --error-unmatch -- config/prod.env
git status --short</code></pre>
        <div style="margin:0 0 22px;padding:18px 20px;border:1px solid #f1cf9e;border-radius:12px;background:var(--card-bg);">
          <p style="margin:0;color:var(--text-color);"><strong>비밀 파일이면 별도 사고 대응입니다.</strong> <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git rm --cached</code>와 ignore 추가는 미래 commit을 막을 뿐, 과거 commit·clone·fork에서 비밀을 지우지 않습니다. 실제 토큰이나 비밀번호가 commit됐다면 먼저 공급자에서 폐기·교체하고, 보안 담당자와 영향 범위를 확인한 뒤 이력 정리를 별도 작업으로 계획합니다. 단순히 파일을 지우고 새 commit을 push하는 것만으로는 노출이 끝나지 않습니다.</p>
        </div>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">6. 개인 규칙은 팀 .gitignore와 분리합니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">현재 저장소에서만 쓰는 개인 메모는 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">.git/info/exclude</code>에 둡니다. 모든 저장소에서 생기는 편집기 파일은 사용자가 의도적으로 global exclude 파일을 구성할 때만 넣습니다. 설정 전후에는 출처를 기록하고, 예상치 못한 파일까지 숨기면 즉시 unset합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">Add-Content .git\info\exclude 'scratch/'
git check-ignore --verbose -- scratch/note.txt

git config --global core.excludesFile "$env:USERPROFILE\.config\git\ignore"
git config --show-origin --get core.excludesFile

# 원복이 필요하면
git config --global --unset core.excludesFile</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>롤백 기준:</strong> global 설정 뒤 다른 저장소에서 필요한 파일이 사라지면 해당 설정을 unset하고, 정말 공통인 패턴만 다시 설계합니다. 기존 global exclude 파일의 내용을 덮어쓰지 말고 먼저 경로와 내용을 백업·검토합니다. 팀에 필요한 공통 규칙은 개인 설정에 숨기지 말고 저장소의 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">.gitignore</code> 변경으로 리뷰받습니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">7. commit 전에는 tracked-and-ignored와 ignored-untracked를 따로 셉니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">대량 규칙 변경은 status 한 화면만 보고 끝내지 않습니다. index에 있으면서 ignore 규칙에도 맞는 경로와, 실제로 숨겨진 untracked 경로를 분리해 목록화합니다. 새 규칙으로 중요한 fixture가 사라지지 않았는지 리뷰할 수 있습니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git ls-files -ci --exclude-standard
git ls-files -oi --exclude-standard
git diff -- .gitignore
git diff --cached --name-status
git status --short --ignored</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>배포 게이트:</strong> 첫 목록의 tracked-and-ignored 경로는 각각 의도적으로 유지할지 untrack할지 결정합니다. 두 번째 목록에는 build 산출물과 개인 파일만 있어야 합니다. staged diff에 예상보다 넓은 삭제가 보이거나 working tree 파일이 실제로 사라졌다면 commit하지 말고 staged 변경을 복원합니다.</p>

        <div style="margin:0 0 22px;padding:18px 20px;border:1px solid #bfe4dd;border-radius:12px;background:var(--card-bg);">
          <p style="margin:0;color:var(--text-color);"><strong>실측 검증:</strong> Git 2.54.0.windows.1의 격리된 저장소에서 이미 commit된 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">config/prod.env</code>를 만든 뒤 ignore 규칙을 추가했습니다. 기본 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">check-ignore</code>는 종료 코드 1로 아무 규칙도 보여주지 않았고, <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">--no-index</code>는 정확히 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">.gitignore:1:/config/*.env</code>를 가리켰습니다. <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">/cache/</code>에서는 keep 파일 재포함이 실패했지만 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">/cache/*</code>로 바꾸자 부정 패턴이 이겼습니다. <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git rm --cached</code> 뒤 staged 상태는 D였고 working file은 남았으며, <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">restore --staged</code> 후 저장소는 clean으로 돌아왔습니다.</p>
        </div>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">결론</h2>
        <p style="margin:0 0 18px;color:var(--text-color);">ignore 문제의 첫 질문은 “패턴이 맞나”가 아니라 “이 경로가 이미 index에 있나”입니다. tracked면 diff를 검토한 뒤 index에서만 빼고, untracked면 verbose 출력으로 실제 규칙 출처를 찾습니다. 부정 패턴은 부모 디렉터리를 탐색할 수 있어야 하며, 팀 규칙·저장소 개인 규칙·사용자 전역 규칙을 분리해야 합니다. 실제 비밀이 노출된 경우에는 ignore 수정과 별개로 자격 증명 폐기·교체를 먼저 수행합니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">공식 출처</h2>
        <ul style="margin:0 0 18px;padding-left:22px;color:var(--text-color);">
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/gitignore" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: gitignore</a> — 규칙 출처 우선순위, 패턴 문법, 부정 패턴, tracked 파일의 비적용 범위</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-check-ignore" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-check-ignore</a> — verbose 출력, no-index, 종료 코드와 디버깅 형식</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-ls-files" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-ls-files</a> — index 경로, ignored·others, exclude-standard 확인</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-rm" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-rm</a> — --cached가 working tree를 남기고 index에서만 제거하는 동작</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-status" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-status</a> — short 형식의 untracked와 ignored 표시</li>
          <li style="margin:8px 0;"><a href="https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository" style="color:var(--link-color);font-weight:700;text-decoration:underline;">GitHub 공식 문서: 저장소에서 민감정보 제거</a> — 먼저 secret을 폐기·교체하고 이력 정리의 부작용을 조정하는 절차</li>
        </ul>
</div>
