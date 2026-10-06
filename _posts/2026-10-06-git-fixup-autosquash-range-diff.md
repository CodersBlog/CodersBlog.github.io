---
title: "[Git] fixup과 autosquash로 리뷰 수정 커밋 안전하게 정리하기"
excerpt: "PR 리뷰 수정 커밋을 원래 의도에 합치고 range-diff, 최종 트리, 테스트, 명시적 lease로 검증하는 실무 가이드"
description: "Git fixup과 autosquash로 리뷰 수정 커밋을 정리하고, range-diff와 최종 트리 비교 후 force-with-lease로 안전하게 갱신하는 방법을 설명합니다."
categories:
  - Dev
tags:
  - [Git, fixup, autosquash, rebase, range-diff, force-with-lease]
toc: true
toc_sticky: true
date: 2026-10-06
last_modified_at: 2026-10-06
---
<div style="max-width:860px;margin:0 auto;font-family:Arial,'Malgun Gothic',sans-serif;color:var(--text-color);line-height:1.75;">
<div style="margin:0 0 28px;padding:20px 22px;border-left:5px solid #5367c8;border-radius:10px;background:var(--card-bg);">
      <p style="margin:0;color:var(--text-color);">앞선 글 <a href="https://codersblog.github.io/posts/git-branch-rebase-push-merge-guide/" style="color:var(--link-color);font-weight:700;text-decoration:underline;">브랜치부터 rebase와 PR 병합까지</a>는 기능 branch를 최신 main 위에 놓고 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">force-with-lease</code>로 push하는 큰 흐름을 다뤘습니다. 다만 리뷰에서 “테스트 보완”, “이름 수정”, “예외 처리 추가” 커밋이 여러 개 쌓였을 때 어떤 원래 commit에 합치고, 정리 결과가 같은지 증명하는 과정은 남겨 두었습니다. 이번 글은 그 다음 단계입니다.</p>
    </div>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">대상 환경과 실패 증상</h2>
    <p style="margin:0 0 16px;color:var(--text-color);">Windows PowerShell 또는 일반 셸에서 Git 2.x를 사용하고, 개인이 관리하는 PR feature branch를 가정합니다. 리뷰를 반영한 뒤 로그가 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">fix typo</code>, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">address review</code>, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">test again</code>처럼 늘어나 어느 변경이 어느 의도에 속하는지 흐려졌습니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>적용 경계:</strong> 이 절차는 commit SHA를 바꾸는 history rewrite입니다. 다른 사람이 같은 branch를 기준으로 작업 중이거나, 팀 정책이 force push를 금지한다면 실행하지 않습니다. 이미 main에 병합된 commit을 정리하려고 rebase하지도 않습니다. 그 경우에는 새 수정 commit이나 revert를 사용합니다.</p>

    <table style="width:100%;margin:0 0 22px;border-collapse:collapse;border:1px solid var(--main-border-color);font-size:14px;">
      <thead><tr style="background:var(--highlight-bg-color);"><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">목적</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">생성 명령</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">autosquash 결과</th></tr></thead>
      <tbody>
        <tr><td style="padding:11px;border:1px solid var(--main-border-color);">코드만 보완</td><td style="padding:11px;border:1px solid var(--main-border-color);">commit --fixup=&lt;sha&gt;</td><td style="padding:11px;border:1px solid var(--main-border-color);">원래 메시지를 유지하고 내용 합침</td></tr>
        <tr style="background:var(--card-bg);"><td style="padding:11px;border:1px solid var(--main-border-color);">코드와 메시지 보완</td><td style="padding:11px;border:1px solid var(--main-border-color);">commit --fixup=amend:&lt;sha&gt;</td><td style="padding:11px;border:1px solid var(--main-border-color);">내용을 합치고 메시지 교체</td></tr>
        <tr><td style="padding:11px;border:1px solid var(--main-border-color);">메시지만 수정</td><td style="padding:11px;border:1px solid var(--main-border-color);">commit --fixup=reword:&lt;sha&gt;</td><td style="padding:11px;border:1px solid var(--main-border-color);">파일 변화 없이 메시지 교체</td></tr>
      </tbody>
    </table>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">1. 먼저 정리 범위와 작업 상태를 고정합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git --version
git status --short --branch
git fetch origin
git log --oneline --decorate origin/main..HEAD</code></pre>
    <p style="margin:0 0 14px;color:var(--text-color);"><strong>기대 관찰값:</strong> 현재 branch가 PR branch이고 working tree가 깨끗하며, 마지막 명령에 정리할 commit만 나옵니다. untracked 파일도 포함해 상태가 비어 있지 않으면 먼저 commit 범위를 다시 나누거나 별도 worktree에서 작업합니다. 자동 stash는 rebase 뒤 재적용 충돌을 만들 수 있으므로 이 글에서는 깨끗한 상태를 출발 조건으로 둡니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>진단 분기:</strong> <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">origin/main..HEAD</code>에 예상보다 오래된 commit이 보이면 base가 다르거나 branch가 잘못된 것입니다. 곧바로 rebase하지 말고 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">git merge-base origin/main HEAD</code>와 PR의 base branch를 먼저 확인합니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">2. 수정 내용을 원래 commit에 연결합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git log --oneline --reverse origin/main..HEAD
git add -p
git diff --cached
git commit --fixup=&lt;target-sha&gt;</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);">첫 명령에서 리뷰 수정이 속해야 할 원래 commit을 고릅니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">git add -p</code>로 관련 hunk만 stage하고, cached diff를 확인한 뒤 target SHA를 지정합니다. Git은 제목이 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">fixup! 원래 제목</code>인 commit을 만들어 autosquash가 이동할 목적지를 기록합니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);">코드가 아니라 원래 commit 메시지만 고쳐야 한다면 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">git commit --fixup=reword:&lt;target-sha&gt;</code>를 사용할 수 있습니다. 이 모드는 staged 변경을 무시하고 메시지만 교체하므로, 먼저 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">git diff --cached</code>가 비어 있는지 확인합니다.</p>

    <figure style="margin:22px 0 28px;padding:12px;border:1px solid var(--main-border-color);border-radius:12px;background:var(--card-bg);">
      <img src="/assets/img/post/git-autosquash/git-autosquash-review-flow.png" alt="기능과 테스트 커밋 뒤에 흩어진 두 fixup 커밋을 autosquash로 각각의 원래 커밋에 합치고, range-diff, 최종 트리, 테스트, 명시적 lease를 차례로 검증하는 흐름도" width="1200" height="700" style="display:block;width:100%;height:auto;border:0;border-radius:10px;">
      <figcaption style="margin:10px 8px 2px;color:var(--text-muted-color);font-size:13px;text-align:center;">autosquash가 끝났다는 사실만으로 안전하지는 않습니다. 정리 전후 패치와 최종 트리, 테스트, 원격 SHA를 각각 확인해야 합니다.</figcaption>
    </figure>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">3. 되돌아갈 이름을 만든 뒤 autosquash합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git branch backup/review-before-autosquash
git log --oneline --graph origin/main..HEAD
git rebase -i --autosquash origin/main</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);"><strong>기대 관찰값:</strong> interactive todo에서 각 fixup 줄이 대상 commit 바로 아래로 이동하고 동작이 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">fixup</code>으로 바뀝니다. 순서와 대상이 맞으면 저장해 진행합니다. 완료 뒤에는 리뷰용 수정 commit이 사라지고 의도 단위 commit만 남습니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>롤백 기준:</strong> todo에서 fixup이 엉뚱한 commit 아래로 갔거나 대상 commit이 목록에 없다면 저장하지 말고 편집기를 종료합니다. rebase 도중 conflict가 나고 해결 범위가 리뷰 수정과 관계없는 파일까지 넓어지면 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">git rebase --abort</code>로 시작점으로 돌아갑니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">4. conflict는 현재 단계의 commit 기준으로 풉니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git status
git diff --name-only --diff-filter=U
git add &lt;resolved-file&gt;
git rebase --continue</code></pre>
    <p style="margin:0 0 18px;color:var(--text-color);">autosquash는 예전 commit에 수정 patch를 다시 적용하므로, 이후 commit이 같은 줄을 바꿨다면 conflict가 날 수 있습니다. 현재 화면의 최종 코드만 복사하지 말고 rebase가 지금 재생 중인 commit의 의도를 유지해 해결합니다. 잘못 해결했음을 다음 단계에서 발견하면 backup branch가 있으므로 현재 branch를 버리지 말고 비교 근거부터 남깁니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">5. range-diff와 최종 트리를 모두 비교합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git range-diff origin/main..backup/review-before-autosquash origin/main..HEAD
git diff --exit-code backup/review-before-autosquash HEAD
git log --oneline --graph origin/main..HEAD
python -m pytest -q</code></pre>
    <p style="margin:0 0 14px;color:var(--text-color);"><strong>기대 관찰값:</strong> range-diff는 정리 전 여러 commit과 정리 후 의도 단위 commit의 대응을 보여 줍니다. 두 번째 명령은 출력 없이 종료 코드 0이어야 하며, 이는 commit SHA와 개수는 바뀌어도 최종 파일 내용은 같다는 뜻입니다. 마지막으로 실제 프로젝트 테스트가 통과해야 합니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>진단 분기:</strong> 최종 트리 diff가 남으면 conflict 해결이나 commit 이동 과정에서 코드가 달라진 것입니다. 차이가 의도한 추가 수정이 아니라면 push하지 않습니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">git switch -c investigate/autosquash-result</code>로 현재 결과를 보존한 다음 backup branch에서 다시 시작합니다. range-diff 출력은 사람이 읽는 검토용이며 자동화의 안정된 파싱 형식으로 사용하지 않습니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">6. 원격 SHA를 명시한 lease로 push합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--code-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git fetch origin
git log --oneline --left-right HEAD...origin/feature/session-timeout
git push --force-with-lease=refs/heads/feature/session-timeout:&lt;old-remote-sha&gt; origin HEAD:refs/heads/feature/session-timeout</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);">여기서 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">&lt;old-remote-sha&gt;</code>는 autosquash 전에 기록한 원격 branch의 정확한 SHA입니다. 명시적 lease는 원격이 그 SHA에서 움직였으면 push를 거부합니다. 단순 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">--force</code>는 다른 사람의 새 commit을 덮을 수 있으므로 사용하지 않습니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>롤백 기준:</strong> lease 실패는 강제로 뚫을 오류가 아니라 원격 변경이 생겼다는 신호입니다. 새 원격 commit의 작성자와 의도를 확인하고, 협업자와 정리 순서를 합의한 뒤 다시 rebase합니다. push 뒤 문제가 발견되면 backup branch를 즉시 강제 push하지 말고 PR을 중지한 후 같은 검증 절차로 복구안을 비교합니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">실행 검증 범위</h2>
    <div style="margin:0 0 24px;padding:18px 20px;border-radius:12px;background:var(--card-bg);border:1px solid var(--main-border-color);">
      <p style="margin:0;color:var(--text-color);">Git 2.54.0.windows.1의 격리된 임시 저장소에서 기능 commit 뒤에 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">git commit --fixup=&lt;sha&gt;</code>로 수정 commit을 만들고, <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--code-color);font-family:Consolas,'Courier New',monospace;">git rebase -i --autosquash main</code>을 실행했습니다. 두 commit은 하나로 합쳐졌고 backup과 새 HEAD의 최종 트리 diff는 비어 있었으며 working tree도 clean이었습니다. 이 검증은 로컬 autosquash와 range-diff 흐름만 확인했습니다. 실제 GitHub 보호 규칙, 동시 push, 프로젝트 테스트는 대상 저장소에서 별도로 검증해야 합니다.</p>
    </div>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">결론</h2>
    <p style="margin:0 0 18px;color:var(--text-color);">fixup은 작은 수정의 목적지를 기록하고 autosquash는 그 기록대로 commit을 재배치합니다. 안전성은 깔끔한 로그가 아니라 backup ref, range-diff, 동일한 최종 트리, 통과한 테스트, 예상 원격 SHA를 차례로 확인할 때 생깁니다. shared history를 함부로 다시 쓰지 않는다는 경계가 이 모든 명령보다 먼저입니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">공식 출처</h2>
    <ul style="margin:0 0 28px;padding-left:22px;color:var(--text-color);">
      <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-commit" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-commit</a> — fixup, amend, reword commit의 의미</li>
      <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-rebase" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-rebase</a> — autosquash의 이동 규칙, conflict 계속과 abort</li>
      <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-range-diff" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-range-diff</a> — 두 patch series의 commit 대응 비교</li>
      <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-push" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-push</a> — force-with-lease와 명시적 기대 SHA</li>
      <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-status" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-status</a> — branch와 working tree 상태 확인</li>
    </ul>
</div>
