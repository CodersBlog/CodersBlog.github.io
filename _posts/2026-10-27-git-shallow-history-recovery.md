---
title: "[Git] shallow clone에서 merge-base와 태그 이력 안전하게 복원하기"
excerpt: "CI의 depth 1 체크아웃에서 끊긴 commit ancestry를 진단하고, 필요한 branch만 deepen한 뒤 태그와 전체 이력을 안전하게 복원하는 실무 가이드"
description: "Git shallow clone에서 merge-base와 git describe 실패를 진단하고, deepen, tag fetch, unshallow를 단계적으로 적용·검증하는 방법을 설명합니다."
categories:
  - Dev
tags:
  - [Git, shallow-clone, git-fetch, merge-base, CI]
toc: true
toc_sticky: true
date: 2026-10-27
last_modified_at: 2026-10-27
---
<div style="max-width:860px;margin:0 auto;font-family:Arial,'Malgun Gothic',sans-serif;color:var(--text-color);line-height:1.75;">
<p style="margin:0 0 18px;color:var(--text-color);">앞선 글 <a href="https://codersblog.github.io/posts/git-branch-rebase-push-merge-guide/" style="color:var(--link-color);font-weight:700;text-decoration:underline;">브랜치·rebase·push·PR 병합 흐름</a>은 두 branch의 공통 조상을 찾을 수 있다는 전제에서 rebase와 병합을 설명했습니다. <a href="https://codersblog.github.io/posts/git-maintenance-large-repository/" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git maintenance 글</a>도 이미 가진 commit graph를 빠르게 탐색하는 방법이지, CI가 내려받지 않은 부모 commit을 되살리는 절차는 아니었습니다. 이번 글은 이 두 전제가 깨지는 shallow clone을 진단하고, 전체 이력을 무조건 받기 전에 필요한 두 branch만 단계적으로 확장합니다.</p>
<div style="margin:22px 0;padding:18px 20px;border-left:5px solid #d86565;border-radius:10px;background:var(--card-bg);">
<p style="margin:0 0 8px;color:var(--heading-color);font-weight:700;">대상 환경과 실패 증상</p>
<p style="margin:0;color:var(--text-color);">GitHub Actions의 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">actions/checkout@v7</code> 또는 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git clone --depth=1</code>로 받은 Windows·Linux 작업 공간을 가정합니다. PR 변경 범위를 계산하는 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git merge-base origin/main HEAD</code>가 출력 없이 종료 코드 1로 끝나거나, <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git describe --tags</code>가 태그를 찾지 못해 버전·변경 로그 생성이 실패하는 상황입니다.</p>
</div>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">먼저 비슷해 보이는 세 가지 축을 분리합니다</h2>
<table style="width:100%;margin:0 0 22px;border-collapse:collapse;border:1px solid var(--main-border-color);background:var(--card-bg);font-size:14px;">
<thead style="background:var(--highlight-bg-color);"><tr style="border-bottom:1px solid var(--main-border-color);"><th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">기능</th><th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">줄이는 대상</th><th style="padding:11px 12px;text-align:left;color:var(--heading-color);">대표 증상</th></tr></thead>
<tbody style="color:var(--text-color);">
<tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">shallow clone</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">commit 부모 이력</td><td style="padding:10px 12px;">merge-base·describe·changelog 실패</td></tr>
<tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">sparse-checkout</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">working tree 경로</td><td style="padding:10px 12px;">필요한 디렉터리가 checkout되지 않음</td></tr>
<tr><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">partial clone</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">blob·tree 같은 객체</td><td style="padding:10px 12px;">파일 접근 때 지연 fetch 발생</td></tr>
</tbody></table>
<p style="margin:0 0 18px;color:var(--text-color);">파일이 모두 보여도 commit ancestry는 끊겨 있을 수 있습니다. 반대로 sparse-checkout이라고 해서 commit 이력이 얕은 것은 아닙니다. 이번 증상은 먼저 shallow 여부로 판정합니다.</p>
<figure style="margin:24px 0 30px;padding:14px;border:1px solid var(--main-border-color);border-radius:14px;background:var(--card-bg);">
<img src="/assets/img/post/git-shallow-history/git-shallow-history-recovery-flow.png" alt="depth 1에서는 feature와 main의 tip만 있어 merge-base와 이전 태그를 찾지 못하고, 두 branch를 deepen하면 공통 조상 C3를 찾지만 v1 태그는 여전히 경계 밖이며, unshallow와 tags fetch 뒤 전체 ancestry와 태그 기반 describe가 복원되는 세 단계 흐름" width="1200" height="760" style="display:block;width:100%;height:auto;border:0;border-radius:10px;">
<figcaption style="margin:10px 4px 0;color:var(--text-muted-color);font-size:13px;text-align:center;">그림 1. shallow 경계는 파일 목록이 아니라 부모 commit 탐색을 자르므로, 필요한 관찰값이 나올 때까지만 단계적으로 이동합니다.</figcaption>
</figure>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">1. 작업을 바꾸기 전에 shallow 여부와 ref를 기록합니다</h2>
<pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git --version
git rev-parse --is-shallow-repository
git status --short
git branch -avv
git rev-list --count HEAD</code></pre>
<p style="margin:0 0 18px;color:var(--text-color);"><strong>기대 관찰값:</strong> 두 번째 명령이 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">true</code>이고 depth 1이면 HEAD에서 보이는 commit 수는 대개 1입니다. status가 비지 않으면 fetch 자체가 working tree를 덮지는 않더라도, 이후 진단 결과와 로컬 변경을 섞지 않도록 별도 작업 공간에서 재현합니다.</p>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">2. 실패를 감추지 말고 종료 코드와 경계를 봅니다</h2>
<pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git merge-base origin/main HEAD
$mergeBaseExit = $LASTEXITCODE
git describe --tags HEAD
$describeExit = $LASTEXITCODE
git log --oneline --decorate --boundary -20</code></pre>
<p style="margin:0 0 18px;color:var(--text-color);"><strong>진단 분기:</strong> merge-base 출력이 비고 종료 코드가 1이면 두 ref 사이에 보이는 공통 조상이 없습니다. 실제로 unrelated history일 수도 있지만 shallow가 true라면 먼저 경계 밖 조상을 의심합니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git describe --always</code>는 태그가 없어도 SHA로 성공하므로 문제를 숨길 수 있습니다. 태그 기반 버전이 요구사항이라면 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">--always</code> 성공을 복구 증거로 쓰지 않습니다.</p>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">3. 비교 대상 ref 자체가 없으면 tip부터 명시적으로 받습니다</h2>
<pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git show-ref --verify refs/remotes/origin/main
git fetch --depth=1 --no-tags origin `
  "refs/heads/main:refs/remotes/origin/main"
git show --no-patch --oneline origin/main</code></pre>
<p style="margin:0 0 18px;color:var(--text-color);">이 단계는 origin/main의 tip을 만드는 것뿐 부모 이력을 완성하지 않습니다. ref가 생겼다는 사실과 공통 조상이 생겼다는 사실을 구분해야 합니다. fork PR처럼 head branch가 현재 origin에 없으면 임의 SHA fetch를 반복하지 말고 CI가 제공하는 정확한 head ref와 권한을 확인합니다.</p>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">4. 전체 이력보다 먼저 필요한 두 branch만 단계적으로 깊게 만듭니다</h2>
<pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">$headBranch = 'feature/report'
git fetch --deepen=50 --no-tags origin `
  "refs/heads/main:refs/remotes/origin/main" `
  "refs/heads/$headBranch:refs/remotes/origin/$headBranch"
git merge-base origin/main "origin/$headBranch"
git rev-parse --is-shallow-repository</code></pre>
<p style="margin:0 0 14px;color:var(--text-color);"><strong>기대 관찰값:</strong> 공통 조상이 최근 50 commit 안에 있다면 merge-base가 한 SHA를 출력합니다. 저장소는 여전히 shallow이므로 마지막 값은 true일 수 있습니다. 공통 조상이 없으면 50을 100처럼 관찰 가능한 단위로 늘리되, 네트워크 전송량과 job 시간을 함께 기록합니다.</p>
<p style="margin:0 0 18px;color:var(--text-color);"><strong>중단 기준:</strong> 두 번 깊이를 늘려도 merge-base가 없고 ref 선택이 맞다는 증거가 없다면 무작정 unshallow하지 않습니다. base/head ref가 뒤바뀌었는지, fork 권한이나 force-push로 예상 이력이 사라졌는지 먼저 확인합니다.</p>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">5. tags fetch와 commit 이력 복원을 같은 것으로 보지 않습니다</h2>
<pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git fetch --tags origin
git tag --list --sort=-version:refname | Select-Object -First 10
git rev-parse --is-shallow-repository
git describe --tags HEAD</code></pre>
<p style="margin:0 0 18px;color:var(--text-color);">태그 ref를 받았어도 HEAD에서 그 태그까지의 부모 경로가 shallow 경계에서 끊기면 describe는 여전히 실패할 수 있습니다. 반대로 경계 안에 가까운 태그가 있으면 성공할 수 있으므로, 성공 여부만 보지 말고 예상 태그와 거리까지 검증합니다.</p>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">6. 전체 ancestry가 요구사항일 때만 unshallow합니다</h2>
<pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">if ((git rev-parse --is-shallow-repository) -eq 'true') {
  git fetch --unshallow --tags origin
} else {
  git fetch --tags origin
}
git rev-parse --is-shallow-repository
git merge-base origin/main HEAD
git describe --tags HEAD</code></pre>
<p style="margin:0 0 18px;color:var(--text-color);"><strong>기대 관찰값:</strong> 완전한 source에서 가져왔다면 shallow 값은 false가 되고 merge-base와 예상 태그 기반 describe가 모두 성공합니다. source 자체가 shallow이면 공식 문서상 source가 가진 만큼만 받을 수 있으므로 false가 되지 않을 수 있습니다. 이때 다른 mirror나 upstream을 선택해야 합니다.</p>
<h3 style="margin:30px 0 12px;color:var(--heading-color);font-size:19px;">격리 실험 결과</h3>
<div style="margin:0 0 24px;padding:18px 20px;border-left:5px solid #17877c;border-radius:10px;background:var(--card-bg);">
<p style="margin:0;color:var(--text-color);"><strong>Git 2.54.0.windows.1:</strong> main과 feature/report가 C3에서 갈라지고 C2에 v1.0.0 태그가 있는 로컬 bare remote를 만들었습니다. 두 tip을 depth 1로 받은 worker에서 shallow=true, HEAD commit 수 1, merge-base 종료 코드 1, describe 종료 코드 128을 관찰했습니다. 두 ref에 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">--deepen=2</code>를 적용하자 C3 merge-base는 나타났지만 저장소는 shallow=true였고 태그는 여전히 도달 불가였습니다. <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">--unshallow --tags</code> 뒤 false와 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">v1.0.0-3-g&lt;sha&gt;</code>를 확인했으며 working tree는 clean이었습니다. 실제 원격 전송량과 CI 시간은 대상 저장소에서 별도 측정해야 합니다.</p>
</div>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">7. GitHub Actions에서는 목적에 맞는 fetch-depth를 선언합니다</h2>
<pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">- uses: actions/checkout@v7
  with:
    fetch-depth: 50
    fetch-tags: true</code></pre>
<p style="margin:0 0 14px;color:var(--text-color);">최근 변경 범위만 필요하고 공통 조상이 보통 50 commit 안에 있다면 먼저 이 값을 실측합니다. 태그 기반 버전은 태그 ref뿐 아니라 도달 가능한 ancestry도 필요합니다.</p>
<pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">- uses: actions/checkout@v7
  with:
    fetch-depth: 0</code></pre>
<p style="margin:0 0 18px;color:var(--text-color);">release note, 전체 tag 거리, 장기간 갈라진 branch 비교처럼 완전한 이력이 계약이라면 0을 명시합니다. 이 0은 actions/checkout 입력에서 전체 이력을 뜻하며, Git CLI의 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git clone --depth=0</code>과 같은 문법이 아닙니다.</p>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">8. 깊어진 저장소를 reset으로 다시 얕게 만들지 않습니다</h2>
<pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git status --short
git stash list
git for-each-ref --format="%(refname) %(objectname)" refs/heads refs/tags
git clone --depth=50 --no-single-branch &lt;repository-url&gt; repo-shallow-new</code></pre>
<p style="margin:0 0 18px;color:var(--text-color);"><strong>롤백 기준:</strong> deepen과 unshallow는 commit을 재작성하지 않지만 객체와 이력을 추가합니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git reset</code>은 이를 이전 depth로 되돌리지 않습니다. CI처럼 버리는 작업 공간은 job 종료로 정리하고, 장기 clone을 다시 줄여야 한다면 clean 상태·stash·로컬 전용 branch·tag를 기록한 뒤 새 폴더에 원하는 depth로 재복제합니다. 새 clone의 ref와 빌드를 검증하기 전 기존 폴더를 삭제하지 않습니다.</p>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">운영 판단표</h2>
<table style="width:100%;margin:0 0 22px;border-collapse:collapse;border:1px solid var(--main-border-color);background:var(--card-bg);font-size:14px;">
<thead style="background:var(--highlight-bg-color);"><tr style="border-bottom:1px solid var(--main-border-color);"><th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">관찰</th><th style="padding:11px 12px;border-right:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">판단</th><th style="padding:11px 12px;text-align:left;color:var(--heading-color);">조치</th></tr></thead>
<tbody style="color:var(--text-color);">
<tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">shallow=false</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">depth 원인 아님</td><td style="padding:10px 12px;">ref·태그·unrelated history 재진단</td></tr>
<tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">deepen 뒤 merge-base 발견</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">필요 이력 충족</td><td style="padding:10px 12px;">해당 depth를 CI 기준선으로 검토</td></tr>
<tr style="border-bottom:1px solid var(--main-border-color);"><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">tag ref는 있으나 describe 실패</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">ancestry 경계 남음</td><td style="padding:10px 12px;">추가 deepen 또는 unshallow</td></tr>
<tr><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">source도 shallow</td><td style="padding:10px 12px;border-right:1px solid var(--main-border-color);">완전 복원 불가</td><td style="padding:10px 12px;">완전한 upstream·mirror 선택</td></tr>
</tbody></table>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">마무리</h2>
<ul style="margin:0 0 24px;padding-left:24px;color:var(--text-color);">
<li style="margin:8px 0;">파일 목록보다 먼저 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">--is-shallow-repository</code>로 commit 경계를 확인합니다.</li>
<li style="margin:8px 0;">base와 head ref를 고정하고 필요한 두 이력만 작은 단위로 deepen합니다.</li>
<li style="margin:8px 0;">tags fetch 성공과 태그까지의 ancestry 복원을 별도로 검증합니다.</li>
<li style="margin:8px 0;">전체 이력이 작업 계약일 때만 unshallow 또는 Actions의 fetch-depth 0을 사용합니다.</li>
<li style="margin:8px 0;">깊어진 장기 clone을 줄일 때는 reset이 아니라 검증 가능한 새 shallow clone으로 교체합니다.</li>
</ul>
<h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">공식 출처</h2>
<ul style="margin:0 0 28px;padding-left:24px;color:var(--text-color);">
<li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-clone" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-clone</a> — depth, single-branch, no-single-branch와 shallow clone 범위</li>
<li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-fetch" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-fetch</a> — depth, deepen, shallow 경계, unshallow, tag fetch</li>
<li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-rev-parse" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-rev-parse</a> — --is-shallow-repository 판정</li>
<li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-merge-base" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-merge-base</a> — 두 commit의 최적 공통 조상</li>
<li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-describe" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-describe</a> — commit에서 도달 가능한 최신 태그 기반 이름</li>
<li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-rev-list" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-rev-list</a> — commit 수와 boundary 관찰</li>
<li style="margin:8px 0;"><a href="https://git-scm.com/docs/user-manual#sharing-development" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git User Manual: shallow clone</a> — merge base가 경계 밖일 때 merge 기반 작업의 한계</li>
<li style="margin:8px 0;"><a href="https://github.com/actions/checkout" style="color:var(--link-color);font-weight:700;text-decoration:underline;">GitHub 공식 저장소: actions/checkout</a> — 기본 단일 commit, fetch-depth와 fetch-tags 입력</li>
</ul>
</div>
