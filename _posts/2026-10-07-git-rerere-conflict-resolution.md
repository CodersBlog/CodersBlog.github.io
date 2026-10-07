---
title: "[Git] rerere로 반복 충돌 해결을 안전하게 재사용하기"
excerpt: "Git rerere가 이전 충돌 해결을 working tree에 재적용하게 하고, 자동 stage 없이 diff와 테스트로 검증하는 실무 가이드"
description: "Git rerere를 저장소 로컬 범위에서 사용해 반복되는 rebase 충돌 해결을 재사용하고, autoUpdate를 끈 상태에서 검토·테스트·원복하는 방법을 설명합니다."
categories:
  - Dev
tags:
  - [Git, rerere, rebase, conflict, conflict-resolution]
toc: true
toc_sticky: true
date: 2026-10-07
last_modified_at: 2026-10-07
---
<div style="max-width:860px;margin:0 auto;font-family:Arial,'Malgun Gothic',sans-serif;color:var(--text-color);line-height:1.75;">
<div style="margin:0 0 28px;padding:20px 22px;border-left:5px solid #5367c8;border-radius:10px;background:var(--card-bg);">
      <p style="margin:0;color:var(--text-color);">앞선 글 <a href="https://codersblog.github.io/posts/git-fixup-autosquash-range-diff/" style="color:var(--link-color);font-weight:700;text-decoration:underline;">fixup과 autosquash로 리뷰 수정 커밋 정리하기</a>는 rebase 전후의 patch와 최종 트리를 검증하는 절차를 다뤘습니다. 다만 main이 계속 바뀌는 긴 PR에서는 같은 설정 파일 충돌을 rebase 때마다 다시 풀어야 합니다. 이번 글은 그 반복을 줄이되, Git이 기억한 해결안을 곧바로 정답으로 간주하지 않는 안전 경계를 추가합니다.</p>
    </div>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">대상 환경과 실패 증상</h2>
    <p style="margin:0 0 16px;color:var(--text-color);">Windows PowerShell 또는 일반 셸의 Git 2.x와, 최신 main 위로 반복 rebase하는 개인 feature branch를 가정합니다. 같은 설정 파일에서 timeout 값을 조정한 뒤 main도 그 줄을 바꿔 conflict를 한 번 해결했지만, 며칠 뒤 다시 rebase하자 거의 같은 충돌이 재발합니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>적용 경계:</strong> rerere는 충돌 해결의 정답을 이해하지 않습니다. 이전 conflict hunk와 수동 해결 결과를 저장하고 비슷한 충돌에 재적용할 뿐입니다. 제품 의미가 달라졌거나 주변 코드가 크게 바뀌었다면 자동 적용 결과가 문법적으로 깨끗해도 틀릴 수 있으므로, 테스트와 diff 검토를 생략하지 않습니다.</p>

    <table style="width:100%;margin:0 0 22px;border-collapse:collapse;border:1px solid var(--main-border-color);font-size:14px;">
      <thead><tr style="background:var(--highlight-bg-color);"><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">상황</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">working tree</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">index</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">판단</th></tr></thead>
      <tbody>
        <tr><td style="padding:11px;border:1px solid var(--main-border-color);">첫 충돌</td><td style="padding:11px;border:1px solid var(--main-border-color);">충돌 마커</td><td style="padding:11px;border:1px solid var(--main-border-color);">UU</td><td style="padding:11px;border:1px solid var(--main-border-color);">사람이 해결하고 검증</td></tr>
        <tr style="background:var(--card-bg);"><td style="padding:11px;border:1px solid var(--main-border-color);">재사용, autoUpdate=false</td><td style="padding:11px;border:1px solid var(--main-border-color);">기록된 해결안</td><td style="padding:11px;border:1px solid var(--main-border-color);">UU 유지</td><td style="padding:11px;border:1px solid var(--main-border-color);">권장: 검토 후 별도 add</td></tr>
        <tr><td style="padding:11px;border:1px solid var(--main-border-color);">재사용, autoUpdate=true</td><td style="padding:11px;border:1px solid var(--main-border-color);">기록된 해결안</td><td style="padding:11px;border:1px solid var(--main-border-color);">자동 stage</td><td style="padding:11px;border:1px solid var(--main-border-color);">오적용을 놓치기 쉬움</td></tr>
      </tbody>
    </table>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">1. 저장소 하나에서 검토 모드로 시작합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git --version
git status --short --branch
git config --local rerere.enabled true
git config --local rerere.autoUpdate false
git config --show-origin --get-regexp "^rerere\."</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);">처음부터 global 범위에 켜지 않고 현재 저장소의 local 설정으로 시험합니다. 마지막 출력에는 저장소의 config 파일 경로와 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">rerere.enabled true</code>, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">rerere.autoupdate false</code>가 보여야 합니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>중단 기준:</strong> working tree가 깨끗하지 않거나 팀의 줄바꿈 정책이 정해지지 않았다면 먼저 변경을 보존하고 attributes 상태를 확인합니다. rerere 도입과 줄바꿈 정책 변경을 한 번에 섞으면 동일한 충돌인지 판단하기 어려워집니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">2. 첫 충돌에서는 무엇을 기억할지 확인합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git fetch origin
git rebase --no-rerere-autoupdate origin/main
git status --short
git rerere status
git rerere diff
git ls-files -u -- config/service.conf</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);"><strong>기대 관찰값:</strong> rebase가 conflict로 멈추고 해당 파일은 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">UU</code>로 표시됩니다. rerere status에는 Git이 preimage를 기록할 파일이, ls-files에는 base·ours·theirs에 해당하는 index stage가 보입니다. <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">--no-rerere-autoupdate</code>는 저장소 설정이 나중에 바뀌더라도 현재 rebase에서 자동 stage를 막는 명시적 안전장치입니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>진단 분기:</strong> 충돌 파일이 rerere status에 없으면 submodule처럼 추적할 수 없는 충돌이거나, rerere를 켜기 전에 conflict가 만들어졌을 수 있습니다. 이때 자동 재사용을 기대하지 말고 일반 conflict 절차로 해결합니다.</p>

    <figure style="margin:22px 0 28px;padding:12px;border:1px solid var(--main-border-color);border-radius:12px;background:var(--card-bg);">
      <img src="/assets/img/post/git-rerere/git-rerere-safety-flow.png" alt="첫 충돌의 preimage와 사람이 검증한 postimage를 로컬 rr-cache에 저장하고, 같은 충돌이 반복되면 해결안을 working tree에만 적용해 index를 UU 상태로 남긴 뒤 diff와 테스트를 거쳐 git add하는 안전 흐름도" width="1200" height="720" style="display:block;width:100%;height:auto;border:0;border-radius:10px;">
      <figcaption style="margin:10px 8px 2px;color:var(--text-muted-color);font-size:13px;text-align:center;">rerere의 장점은 충돌 마커 편집을 줄이는 것이고, 안전성은 index를 자동 갱신하지 않은 채 diff와 테스트를 거치는 데서 나옵니다.</figcaption>
    </figure>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">3. 첫 해결은 평소보다 더 엄격하게 검증합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git diff --check
git rerere diff
python -m pytest -q
git add config/service.conf
git rebase --continue</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);">충돌 마커를 제거하고 양쪽 변경의 의도를 합친 뒤, rerere diff로 최초 conflict 상태와 현재 해결안을 비교합니다. 프로젝트 테스트가 통과한 다음에만 add와 continue를 실행합니다. 이 해결 결과가 이후 동일 충돌에 사용할 postimage가 됩니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>기대 관찰값:</strong> Git은 해결된 conflict를 기록하고 rebase를 계속합니다. 기록은 저장소의 Git 디렉터리 아래 rr-cache에 남으므로, 팀 CI 규칙이나 공유 가능한 source policy를 대신하지 않습니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">4. 반복 충돌에서는 자동 적용과 stage를 분리합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git rebase --no-rerere-autoupdate origin/main
git status --short
git rerere remaining
git diff -- config/service.conf
python -m pytest -q
git add config/service.conf
git rebase --continue</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);"><strong>기대 관찰값:</strong> 같은 conflict hunk라면 Git이 이전 해결안을 working tree에 씁니다. remaining 출력은 비어 있을 수 있지만 status는 여전히 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">UU</code>입니다. 즉 충돌 마커는 사라졌어도 해결 완료를 확정한 상태가 아닙니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>판단 기준:</strong> diff에서 바뀐 설정값의 의미를 검토하고 실제 테스트를 통과한 뒤에만 stage합니다. surrounding code나 요구사항이 달라졌다면 “Resolved using previous resolution” 메시지가 나와도 자동 해결을 거부하고 다시 풉니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">5. 잘못 기억한 해결안은 현재 충돌에서만 잊게 합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git checkout --conflict=merge -- config/service.conf
git rerere forget config/service.conf
git rerere remaining
git rerere diff
python -m pytest -q
git add config/service.conf
git rebase --continue</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);">자동 적용된 결과가 틀렸다면 먼저 conflict marker를 복원하고, 현재 conflict에 매칭된 기존 해결 기록을 forget합니다. 그 뒤 새로운 요구사항에 맞게 수동 해결하고 다시 검증하면 이번 해결안이 새 postimage로 기록됩니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>주의:</strong> forget은 현재 conflict가 재현된 동안 path 단위로 사용합니다. 전체 cache 폴더를 직접 지우거나, 틀린 자동 적용 결과를 확인 없이 add한 다음 복구하려 하지 않습니다. 이미 잘못 stage했다면 continue 전에 index와 working tree 상태부터 분리해 확인합니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">6. 중단과 원복 기준을 명확히 둡니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git rebase --abort
git status --short --branch
git config --local --unset rerere.enabled
git config --local --unset rerere.autoUpdate
git config --local --get-regexp "^rerere\."</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);">해결 범위가 예상보다 넓어지거나 테스트가 실패하면 rebase를 abort해 시작점으로 돌아갑니다. rebase abort는 현재 충돌의 rerere 진행 메타데이터도 정리합니다. 기능을 끄려면 두 local 설정을 unset하고, 마지막 명령이 아무 값도 출력하지 않는지 확인합니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>보존 경계:</strong> 설정을 끄는 것과 기존 rr-cache 기록을 삭제하는 것은 다릅니다. 오래된 기록 정리는 Git이 제공하는 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git rerere gc</code>의 만료 정책을 사용하고, 장애 대응 중에 cache 전체를 수동 삭제하지 않습니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">실행 검증 범위</h2>
    <div style="margin:0 0 24px;padding:18px 20px;border-radius:12px;background:var(--card-bg);border:1px solid var(--main-border-color);">
      <p style="margin:0;color:var(--text-color);">Git 2.54.0.windows.1의 격리된 임시 저장소에서 같은 한 줄 충돌을 두 번 만들었습니다. 첫 merge는 종료 코드 1과 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">Recorded preimage</code>를 남겼고, 수동 해결을 commit한 뒤 같은 merge를 다시 실행하자 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">Resolved using previous resolution</code>이 출력됐습니다. 해결 내용은 working tree에 복원됐지만 status는 UU, rerere remaining은 빈 값이었습니다. conflict marker를 복원한 뒤 forget을 실행하면 해당 경로가 다시 remaining에 나타났고, merge abort 뒤 branch는 clean 상태로 돌아왔습니다. 이 검증은 로컬 merge와 rerere 상태 전이만 확인했습니다. 실제 프로젝트 rebase, 도메인 테스트, CI는 대상 저장소에서 별도로 검증해야 합니다.</p>
    </div>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">결론</h2>
    <p style="margin:0 0 18px;color:var(--text-color);">rerere는 충돌 해결을 자동 결정하는 기능이 아니라, 이전에 검증한 편집 결과를 다시 제안하는 로컬 기억장치입니다. local 범위에서 켜고 autoUpdate를 끈 채, 첫 해결을 엄격히 검증하고 반복 충돌에서도 status·diff·테스트·add를 분리하면 긴 PR의 반복 작업을 줄이면서 검토 지점을 보존할 수 있습니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">공식 출처</h2>
    <ul style="margin:0 0 28px;padding-left:22px;color:var(--text-color);">
      <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-rerere" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-rerere</a> — preimage·postimage 기록, status·diff·remaining·forget·clear·gc</li>
      <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-config#Documentation/git-config.txt-rerereenabled" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-config</a> — rerere.enabled와 기본 false인 rerere.autoUpdate</li>
      <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-rebase" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-rebase</a> — rerere autoupdate 제어, continue와 abort</li>
      <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-ls-files" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-ls-files</a> — unmerged index stage 확인</li>
      <li style="margin:8px 0;"><a href="https://git-scm.com/book/en/v2/Git-Tools-Rerere" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Pro Git: Rerere</a> — 긴 topic branch와 반복 rebase에서의 사용 예</li>
    </ul>
</div>
