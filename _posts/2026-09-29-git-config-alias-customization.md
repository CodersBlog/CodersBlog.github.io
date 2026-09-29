---
title: "[Git] .gitconfig와 alias로 설정 충돌을 찾고 반복 작업 줄이기"
excerpt: "Windows 협업 저장소의 줄바꿈·실행 권한 diff를 설정 출처부터 진단하고 안전한 alias로 반복 작업을 줄이는 실무 가이드"
description: "Git 설정의 system, global, local, worktree 범위와 core.autocrlf, core.fileMode 충돌을 진단하고 안전한 alias와 원복 절차를 적용하는 방법을 설명합니다."
categories:
  - Dev
tags:
  - [Git, gitconfig, alias, autocrlf, fileMode]
toc: true
toc_sticky: true
date: 2026-09-29
last_modified_at: 2026-09-29
---
<div style="max-width:860px;margin:0 auto;font-family:Arial,'Malgun Gothic',sans-serif;color:var(--text-color);line-height:1.75;">
        <p style="margin:0 0 18px;color:var(--text-color);">앞선 글 <a href="https://codersblog.github.io/posts/git-branch-rebase-push-merge-guide/" style="color:var(--link-color);font-weight:700;text-decoration:underline;">브랜치부터 rebase와 PR 병합까지</a>와 <a href="https://codersblog.github.io/posts/git-reset-revert-restore/" style="color:var(--link-color);font-weight:700;text-decoration:underline;">reset·revert·restore 복구</a>는 명령의 흐름과 변경 복구를 다뤘습니다. 두 글에는 한 가지 가정이 있었습니다. 같은 저장소를 여는 개발자들의 Git 설정이 예측 가능하다는 점입니다. 하지만 Windows, WSL, 네트워크 드라이브를 오가면 이 가정부터 깨집니다.</p>

        <div style="margin:22px 0;padding:18px 20px;border-left:5px solid #d86565;border-radius:10px;background:var(--card-bg);">
          <p style="margin:0 0 8px;color:var(--heading-color);font-weight:700;">대상 환경과 실패 증상</p>
          <p style="margin:0;color:var(--text-color);">Windows PowerShell 또는 Git Bash에서 Git 2.x를 사용하고, 같은 저장소를 Windows·WSL·공유 드라이브에서 번갈아 엽니다. 소스 내용을 고치지 않았는데 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git status</code>에 수십 개 파일이 나타나거나, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">mode change 100644 =&gt; 100755</code>와 파일 전체 줄바꿈 diff가 보이는 상황을 해결합니다.</p>
        </div>

        <p style="margin:0 0 18px;color:var(--text-color);">핵심은 값을 바로 바꾸지 않는 것입니다. Git 설정은 system, global, local, worktree, command 범위에서 합쳐집니다. 먼저 <strong>어느 파일의 어떤 범위가 현재 값을 만들었는지</strong>를 기록한 뒤, 문제를 재현하는 가장 작은 범위만 수정해야 다른 저장소를 망가뜨리지 않습니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">1. 값보다 출처와 범위를 먼저 봅니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">단일 값 설정은 보통 system보다 global, global보다 local, local보다 worktree, worktree보다 명령 한 번의 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">-c</code>가 우선합니다. 같은 키가 여러 곳에 있어도 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git config --get</code>만 실행하면 최종값 하나만 보여 원인을 놓치기 쉽습니다.</p>

        <div style="margin:20px 0 10px;text-align:center;">
          <img src="/assets/img/post/git-config/git-config-scope-map.png" alt="system, global, local, worktree, command 다섯 Git 설정 범위가 순서대로 최종값을 덮어쓰고, 출처 기록부터 최소 범위 수정, diff 검증, unset 원복까지 이어지는 안전 절차를 보여주는 도식" width="1200" height="700" style="display:block;width:100%;height:auto;border:1px solid var(--main-border-color);border-radius:12px;">
          <p style="margin:9px 0 0;color:var(--text-muted-color);font-size:12px;">그림 1. 같은 설정 키의 최종값이 정해지는 범위와 안전한 변경 순서</p>
        </div>

        <pre style="margin:16px 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git --version
git config --list --show-origin --show-scope
git config --show-origin --show-scope --get-all core.autocrlf
git config --show-origin --show-scope --get-all core.fileMode
git config --show-origin --show-scope --get-regexp '^alias\.'</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>기대 관찰값:</strong> 각 줄 앞에 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">global</code>, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">local</code> 같은 범위와 실제 설정 파일 경로가 함께 나옵니다. 전체 목록에는 사용자·도구 환경이 드러날 수 있으므로 공개 이슈에 그대로 붙이지 말고, 문제 키만 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">--get-all</code>로 좁힙니다.</p>

        <table style="width:100%;margin:18px 0 24px;border-collapse:collapse;border:1px solid var(--main-border-color);font-size:14px;">
          <thead style="background:var(--highlight-bg-color);color:var(--heading-color);">
            <tr style="border-bottom:1px solid var(--main-border-color);">
              <th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;">범위</th>
              <th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;">영향</th>
              <th style="padding:11px 12px;text-align:left;">실무 기준</th>
            </tr>
          </thead>
          <tbody style="color:var(--text-color);">
            <tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);font-weight:700;">system</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">PC의 모든 사용자</td><td style="padding:10px 12px;">관리자가 배포한 정책. 개인이 먼저 고칠 범위가 아닙니다.</td></tr>
            <tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);font-weight:700;">global</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">현재 사용자 전체 저장소</td><td style="padding:10px 12px;">이름·이메일·개인 alias처럼 어디서나 같은 선호에 적합합니다.</td></tr>
            <tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);font-weight:700;">local</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">현재 저장소</td><td style="padding:10px 12px;">특정 저장소의 파일 시스템 차이를 격리할 때 우선합니다.</td></tr>
            <tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);font-weight:700;">worktree</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">현재 연결 작업 폴더</td><td style="padding:10px 12px;">같은 저장소의 worktree마다 정말 다른 값이 필요할 때만 씁니다.</td></tr>
            <tr><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);font-weight:700;">command</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">이번 명령 한 번</td><td style="padding:10px 12px;">영구 변경 전에 가설을 시험하는 가장 안전한 범위입니다.</td></tr>
          </tbody>
        </table>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">2. 줄바꿈 diff와 실행 권한 diff를 분리합니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">파일 전체가 바뀐 것처럼 보여도 줄바꿈 문제와 mode 문제는 진단 명령이 다릅니다. 먼저 diff 요약과 줄 수를 보고, 의심 파일 하나의 index·working tree 줄바꿈과 적용 속성을 확인합니다.</p>

        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git status --short
git diff --summary
git diff --numstat
git ls-files --eol -- scripts/deploy.sh
git check-attr -a -- scripts/deploy.sh</code></pre>
        <p style="margin:0 0 14px;color:var(--text-color);"><strong>진단 분기:</strong> <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git diff --summary</code>에 mode change만 나오면 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">core.fileMode</code> 후보입니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git ls-files --eol</code>에서 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">i/lf w/crlf</code>처럼 index와 working tree가 다르면 줄바꿈 정책을 확인합니다. 내용 수정과 mode 변경이 함께 보이면 둘을 별개 문제로 처리합니다.</p>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>중요:</strong> 팀의 줄바꿈 계약은 커밋되는 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">.gitattributes</code>가 우선입니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">core.autocrlf</code>를 무조건 global로 바꾸면 다른 저장소까지 영향을 받습니다. 속성이 없거나 팀 정책이 불명확하면 대량 renormalize를 시작하지 말고 합의부터 합니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">3. 영구 변경 전에 command 범위로 가설을 시험합니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">현재 저장소의 속성 정책이 줄바꿈을 명시하고 있고 working tree가 clean한지 확인했다면, 먼저 한 번의 명령에만 후보 값을 적용합니다. 이 명령은 설정 파일을 수정하지 않습니다.</p>

        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git -c core.autocrlf=false status --short
git -c core.fileMode=false diff --summary</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>기대 관찰값:</strong> 첫 명령에서 불필요한 줄바꿈 변경이 사라지거나, 두 번째 명령에서 mode-only diff가 사라지면 후보 설정과 증상의 연관성이 확인됩니다. 결과가 같다면 설정부터 영구 변경하지 말고 실제 파일 내용, attributes, index 상태를 계속 조사합니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">4. 영향을 현재 저장소로 제한해 수정합니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">공유 드라이브나 Windows 도구가 executable bit를 안정적으로 표현하지 못해 mode-only diff가 반복되고, 저장소가 실행 권한 변경을 working tree에서 감지할 필요가 없다고 확인했다면 local 범위로 제한합니다.</p>

        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git config --local core.fileMode false
git config --local --get core.fileMode
git diff --summary</code></pre>
        <p style="margin:0 0 14px;color:var(--text-color);"><strong>기대 관찰값:</strong> 조회값은 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">false</code>이고, 내용이 같던 파일의 mode-only diff가 사라집니다. 실제로 스크립트 실행 권한을 바꿔야 한다면 이 설정에 의존하지 말고 변경 의도를 확인한 뒤 index mode를 명시적으로 다뤄야 합니다.</p>
        <p style="margin:0 0 14px;color:var(--text-color);">줄바꿈도 팀의 attributes가 이미 경로별 정책을 명시하고 있고 command 범위 시험이 성공했을 때만 local로 좁힙니다.</p>

        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git status --short
git config --local core.autocrlf false
git config --show-origin --show-scope --get-all core.autocrlf
git status --short</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>중단 기준:</strong> 설정 직후 예상하지 않은 파일이 새로 변경되거나, checkout·add 결과가 팀 정책과 달라지면 더 진행하지 않습니다. 이 시점에는 commit도 대량 renormalize도 하지 말고 아래의 unset으로 되돌립니다.</p>

        <h3 style="margin:26px 0 10px;color:var(--heading-color);font-size:18px;">worktree마다 달라야 할 때만 별도 범위를 엽니다</h3>
        <p style="margin:0 0 14px;color:var(--text-color);">같은 저장소의 한 worktree는 Windows 도구가, 다른 worktree는 WSL 도구가 관리해 정말로 설정을 분리해야 할 수 있습니다. worktree 설정은 자동으로 켜져 있지 않으므로 저장소 확장을 먼저 활성화합니다.</p>

        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git config --local extensions.worktreeConfig true
git config --worktree core.autocrlf input
git config --show-origin --show-scope --get-all core.autocrlf</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>기대 관찰값:</strong> 마지막 줄에 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">worktree file:.git/config.worktree input</code>이 보이고 현재 worktree의 최종값은 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">input</code>입니다. 한 저장소 안에서 설정이 갈라지므로, 차이가 반드시 필요한 경우가 아니면 local 하나로 유지하는 편이 추적하기 쉽습니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">5. alias는 관찰 명령만 짧게 만듭니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">좋은 alias는 타이핑을 줄이면서도 원래 명령을 떠올릴 수 있어야 합니다. 우선 상태, 그래프, 설정 출처처럼 읽기 중심 명령부터 global에 둡니다. reset, clean, force push처럼 결과를 되돌리기 어려운 명령은 짧은 alias로 숨기지 않습니다.</p>

        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git config --global alias.st 'status --short --branch'
git config --global alias.graph 'log --graph --decorate --oneline --all -20'
git config --global alias.cfg 'config --show-origin --show-scope --get-regexp'

git st
git graph
git cfg '^core\.(autocrlf|fileMode)$'</code></pre>
        <p style="margin:0 0 14px;color:var(--text-color);"><strong>기대 관찰값:</strong> <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git st</code>는 브랜치와 짧은 상태를, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git graph</code>는 최근 20개 commit 그래프를 보여줍니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git cfg</code> 뒤의 정규식 인자는 원래 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git config</code> 명령으로 전달됩니다.</p>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>피할 패턴:</strong> 값이 느낌표로 시작하는 shell alias는 저장소 최상위에서 셸 명령을 실행할 수 있고 Windows·Linux quoting 차이도 생깁니다. 팀 문서의 핵심 절차나 파괴적 작업을 shell alias 하나에 넣지 않습니다. alias는 개인 편의 설정이며, 팀이 반드시 지켜야 할 검증은 다음 글의 hooks·CI 경계에서 다룹니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">6. unset으로 한 단계씩 원복합니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">설정 파일을 통째로 덮어쓰지 말고 이번에 추가한 키만 지웁니다. 하위 범위 값을 unset하면 바로 위 범위의 기존 값이 다시 드러납니다.</p>

        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git config --worktree --unset core.autocrlf
git config --local --unset core.autocrlf
git config --local --unset core.fileMode
git config --global --unset alias.st
git config --global --unset alias.graph
git config --global --unset alias.cfg

git config --show-origin --show-scope --get-all core.autocrlf
git config --show-origin --show-scope --get-all core.fileMode</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>기대 관찰값:</strong> 제거한 범위의 줄은 사라지고, global이나 system에 같은 키가 있다면 그 값이 다시 최종값이 됩니다. 키가 없을 때 unset이 0이 아닌 종료 코드로 끝나는 것은 파일 손상이 아니라 “그 범위에 제거할 값이 없음”이라는 진단 신호입니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">7. 적용 완료 기준을 diff로 닫습니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">설정 조회가 맞아도 working tree 결과가 틀리면 완료가 아닙니다. 다음 네 가지를 함께 통과해야 합니다.</p>

        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git config --show-origin --show-scope --get-regexp '^(core\.(autocrlf|fileMode)|alias\.)'
git status --short
git diff --summary
git diff --check</code></pre>
        <ol style="margin:0 0 18px;padding-left:24px;color:var(--text-color);">
          <li style="margin:8px 0;">최종 설정값과 그 출처가 의도한 범위에 있습니다.</li>
          <li style="margin:8px 0;">status에는 실제로 수정한 파일만 남습니다.</li>
          <li style="margin:8px 0;">예상하지 않은 mode change가 없습니다.</li>
          <li style="margin:8px 0;">diff 검사에서 새 공백 오류나 충돌 표식이 없습니다.</li>
        </ol>

        <div style="margin:22px 0;padding:18px 20px;border-left:5px solid #17877c;border-radius:10px;background:var(--card-bg);">
          <p style="margin:0 0 8px;color:var(--heading-color);font-weight:700;">로컬 실행 검증</p>
          <p style="margin:0;color:var(--text-color);">Git 2.54.0.windows.1의 격리된 임시 저장소에서 global <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--heading-color);font-family:Consolas,'Courier New',monospace;">true</code>, local <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--heading-color);font-family:Consolas,'Courier New',monospace;">false</code>, worktree <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--heading-color);font-family:Consolas,'Courier New',monospace;">input</code> 순서와 최종값 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--heading-color);font-family:Consolas,'Courier New',monospace;">input</code>을 확인했습니다. 세 alias의 실행과 인자 전달, unset 후 global 값 재노출과 alias 0개도 확인했습니다. 실제 팀 저장소의 줄바꿈 정책 자체는 프로젝트의 attributes와 CI에서 별도로 검증해야 합니다.</p>
        </div>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">핵심 정리</h2>
        <ul style="margin:0 0 20px;padding-left:24px;color:var(--text-color);">
          <li style="margin:8px 0;">설정을 바꾸기 전에 <strong>show-origin과 show-scope</strong>로 값의 출처를 기록합니다.</li>
          <li style="margin:8px 0;">가설은 <strong>git -c</strong>로 한 번 시험하고, 영구 설정은 가능한 한 local 범위에 둡니다.</li>
          <li style="margin:8px 0;">줄바꿈은 core.autocrlf 하나가 아니라 <strong>index, working tree, attributes</strong>를 함께 봅니다.</li>
          <li style="margin:8px 0;">alias는 상태·로그·설정 조회처럼 안전하고 읽기 쉬운 명령부터 만듭니다.</li>
          <li style="margin:8px 0;">원복은 설정 파일 전체 교체가 아니라 <strong>해당 범위의 키만 unset</strong>합니다.</li>
        </ul>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">공식 참고 자료</h2>
        <ul style="margin:0 0 26px;padding-left:24px;color:var(--text-color);">
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-config" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-config</a> — 설정 범위, show-origin, show-scope, worktree 설정, alias, core.autocrlf, core.fileMode</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/book/en/v2/Getting-Started-First-Time-Git-Setup" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Pro Git: First-Time Git Setup</a> — system·global·local 파일과 우선순위</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/book/en/v2/Customizing-Git-Git-Configuration" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Pro Git: Git Configuration</a> — 사용자 설정과 안전한 커스터마이징</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-ls-files" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-ls-files</a> — index·working tree의 EOL과 attributes 관찰</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/gitattributes" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: gitattributes</a> — text, eol, 줄바꿈 정규화의 팀 저장소 기준</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-diff" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-diff</a> — summary, numstat, check로 변경 검증</li>
        </ul>
</div>
