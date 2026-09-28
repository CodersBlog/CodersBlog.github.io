---
title: "[Git] stash와 worktree로 긴급 작업 전환하기"
excerpt: "수정 중인 파일을 잃지 않고 핫픽스로 이동하고, 돌아온 뒤 정확히 복원하는 stash와 worktree 실무 가이드"
description: "Git stash로 untracked 파일과 staged 상태를 안전하게 보관·복원하고, worktree로 핫픽스 작업 공간을 병렬 운영하는 절차를 설명합니다."
categories:
  - Dev
tags:
  - [Git, stash, worktree, PowerShell, 협업]
toc: true
toc_sticky: true
date: 2026-09-26
last_modified_at: 2026-09-26
---

<div style="max-width:820px;margin:0 auto;color:#26364b;font-family:Arial,'Malgun Gothic',sans-serif;line-height:1.72;">
      <p style="margin:0 0 24px;color:#536174;font-size:17px;">수정 중인 파일을 잃지 않고 핫픽스로 이동하고, 돌아온 뒤 정확히 복원하는 절차</p>

      <div style="margin:0 0 28px;padding:18px 20px;border-left:5px solid #d86565;background:#fff6f4;border-radius:10px;">
        <p style="margin:0 0 8px;color:#9f3f3f;font-weight:700;">대상 환경과 실패 증상</p>
        <p style="margin:0;color:#3f4f63;">Windows PowerShell 또는 Git Bash에서 Git 2.23 이상을 사용하고, <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">feature/report-filter</code> 작업 도중 긴급 핫픽스를 요청받은 상황을 가정합니다. <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">git switch main</code>을 실행했을 때 “local changes would be overwritten”로 중단되거나, 미완성 변경을 억지로 커밋하고 싶지 않은 것이 시작 증상입니다.</p>
      </div>

      <p style="margin:0 0 18px;color:#3f4f63;">앞선 글 <a href="https://codersblog.github.io/posts/git-branch-rebase-push-merge-guide/" style="color:#4557b4;font-weight:700;text-decoration:underline;">브랜치부터 rebase와 PR 병합까지</a>는 브랜치를 만들고 원격과 통합하는 흐름을 설명했습니다. 다만 작업 디렉터리가 브랜치를 바꿀 수 있는 상태라고 가정했습니다. 실무에서는 저장하지 않은 변경이 많은 순간에 장애 대응이 들어옵니다. 이번 글은 그 빈틈을 <strong>짧게 보관하는 stash</strong>와 <strong>별도 폴더에서 병렬로 일하는 worktree</strong>로 메웁니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">1. 먼저 변경의 위치를 기록합니다</h2>
      <p style="margin:0 0 14px;color:#3f4f63;">전환 전에 현재 브랜치, staged 변경, unstaged 변경, untracked 파일을 한 번에 기록합니다. 이 관찰값이 복원 뒤 비교 기준입니다.</p>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git --version
git status --short --branch
git diff --stat
git diff --cached --stat</code></pre>
      <p style="margin:0 0 18px;color:#3f4f63;"><strong>기대 관찰값:</strong> 첫 줄에는 현재 브랜치가, 각 파일 앞의 두 글자에는 index와 working tree 상태가 표시됩니다. <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">??</code>는 아직 추적하지 않는 파일입니다. 이 목록을 보지 않고 전환하면 새 파일을 stash에서 빠뜨리기 쉽습니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">2. stash와 worktree는 해결하는 문제가 다릅니다</h2>
      <p style="margin:0 0 16px;color:#3f4f63;">둘 다 급한 전환에 쓰이지만 작업 모델이 다릅니다. stash는 현재 폴더를 깨끗하게 만든 뒤 순서대로 작업하고, worktree는 같은 저장소에 연결된 새 폴더를 만들어 두 브랜치를 동시에 유지합니다.</p>
      <figure style="margin:20px 0 10px;padding:12px;border:1px solid #e3e9f2;border-radius:14px;background:#f7f9fc;">
        <img src="/assets/img/post/git-stash-worktree/stash-vs-worktree.png" alt="왼쪽은 현재 폴더의 변경을 stash 선반에 보관했다가 복원하는 순차 흐름이고, 오른쪽은 공유 저장소에서 기존 기능 브랜치 폴더와 별도 핫픽스 폴더가 병렬로 연결된 구조를 비교한 그림" width="1200" height="650" style="display:block;width:100%;height:auto;border-radius:10px;">
        <figcaption style="margin:10px 8px 2px;color:#66758a;font-size:13px;text-align:center;">stash는 한 작업 공간을 비웠다가 복원하고, worktree는 브랜치마다 독립된 HEAD·index·작업 폴더를 둡니다.</figcaption>
      </figure>
      <table style="width:100%;margin:18px 0 26px;border-collapse:collapse;border:1px solid #dfe5ee;font-size:14px;">
        <thead>
          <tr style="background:#eef2f7;">
            <th style="padding:11px;border:1px solid #dfe5ee;text-align:left;color:#21324a;">판단 기준</th>
            <th style="padding:11px;border:1px solid #dfe5ee;text-align:left;color:#21324a;">stash</th>
            <th style="padding:11px;border:1px solid #dfe5ee;text-align:left;color:#21324a;">worktree</th>
          </tr>
        </thead>
        <tbody>
          <tr><td style="padding:11px;border:1px solid #dfe5ee;">추천 상황</td><td style="padding:11px;border:1px solid #dfe5ee;">몇 분 또는 몇 시간의 짧은 전환</td><td style="padding:11px;border:1px solid #dfe5ee;">핫픽스와 기존 작업을 함께 실행·검증</td></tr>
          <tr style="background:#fbfcfe;"><td style="padding:11px;border:1px solid #dfe5ee;">작업 폴더</td><td style="padding:11px;border:1px solid #dfe5ee;">기존 폴더 하나</td><td style="padding:11px;border:1px solid #dfe5ee;">브랜치별 별도 폴더</td></tr>
          <tr><td style="padding:11px;border:1px solid #dfe5ee;">주요 위험</td><td style="padding:11px;border:1px solid #dfe5ee;">untracked 누락, 너무 이른 drop</td><td style="padding:11px;border:1px solid #dfe5ee;">수정된 worktree 강제 삭제, 같은 브랜치 중복 checkout</td></tr>
          <tr style="background:#fbfcfe;"><td style="padding:11px;border:1px solid #dfe5ee;">안전한 종료</td><td style="padding:11px;border:1px solid #dfe5ee;">apply·검증 후 drop</td><td style="padding:11px;border:1px solid #dfe5ee;">clean 확인 후 worktree remove</td></tr>
        </tbody>
      </table>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">3. 짧은 전환이면 stash를 명시적으로 만듭니다</h2>
      <p style="margin:0 0 14px;color:#3f4f63;">기본 stash는 추적 중인 수정과 staged 변경을 저장하지만 untracked 파일은 포함하지 않습니다. 새 파일까지 함께 작업했다면 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">-u</code>를 붙이고, 나중에 이유를 알 수 있는 메시지를 남깁니다.</p>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git stash push -u -m "wip: report filter before login hotfix"
git stash list
git stash show --stat --include-untracked 'stash@{0}'
git status --short --branch</code></pre>
      <p style="margin:0 0 12px;color:#3f4f63;"><strong>기대 관찰값:</strong> <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">stash@{0}</code>에 메시지가 보이고, 마지막 status에는 핫픽스와 무관한 변경이 남지 않아야 합니다. PowerShell에서는 중괄호 해석을 피하려고 stash 참조를 작은따옴표로 감쌉니다.</p>
      <ul style="margin:0 0 20px;padding-left:24px;color:#3f4f63;">
        <li style="margin:7px 0;"><strong>-u:</strong> untracked 파일까지 포함하지만 ignored 파일은 포함하지 않습니다.</li>
        <li style="margin:7px 0;"><strong>-a:</strong> ignored 파일까지 치우므로 빌드 산출물·로컬 환경 파일이 예상 밖으로 이동할 수 있어 기본 절차로 권하지 않습니다.</li>
        <li style="margin:7px 0;"><strong>show:</strong> 이름과 파일 목록이 맞는지 확인하기 전에는 브랜치를 바꾸지 않습니다.</li>
      </ul>

      <h3 style="margin:26px 0 12px;color:#4557b4;font-size:19px;">핫픽스를 만들고 완료합니다</h3>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git switch main
git pull --ff-only origin main
git switch -c hotfix/login-timeout

# 수정과 테스트 후
git add src/login-timeout.ps1
git commit -m "fix: bound login request timeout"
git push -u origin hotfix/login-timeout</code></pre>
      <p style="margin:0 0 18px;color:#3f4f63;"><strong>진단 분기:</strong> 첫 switch 뒤에도 변경이 보이면 stash 대상에서 빠진 ignored 파일인지 확인합니다. <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">git clean -fd</code>로 즉시 지우지 말고 먼저 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">git clean -nd</code>로 삭제 후보만 봅니다. 핫픽스 브랜치가 이미 있다면 새 이름을 만들지 말고 원격·로컬 브랜치 상태를 확인합니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">4. 복원은 pop보다 apply 후 drop이 안전합니다</h2>
      <p style="margin:0 0 14px;color:#3f4f63;">핫픽스를 끝낸 뒤 원래 브랜치로 돌아와 working tree가 깨끗한지 확인하고 stash를 적용합니다. <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">--index</code>는 stash 전의 staged 상태까지 되살리려 시도합니다.</p>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git switch feature/report-filter
git status --short --branch
git stash apply --index 'stash@{0}'
git status --short --branch
git diff --stat
git diff --cached --stat</code></pre>
      <p style="margin:0 0 14px;color:#3f4f63;">처음 기록한 파일 목록과 staged 상태가 돌아왔고 테스트가 통과했을 때만 아래처럼 stash를 지웁니다.</p>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git stash drop 'stash@{0}'</code></pre>
      <p style="margin:0 0 18px;color:#3f4f63;"><strong>충돌 시 복구:</strong> 즉시 drop하지 말고 충돌 파일을 확인합니다. 현재 기준과 너무 멀어 적용이 복잡하다면, clean한 상태에서 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">git stash branch recover/report-filter 'stash@{0}'</code>로 stash를 만들 당시 커밋에서 복구 브랜치를 만들 수 있습니다. 성공하면 Git이 해당 stash를 목록에서 제거하므로 결과 브랜치를 먼저 확인합니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">5. 기존 작업도 실행해야 한다면 worktree를 만듭니다</h2>
      <p style="margin:0 0 14px;color:#3f4f63;">긴급 수정 중에도 기존 기능 브랜치의 개발 서버나 테스트를 계속 돌려야 한다면 stash보다 worktree가 명확합니다. 아래 예시는 현재 저장소의 형제 경로에 핫픽스 폴더를 만들고 최신 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">origin/main</code>에서 새 브랜치를 시작합니다.</p>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git fetch origin
git worktree add -b hotfix/login-timeout ..\shop-hotfix origin/main
git worktree list
git -C ..\shop-hotfix status --short --branch</code></pre>
      <p style="margin:0 0 14px;color:#3f4f63;"><strong>기대 관찰값:</strong> 목록에 기존 폴더와 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">..\shop-hotfix</code>가 서로 다른 브랜치로 표시됩니다. 두 폴더는 Git 객체와 refs를 공유하지만 각자 HEAD, index, working tree를 가집니다.</p>
      <p style="margin:0 0 18px;color:#3f4f63;"><strong>진단 분기:</strong> “already checked out” 오류가 나면 같은 로컬 브랜치가 다른 worktree에서 사용 중인 것입니다. 보호를 무시하는 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">--force</code>를 붙이지 말고 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">git worktree list</code>로 위치를 찾거나 새 브랜치 이름을 사용합니다.</p>

      <h3 style="margin:26px 0 12px;color:#4557b4;font-size:19px;">별도 폴더에서 수정하고 push합니다</h3>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git -C ..\shop-hotfix status --short --branch
git -C ..\shop-hotfix add src/login-timeout.ps1
git -C ..\shop-hotfix commit -m "fix: bound login request timeout"
git -C ..\shop-hotfix push -u origin hotfix/login-timeout</code></pre>
      <p style="margin:0 0 18px;color:#3f4f63;">환경 파일과 의존성 디렉터리는 working tree별로 따로 준비될 수 있습니다. 반대로 저장소 설정과 refs 일부는 공유되므로 “완전히 독립된 clone”으로 오해하면 안 됩니다. 같은 브랜치를 두 폴더에서 동시에 수정하지 않는 것이 기본 안전장치입니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">6. worktree는 폴더 삭제가 아니라 Git 명령으로 정리합니다</h2>
      <p style="margin:0 0 14px;color:#3f4f63;">PR 병합과 필요한 기록 보존을 확인한 뒤, 별도 폴더가 clean일 때 정리합니다. 수정 파일이 있으면 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">remove</code>가 거부하는 것이 정상입니다.</p>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git -C ..\shop-hotfix status --short --branch
git worktree remove ..\shop-hotfix
git branch -d hotfix/login-timeout
git worktree prune --dry-run</code></pre>
      <p style="margin:0 0 18px;color:#3f4f63;"><strong>롤백 기준:</strong> status에 수정 또는 untracked 파일이 하나라도 보이거나, hotfix 브랜치가 원격·PR에 반영됐는지 확실하지 않으면 제거를 중단합니다. <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">git worktree remove --force</code>와 탐색기 수동 삭제는 기본 절차에서 제외합니다. 폴더를 수동 이동해 연결이 끊겼다면 삭제보다 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">git worktree repair</code>를 먼저 검토합니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">7. 실무 선택 규칙</h2>
      <ol style="margin:0 0 20px;padding-left:24px;color:#3f4f63;">
        <li style="margin:8px 0;">전환이 짧고 현재 폴더 하나면 충분하면 <strong>stash</strong>를 사용합니다.</li>
        <li style="margin:8px 0;">두 브랜치를 동시에 실행·비교해야 하면 <strong>worktree</strong>를 사용합니다.</li>
        <li style="margin:8px 0;">stash에는 메시지와 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">-u</code> 포함 여부를 명시하고, 적용 전후 status를 비교합니다.</li>
        <li style="margin:8px 0;">worktree는 clean 상태를 확인하고 Git 명령으로 제거합니다.</li>
        <li style="margin:8px 0;">복구 명령보다 먼저, drop·force·수동 삭제를 늦추는 것이 가장 안전합니다.</li>
      </ol>
      <p style="margin:0 0 18px;color:#3f4f63;">핵심은 “stash와 worktree 중 더 고급인 명령”을 고르는 것이 아닙니다. <strong>현재 작업을 잠깐 접을 것인지, 두 작업 공간을 동시에 유지할 것인지</strong>를 먼저 결정하고, 제거는 검증 뒤에 실행하는 것입니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">공식 출처</h2>
      <ul style="margin:0 0 24px;padding-left:24px;color:#3f4f63;">
        <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-stash" style="color:#4557b4;font-weight:700;text-decoration:underline;">Git 공식 문서: git-stash</a> — push, show, apply, pop, branch와 untracked 처리</li>
        <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-worktree" style="color:#4557b4;font-weight:700;text-decoration:underline;">Git 공식 문서: git-worktree</a> — add, list, remove, prune, repair와 worktree 구조</li>
        <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-status" style="color:#4557b4;font-weight:700;text-decoration:underline;">Git 공식 문서: git-status</a> — short 형식의 index·working tree·untracked 상태</li>
        <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-switch" style="color:#4557b4;font-weight:700;text-decoration:underline;">Git 공식 문서: git-switch</a> — 로컬 변경 손실 가능성이 있을 때 전환을 중단하는 동작</li>
        <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-clean" style="color:#4557b4;font-weight:700;text-decoration:underline;">Git 공식 문서: git-clean</a> — untracked 삭제 전 dry-run 확인</li>
      </ul>
</div>
