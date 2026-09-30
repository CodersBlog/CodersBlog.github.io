---
title: "[Git] hooks와 .gitattributes로 팀 검사를 공유하고 CI로 강제하기"
excerpt: "로컬 Git hook, 저장소 .gitattributes, CI와 브랜치 보호의 역할을 분리해 팀 검사 정책을 안전하게 적용하는 실무 가이드"
description: "Git hooks와 .gitattributes로 EOL·diff·merge 규칙을 공유하고, 우회 가능한 로컬 검사를 CI와 required status checks로 보완하는 방법을 설명합니다."
categories:
  - Dev
tags:
  - [Git, hooks, gitattributes, CI, branch protection]
toc: true
toc_sticky: true
date: 2026-09-30
last_modified_at: 2026-09-30
---
<div style="max-width:860px;margin:0 auto;font-family:Arial,'Malgun Gothic',sans-serif;color:var(--text-color);line-height:1.75;">
        <p style="margin:0 0 18px;color:var(--text-color);">앞선 글 <a href="https://codersblog.github.io/posts/git-config-alias-customization/" style="color:var(--link-color);font-weight:700;text-decoration:underline;">.gitconfig와 alias로 설정 충돌 찾기</a>에서는 개인 설정의 출처와 범위를 추적했습니다. 그 글은 팀의 줄바꿈 계약은 커밋되는 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">.gitattributes</code>와 원격 검증에서 별도로 다뤄야 한다는 한계를 남겼습니다. 이번 글은 바로 그 다음 단계입니다. 개인 설정을 맞추는 데서 끝내지 않고, 저장소에 파일별 규칙과 빠른 로컬 검사를 함께 두되 우회 가능한 hook을 CI와 브랜치 규칙으로 보완합니다.</p>

        <div style="margin:22px 0;padding:18px 20px;border-left:5px solid #d86565;border-radius:10px;background:var(--card-bg);">
          <p style="margin:0 0 8px;color:var(--heading-color);font-weight:700;">대상 환경과 실패 증상</p>
          <p style="margin:0;color:var(--text-color);">Windows PowerShell 또는 Git Bash에서 Git 2.x를 쓰고, Windows와 Linux 개발자가 같은 저장소에 기여하는 팀을 가정합니다. 한 개발자 PC의 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">pre-commit</code>은 trailing whitespace를 막지만 새 clone에서는 hook이 실행되지 않습니다. 셸 스크립트는 CRLF로 checkout되어 CI에서 실행에 실패하고, PNG나 lock 파일 merge에서는 읽기 어려운 충돌이 생깁니다.</p>
        </div>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">1. 세 계층을 한 가지 기능처럼 취급하지 않습니다</h2>
        <p style="margin:0 0 16px;color:var(--text-color);">Git hook은 특정 clone의 개발자에게 빠른 피드백을 줍니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">.gitattributes</code>는 저장소에 커밋되어 경로별 EOL, diff, merge 동작을 공유합니다. CI와 보호 브랜치의 필수 상태 검사는 로컬 환경이나 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">--no-verify</code> 사용 여부와 무관하게 병합 직전의 최종 게이트가 됩니다.</p>

        <table style="width:100%;margin:0 0 22px;border-collapse:collapse;border:1px solid var(--main-border-color);background:var(--card-bg);font-size:14px;">
          <thead style="background:var(--highlight-bg-color);">
            <tr style="border-bottom:1px solid var(--main-border-color);">
              <th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">계층</th>
              <th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">잘하는 일</th>
              <th style="padding:11px 12px;text-align:left;color:var(--heading-color);">한계</th>
            </tr>
          </thead>
          <tbody style="color:var(--text-color);">
            <tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);font-weight:700;">로컬 hook</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">커밋 전 수초 안에 staged diff 검사</td><td style="padding:10px 12px;">clone마다 설치가 필요하고 우회 가능</td></tr>
            <tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);font-weight:700;">.gitattributes</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">경로별 EOL·텍스트·diff·merge 정책</td><td style="padding:10px 12px;">변경 시 기존 파일의 재정규화 검토 필요</td></tr>
            <tr><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);font-weight:700;">CI + 브랜치 규칙</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">모든 기여자의 동일 검사 결과를 병합 조건으로 강제</td><td style="padding:10px 12px;">결과가 늦으므로 로컬 피드백을 완전히 대체하지 않음</td></tr>
          </tbody>
        </table>

        <figure style="margin:24px 0 30px;padding:14px;border:1px solid var(--main-border-color);border-radius:14px;background:var(--card-bg);">
          <img src="/assets/img/post/git-hooks-attributes/hooks-attributes-policy-flow.png" alt="개발자 PC의 pre-commit hook에서 저장소의 .gitattributes를 거쳐 CI와 브랜치 보호로 이어지고, no-verify 우회를 CI가 다시 검사하는 구조 및 안전한 도입 순서를 보여주는 도식" width="1200" height="700" style="display:block;width:100%;height:auto;border:0;border-radius:10px;">
          <figcaption style="margin:10px 4px 0;color:var(--text-muted-color);font-size:13px;text-align:center;">그림 1. hook은 빠른 안내, attributes는 공유 규칙, CI는 우회할 수 없는 최종 게이트입니다.</figcaption>
        </figure>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">2. 정책 변경 전 깨끗한 전용 브랜치를 만듭니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">줄바꿈 정책을 바꾸면 많은 파일이 한꺼번에 stage될 수 있습니다. 기능 변경과 섞지 말고, 시작 시점에 작업 트리가 깨끗한지 확인한 다음 정책 전용 브랜치에서 진행합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git status --short
git switch -c chore/shared-git-policy
git --version
git config --show-origin --get core.autocrlf
git config --show-origin --get core.hooksPath</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>기대 관찰값:</strong> 첫 명령의 출력은 비어 있어야 합니다. 기존 변경이 한 줄이라도 보이면 stash나 별도 worktree로 분리한 뒤 시작합니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">core.hooksPath</code>가 이미 다른 경로를 가리키면 기존 도구와 충돌할 수 있으므로 덮어쓰기 전에 팀 사용 방식을 확인합니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">3. .gitattributes에는 파일별 결과만 선언합니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">아래 예시는 일반 텍스트를 자동 판별하고, hook과 셸 스크립트는 LF, 배치 파일은 CRLF로 checkout합니다. PNG는 바이너리로 취급해 텍스트 diff와 자동 merge를 끄고, lock 파일은 자동 내용 merge 대신 충돌을 드러내도록 합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">* text=auto
.githooks/** text eol=lf
*.sh text eol=lf
*.bat text eol=crlf
*.png binary
*.lock -merge</code></pre>
        <p style="margin:0 0 14px;color:var(--text-color);">규칙을 썼다는 사실보다 실제 파일에 어떤 속성이 적용되는지 확인하는 일이 중요합니다. 패턴 오타나 더 가까운 하위 디렉터리의 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">.gitattributes</code>가 결과를 바꿀 수 있습니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git check-attr text eol diff merge -- .githooks/pre-commit scripts/deploy.sh tools/build.bat assets/logo.png generated.lock
git ls-files --eol -- .githooks/pre-commit scripts/deploy.sh tools/build.bat
git diff -- .gitattributes</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>기대 관찰값:</strong> hook과 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">*.sh</code>는 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">text: set, eol: lf</code>, 배치 파일은 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">eol: crlf</code>, PNG는 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">text: unset, diff: unset, merge: unset</code>으로 보입니다. 예상과 다르면 재정규화 전에 패턴부터 고칩니다.</p>

        <h3 style="margin:26px 0 10px;color:var(--heading-color);font-size:18px;">기존 파일 재정규화는 별도 변경으로 검토합니다</h3>
        <p style="margin:0 0 14px;color:var(--text-color);"><code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">git add --renormalize .</code>는 새 규칙의 clean 처리를 모든 tracked 파일에 다시 적용하고 index를 갱신합니다. 기능 코드와 함께 실행하면 실제 수정과 EOL 정규화가 섞이므로, 전용 브랜치와 별도 commit이 롤백 경계가 됩니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git add .gitattributes
git add --renormalize .
git status --short
git diff --cached --stat
git diff --cached --check</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>진단 분기:</strong> 예상한 스크립트만 바뀌면 staged diff를 검토합니다. 수백 개 파일, 바이너리 파일, 생성물이 나타나면 commit하지 말고 중단합니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">--renormalize</code> 결과를 기능 변경과 같은 commit에 넣지 않습니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">4. 추적되는 hook과 clone별 활성화를 분리합니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">기본 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">.git/hooks</code>는 clone되지 않습니다. hook 본문은 저장소의 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">.githooks</code>에 추적하고, 각 clone에서 local <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">core.hooksPath</code>를 한 번 설정합니다. 아래 PowerShell은 UTF-8 BOM 없이 LF로 hook을 만듭니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">New-Item -ItemType Directory -Force .githooks | Out-Null
$hook = @'
#!/bin/sh
set -eu
if ! git diff --cached --check; then
  echo "commit blocked: fix staged whitespace errors" &gt;&amp;2
  exit 1
fi
'@ -replace "`r`n", "`n"
[IO.File]::WriteAllText("$PWD/.githooks/pre-commit", $hook, [Text.UTF8Encoding]::new($false))

git add .githooks/pre-commit
git update-index --chmod=+x .githooks/pre-commit
git config --local core.hooksPath .githooks</code></pre>
        <p style="margin:0 0 14px;color:var(--text-color);">활성화 결과는 추측하지 말고 Git이 계산한 경로와 config 출처를 읽습니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git config --show-origin --get core.hooksPath
git rev-parse --git-path hooks/pre-commit
git ls-files --stage -- .githooks/pre-commit
git diff --cached --check</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>기대 관찰값:</strong> 첫 출력은 현재 저장소의 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">.git/config</code>와 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">.githooks</code>를 가리키고, 두 번째 출력은 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">.githooks/pre-commit</code>입니다. stage 정보의 mode가 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">100755</code>인지도 확인합니다.</p>

        <h3 style="margin:26px 0 10px;color:var(--heading-color);font-size:18px;">실패를 의도적으로 한 번 재현합니다</h3>
        <p style="margin:0 0 14px;color:var(--text-color);">정상 경로만 확인하면 hook이 실제로 commit을 막는지 알 수 없습니다. 전용 브랜치에서 임시 파일에 trailing whitespace를 넣고 실패를 관찰합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">[IO.File]::WriteAllText("$PWD/hook-smoke.txt", "bad trailing space  `n", [Text.UTF8Encoding]::new($false))
git add hook-smoke.txt
git commit -m "test: prove hook blocks whitespace"

git restore --staged -- hook-smoke.txt
Remove-Item -LiteralPath hook-smoke.txt</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>기대 관찰값:</strong> Git의 whitespace 위치와 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">commit blocked</code> 메시지가 나온 뒤 commit이 생성되지 않습니다. 반대로 hook 파일이 없거나 실행 mode가 아니면 조용히 통과할 수 있습니다. Git 공식 문서대로 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">pre-commit</code>은 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">git commit --no-verify</code>로 우회할 수 있으므로 보안 경계로 간주하면 안 됩니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">5. 같은 검사를 CI에서 다시 실행하고 병합 조건으로 묶습니다</h2>
        <p style="margin:0 0 14px;color:var(--text-color);">CI는 hook 설치 여부와 무관하게 저장소 checkout 후 동일한 검사 명령을 실행해야 합니다. PR의 base와 head 범위에 대해 whitespace 오류, attributes 적용 결과, 프로젝트 테스트를 검사하고, 그 작업을 보호 브랜치의 필수 상태 검사로 지정합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git diff --check origin/main...HEAD
git check-attr text eol diff merge -- .githooks/pre-commit scripts/deploy.sh tools/build.bat assets/logo.png generated.lock
git ls-files --eol -- .githooks/pre-commit scripts/deploy.sh tools/build.bat
./scripts/test.sh</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>병합 기준:</strong> 로컬 hook 성공만으로는 부족합니다. CI에서 같은 검사가 성공하고, GitHub의 required status check가 해당 작업을 성공·중립·건너뜀 상태 중 하나로 확인해야 병합하도록 설정합니다. 동료가 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">--no-verify</code>를 썼더라도 원격 게이트가 다시 잡아야 합니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">6. 위험 신호와 롤백 기준을 미리 정합니다</h2>
        <ul style="margin:0 0 16px;padding-left:24px;color:var(--text-color);">
          <li style="margin:8px 0;"><strong>대량 diff:</strong> renormalize 후 예상보다 많은 파일이나 바이너리가 바뀌면 commit하지 않습니다.</li>
          <li style="margin:8px 0;"><strong>환경 차이:</strong> Windows에서는 hook이 실행되지만 Linux CI에서 shebang·실행 mode 오류가 나면 hook 배포를 중단합니다.</li>
          <li style="margin:8px 0;"><strong>merge driver 오해:</strong> <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">merge=ours</code>는 이름만 attributes에 적는다고 동작하지 않습니다. 각 clone의 config에 driver가 필요하고 상대 변경을 조용히 버릴 수 있으므로 합의 없이 도입하지 않습니다.</li>
          <li style="margin:8px 0;"><strong>우회 발견:</strong> 필수 CI가 없는데 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">--no-verify</code> commit이 들어오면 hook 범위를 늘리기보다 원격 병합 규칙부터 보완합니다.</li>
        </ul>
        <p style="margin:0 0 14px;color:var(--text-color);">이미 정책 commit을 공유했다면 이력을 다시 쓰지 말고 해당 commit을 revert합니다. 아직 commit 전이고 시작 시 작업 트리가 깨끗했다는 전제가 확인될 때만 아래처럼 원복합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git status --short
git config --local --unset core.hooksPath
git restore --staged --worktree --source=HEAD -- :/
git revert &lt;policy-commit-sha&gt;</code></pre>
        <p style="margin:0 0 18px;color:var(--text-color);"><strong>중요:</strong> 세 번째 명령은 working tree 전체를 HEAD 상태로 되돌립니다. 시작 전 깨끗했고 현재 변경이 정책 실험뿐이라는 사실을 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">git status --short</code>로 확인한 경우에만 실행합니다. 다른 변경이 보이면 중단하고 파일별로 분리합니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">7. 이 글의 실행 검증 범위</h2>
        <div style="margin:0 0 24px;padding:18px 20px;border-left:5px solid #17877c;border-radius:10px;background:var(--card-bg);">
          <p style="margin:0 0 8px;color:var(--heading-color);font-weight:700;">로컬 격리 저장소에서 확인한 결과</p>
          <p style="margin:0;color:var(--text-color);">Git 2.54.0.windows.1에서 global 설정과 사용자 저장소를 건드리지 않는 임시 저장소를 만들었습니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">core.hooksPath=.githooks</code>가 계산한 hook 경로, 경로별 text/eol/diff/merge 속성, LF·CRLF index 정규화, staged whitespace에 대한 exit code 1, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">--no-verify</code>의 로컬 우회를 실행으로 확인했습니다. GitHub 저장소의 실제 브랜치 보호 설정 변경과 CI 실행은 이 초안 단계에서 수행하지 않았습니다.</p>
        </div>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">공식 출처</h2>
        <ul style="margin:0 0 22px;padding-left:24px;color:var(--text-color);">
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/githooks" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: githooks</a> — hook 경로, 실행 조건, pre-commit의 종료 코드와 no-verify 우회</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-config#Documentation/git-config.txt-corehooksPath" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: core.hooksPath</a> — 기본 hooks 디렉터리와 상대·절대 경로 설정</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/gitattributes" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: gitattributes</a> — text, eol, diff, merge 속성과 적용 우선순위</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-check-attr" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-check-attr</a> — 경로별 실제 attributes 확인</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-add" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git add --renormalize</a> — text·EOL 정책 변경 뒤 index 재정규화</li>
          <li style="margin:8px 0;"><a href="https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches#require-status-checks-before-merging" style="color:var(--link-color);font-weight:700;text-decoration:underline;">GitHub 공식 문서: required status checks</a> — 필수 검사가 통과해야 병합되는 보호 브랜치 규칙</li>
        </ul>

      </div>
