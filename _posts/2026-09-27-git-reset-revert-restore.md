---
title: "[Git] reset·revert·restore로 잘못된 변경 안전하게 되돌리기"
excerpt: "working tree·index·commit을 구분해 공유 전에는 기록을 고치고 공유 후에는 이력을 보존하는 Git 복구 가이드"
description: "Git restore, reset, revert의 영향 범위와 안전한 선택 기준, checkpoint와 reflog를 활용한 실무 복구 절차를 설명합니다."
categories:
  - Dev
tags:
  - [Git, reset, revert, restore, reflog]
toc: true
toc_sticky: true
date: 2026-09-27
last_modified_at: 2026-09-27
---

<div style="max-width:860px;margin:0 auto;font-family:Arial,'Malgun Gothic',sans-serif;color:#26364b;line-height:1.75;">
        <p style="margin:0 0 20px;color:#4a5b70;font-size:16px;">working tree·index·commit을 구분해, 공유 전에는 기록을 안전하게 고치고 공유 후에는 이력을 보존하며 복구하는 실무 절차입니다.</p>
        <p style="margin:0 0 18px;color:#3f4f63;">앞선 글 <a href="https://codersblog.github.io/posts/git-branch-rebase-push-merge-guide/" style="color:#4557b4;font-weight:700;text-decoration:underline;">브랜치부터 rebase와 PR 병합까지</a>는 커밋을 만들고 원격과 통합하는 흐름을 설명했습니다. 다만 잘못된 파일을 수정·stage·commit하거나 이미 push한 뒤에는 어떤 명령을 골라야 하는지까지는 다루지 않았습니다. 이번 글은 그 다음 단계로, <strong>변경이 어느 영역에 있고 다른 사람이 이미 보았는지</strong>를 기준으로 복구 명령을 선택합니다.</p>

        <div style="margin:22px 0;padding:18px 20px;border-left:5px solid #d86565;border-radius:10px;background:#fff4f4;">
          <p style="margin:0 0 8px;color:#8a3b3b;font-weight:700;">대상 환경과 실패 증상</p>
          <p style="margin:0;color:#5a4a4a;">Git 2.23 이상을 쓰는 Windows PowerShell 또는 일반 셸 환경을 가정합니다. 기능 브랜치에서 결제 설정 파일을 잘못 수정했고, 그 변경이 아직 working tree에만 있는지, stage됐는지, 로컬 commit인지, 원격에 push됐는지 불분명한 상황입니다. 이 구분 없이 <code style="padding:2px 6px;border-radius:5px;background:#ffe3e3;color:#9f3434;font-family:Consolas,monospace;">git reset --hard</code>부터 실행하면 필요한 변경까지 사라질 수 있습니다.</p>
        </div>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">1. 되돌리기 전에 상태부터 고정합니다</h2>
        <p style="margin:0 0 14px;color:#3f4f63;">복구 명령을 입력하기 전에 현재 브랜치, 수정 파일, staged 내용, 최근 commit을 한 화면에 기록합니다. 아래 확인 명령은 파일이나 이력을 바꾸지 않습니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git status --short --branch
git diff
git diff --cached
git log --oneline --decorate -8</code></pre>
        <p style="margin:0 0 14px;color:#3f4f63;"><strong>기대 관찰값:</strong> <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">git status --short</code>의 첫 번째 열은 index, 두 번째 열은 working tree 상태입니다. 예를 들어 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;"> M config/checkout.yml</code>은 아직 stage하지 않은 수정이고, <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">M  config/checkout.yml</code>은 stage된 수정입니다.</p>
        <p style="margin:0 0 18px;color:#3f4f63;"><strong>중단 기준:</strong> diff에 남겨야 할 코드와 버릴 코드가 섞여 있거나, 현재 브랜치와 push 여부가 확실하지 않으면 아직 복구 명령을 실행하지 않습니다. 필요한 변경은 별도 브랜치의 WIP commit이나 명시적인 stash로 보존한 뒤 진행합니다. 특히 commit되지 않은 변경은 reflog로 되살릴 수 있다고 가정하면 안 됩니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">2. 세 영역과 세 명령의 역할을 먼저 구분합니다</h2>
        <p style="margin:0 0 16px;color:#3f4f63;">Git의 현재 상태는 편집 중인 working tree, 다음 commit 후보인 index, 현재 브랜치가 가리키는 HEAD로 나눠 볼 수 있습니다. <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">restore</code>는 파일 또는 index를 복원하고, <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">reset</code>은 브랜치 끝과 선택한 영역을 이동시키며, <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">revert</code>는 기존 commit을 지우지 않고 반대 변경을 담은 새 commit을 만듭니다.</p>
        <figure style="margin:22px 0 28px;padding:10px;border:1px solid #e3e9f2;border-radius:14px;background:#f7f9fc;">
          <img src="/assets/img/post/git-recovery/reset-revert-restore-map.png" alt="working tree, index, HEAD 세 영역과 restore, reset soft, reset mixed, reset hard가 영향을 주는 범위, 공유된 커밋에는 revert로 새 커밋을 추가하는 원칙을 보여 주는 도식" width="1200" height="720" style="display:block;width:100%;height:auto;border-radius:10px;">
          <figcaption style="margin:10px 8px 2px;color:#66758a;font-size:13px;text-align:center;">명령 이름보다 먼저 움직이는 대상을 확인합니다. 공유 전 기록은 checkpoint 뒤 reset, 공유 후 기록은 revert가 기본입니다.</figcaption>
        </figure>

        <table style="width:100%;margin:0 0 24px;border-collapse:collapse;border:1px solid #dfe5ee;font-size:14px;">
          <thead style="background:#eef2f7;">
            <tr>
              <th style="padding:11px;border:1px solid #dfe5ee;text-align:left;color:#21324a;">상황</th>
              <th style="padding:11px;border:1px solid #dfe5ee;text-align:left;color:#21324a;">기본 선택</th>
              <th style="padding:11px;border:1px solid #dfe5ee;text-align:left;color:#21324a;">보존되는 것</th>
              <th style="padding:11px;border:1px solid #dfe5ee;text-align:left;color:#21324a;">주요 위험</th>
            </tr>
          </thead>
          <tbody>
            <tr><td style="padding:11px;border:1px solid #dfe5ee;">수정만 했음</td><td style="padding:11px;border:1px solid #dfe5ee;">restore</td><td style="padding:11px;border:1px solid #dfe5ee;">index·commit</td><td style="padding:11px;border:1px solid #dfe5ee;">버린 미commit 변경은 복구 어려움</td></tr>
            <tr style="background:#fbfcfe;"><td style="padding:11px;border:1px solid #dfe5ee;">stage만 취소</td><td style="padding:11px;border:1px solid #dfe5ee;">restore --staged</td><td style="padding:11px;border:1px solid #dfe5ee;">working tree 내용</td><td style="padding:11px;border:1px solid #dfe5ee;">이후 restore까지 연달아 실행</td></tr>
            <tr><td style="padding:11px;border:1px solid #dfe5ee;">로컬 commit 수정</td><td style="padding:11px;border:1px solid #dfe5ee;">reset --soft 또는 --mixed</td><td style="padding:11px;border:1px solid #dfe5ee;">선택에 따라 index·파일</td><td style="padding:11px;border:1px solid #dfe5ee;">공유 commit의 이력 재작성</td></tr>
            <tr style="background:#fbfcfe;"><td style="padding:11px;border:1px solid #dfe5ee;">이미 push·공유</td><td style="padding:11px;border:1px solid #dfe5ee;">revert</td><td style="padding:11px;border:1px solid #dfe5ee;">기존 commit과 감사 이력</td><td style="padding:11px;border:1px solid #dfe5ee;">충돌 또는 merge commit의 mainline 선택</td></tr>
          </tbody>
        </table>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">3. 수정만 했다면 restore로 파일을 되돌립니다</h2>
        <p style="margin:0 0 14px;color:#3f4f63;">아직 stage하지 않은 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">config/checkout.yml</code>만 현재 index 상태로 되돌리려면 파일을 명시합니다. 먼저 diff를 보고, 전체 파일이 아니라 일부 덩어리만 버릴 때는 patch 모드를 사용합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git diff -- config/checkout.yml
git restore -p -- config/checkout.yml
git status --short -- config/checkout.yml</code></pre>
        <p style="margin:0 0 14px;color:#3f4f63;"><strong>기대 관찰값:</strong> patch 모드는 변경 덩어리마다 적용 여부를 묻습니다. 버리기로 선택한 덩어리는 working tree에서 사라지고, 남긴 덩어리는 diff에 계속 보입니다. 파일 전체를 되돌릴 것이 확실하다면 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">git restore --worktree -- config/checkout.yml</code>을 사용합니다.</p>
        <p style="margin:0 0 18px;color:#3f4f63;"><strong>롤백 기준:</strong> restore 뒤 필요한 변경까지 사라졌다면 추가 정리 명령을 실행하지 말고, IDE local history나 미리 만든 WIP commit·stash를 확인합니다. Git reflog는 브랜치와 HEAD 같은 참조 이동을 기록할 뿐, commit하지 않은 파일 편집의 범용 휴지통이 아닙니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">4. 잘못 stage했다면 내용은 남기고 index만 되돌립니다</h2>
        <p style="margin:0 0 14px;color:#3f4f63;">commit 대상에 잘못 넣은 파일은 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">--staged</code>로 index에서만 뺍니다. 이 단계는 working tree의 편집 내용을 지우지 않습니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git diff --cached -- config/checkout.yml
git restore --staged -- config/checkout.yml
git status --short -- config/checkout.yml
git diff -- config/checkout.yml</code></pre>
        <p style="margin:0 0 14px;color:#3f4f63;"><strong>기대 관찰값:</strong> status 표시는 staged 열에서 working tree 열로 이동합니다. 내용은 그대로 남으므로 수정해서 다시 stage하거나, 정말 버려야 할 때만 별도의 working tree restore를 실행합니다.</p>
        <p style="margin:0 0 18px;color:#3f4f63;"><strong>진단 분기:</strong> stage를 취소했는데 diff가 비어 있다면 해당 파일이 HEAD와 같은지, 다른 경로를 보고 있지 않은지 확인합니다. 한 번에 index와 working tree를 모두 복원하는 옵션은 영향 범위가 커지므로 두 단계를 나눠 관찰하는 편이 안전합니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">5. push 전 로컬 commit은 checkpoint 뒤 reset합니다</h2>
        <p style="margin:0 0 14px;color:#3f4f63;">방금 만든 로컬 commit에 비밀 파일이나 잘못된 설정이 포함됐지만 아직 누구도 가져가지 않았다면 commit을 다시 만들 수 있습니다. 먼저 대상 commit을 확인하고 현재 위치를 가리키는 backup 브랜치를 만든 뒤 HEAD를 한 칸 옮깁니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git show --stat --oneline HEAD
git branch backup/checkout-before-reset
git reset --soft HEAD^
git status --short</code></pre>
        <p style="margin:0 0 14px;color:#3f4f63;"><strong>기대 관찰값:</strong> 최근 commit은 현재 브랜치의 이력에서 빠지지만 그 변경은 index에 staged 상태로 남습니다. 불필요한 파일만 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">git restore --staged</code>로 빼고 새 commit을 만들 수 있습니다. 문제가 생기면 backup 브랜치가 원래 commit을 계속 가리킵니다.</p>
        <p style="margin:0 0 14px;color:#3f4f63;">변경을 stage하지 않은 상태로 다시 검토하려면 mixed reset을 사용합니다. <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">--mixed</code>는 기본 모드지만, 복구 문서에서는 의도를 드러내기 위해 명시하는 편이 좋습니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git branch backup/checkout-before-mixed-reset
git reset --mixed HEAD^
git status --short
git diff</code></pre>
        <p style="margin:0 0 18px;color:#3f4f63;"><strong>hard reset 기준:</strong> <code style="padding:2px 6px;border-radius:5px;background:#ffe3e3;color:#9f3434;font-family:Consolas,monospace;">git reset --hard &lt;commit&gt;</code>은 HEAD·index·working tree를 대상 commit에 맞춥니다. 추적 파일의 미commit 변경을 덮어쓰며 일부 untracked 경로도 영향을 받을 수 있습니다. 정확한 commit SHA, 별도 checkpoint, clean 여부를 모두 확인한 자동화 복구가 아니라면 기본 선택에서 제외합니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">6. 이미 push했다면 revert로 새 복구 commit을 만듭니다</h2>
        <p style="margin:0 0 14px;color:#3f4f63;">동료가 이미 가져갔거나 Pull Request에 보인 commit은 reset으로 없애면 공유 이력이 갈라집니다. 이때는 원격 상태를 가져와 대상 SHA를 확인하고, 그 변경의 반대를 새 commit으로 기록합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git fetch origin
git status --short --branch
git log --oneline --decorate -10
git revert --no-edit &lt;bad-commit-sha&gt;
git show --stat --oneline HEAD</code></pre>
        <p style="margin:0 0 14px;color:#3f4f63;"><strong>기대 관찰값:</strong> 기존 bad commit은 이력에 남고, 가장 위에 그 효과를 반대로 적용한 새 revert commit이 생깁니다. 테스트와 diff를 확인한 뒤 현재 브랜치 정책에 따라 push하거나 PR을 갱신합니다.</p>
        <p style="margin:0 0 14px;color:#3f4f63;">충돌이 나면 Git이 자동으로 끝내지 않고 중단합니다. 최종 파일을 직접 결정해 stage한 뒤 계속하거나, 복구 방향이 잘못됐으면 revert 시작 전으로 돌아갑니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git status
# 충돌 파일을 편집한 뒤
git add config/checkout.yml
git revert --continue

# 전체 revert를 취소하려면
git revert --abort</code></pre>
        <p style="margin:0 0 18px;color:#3f4f63;"><strong>진단 분기:</strong> merge commit을 revert할 때는 어느 부모를 mainline으로 볼지 정하는 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">-m</code> 선택이 필요합니다. 부모 번호를 추측하지 말고 <code style="padding:2px 6px;border-radius:5px;background:#eef2f7;color:#384a63;font-family:Consolas,monospace;">git show --summary &lt;merge-sha&gt;</code>로 부모와 병합 의도를 확인합니다. 잘못된 mainline revert는 이후 재병합에도 영향을 줄 수 있으므로 리뷰 없이 진행하지 않습니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">7. reset으로 commit을 잃었다면 reflog에서 먼저 구조합니다</h2>
        <p style="margin:0 0 14px;color:#3f4f63;">실수로 브랜치 끝을 과거로 옮겼더라도 이전 commit 객체가 즉시 사라지는 것은 아닙니다. reflog에서 reset 직전의 HEAD를 찾고, 원래 브랜치를 다시 움직이기 전에 구조 브랜치를 만들어 고정합니다.</p>
        <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:#172033;color:#edf3ff;font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git reflog --date=local -10
git show --stat &lt;old-head-sha&gt;
git branch rescue/checkout-lost-commit &lt;old-head-sha&gt;
git log --oneline --decorate rescue/checkout-lost-commit -3</code></pre>
        <p style="margin:0 0 14px;color:#3f4f63;"><strong>기대 관찰값:</strong> 구조 브랜치가 잃어버린 commit을 가리키고, 그 commit의 파일과 메시지를 다시 검토할 수 있습니다. 필요한 변경은 cherry-pick하거나 두 브랜치 diff를 비교해 복원합니다.</p>
        <p style="margin:0 0 18px;color:#3f4f63;"><strong>한계:</strong> reflog는 해당 로컬 저장소의 참조 이동 기록이며 영구 백업이 아닙니다. 만료·정리될 수 있고, commit하지 않은 working tree 내용 자체를 자동으로 기록하지 않습니다. 확인 전에 <code style="padding:2px 6px;border-radius:5px;background:#ffe3e3;color:#9f3434;font-family:Consolas,monospace;">git gc</code>나 reflog expire 작업을 실행하지 않습니다.</p>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">8. 실제 장애 복구 순서와 종료 조건</h2>
        <ol style="margin:0 0 18px;padding-left:24px;color:#3f4f63;">
          <li style="margin:8px 0;"><strong>관찰:</strong> status, working tree diff, cached diff, log를 저장합니다.</li>
          <li style="margin:8px 0;"><strong>공유 여부 확인:</strong> 로컬 commit인지, 원격 또는 PR에 이미 보인 commit인지 확인합니다.</li>
          <li style="margin:8px 0;"><strong>checkpoint:</strong> reset 전에는 원래 HEAD를 가리키는 backup 브랜치를 만듭니다.</li>
          <li style="margin:8px 0;"><strong>최소 범위 복구:</strong> 파일이면 restore, 로컬 commit이면 soft 또는 mixed reset, 공유 commit이면 revert를 선택합니다.</li>
          <li style="margin:8px 0;"><strong>검증:</strong> diff, 테스트, 설정 검증을 실행하고 의도한 변경만 남았는지 확인합니다.</li>
          <li style="margin:8px 0;"><strong>정리:</strong> 새 commit과 push는 검증 뒤에 진행하고, backup 브랜치는 복구가 끝났음을 확인한 뒤 삭제합니다.</li>
        </ol>
        <div style="margin:22px 0;padding:18px 20px;border-left:5px solid #17877c;border-radius:10px;background:#eef9f7;">
          <p style="margin:0 0 8px;color:#14766e;font-weight:700;">완료 기준</p>
          <p style="margin:0;color:#3f5a57;">의도하지 않은 파일이 diff에 없고, 관련 테스트나 설정 검증이 통과하며, 공유된 이력을 reset이나 강제 push로 다시 쓰지 않았고, 필요할 때 돌아갈 checkpoint가 확인돼야 복구를 끝냅니다.</p>
        </div>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">핵심 정리</h2>
        <ul style="margin:0 0 20px;padding-left:24px;color:#3f4f63;">
          <li style="margin:8px 0;">파일 수정은 <strong>restore</strong>, 로컬 branch tip 수정은 <strong>reset</strong>, 공유된 commit 취소는 <strong>revert</strong>로 구분합니다.</li>
          <li style="margin:8px 0;">stage 취소와 파일 내용 폐기는 서로 다른 단계입니다. 먼저 index만 되돌리고 diff를 다시 봅니다.</li>
          <li style="margin:8px 0;">reset 전에는 backup 브랜치를 만들어 원래 commit을 가리키게 합니다.</li>
          <li style="margin:8px 0;">hard reset은 기본 복구 명령이 아니라, 대상 SHA와 checkpoint가 확인된 제한적 도구입니다.</li>
          <li style="margin:8px 0;">reflog는 잃어버린 commit 구조에 유용하지만 미commit 파일의 백업은 아닙니다.</li>
        </ul>

        <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid #e7ebf3;color:#21324a;font-size:23px;">공식 참고 자료</h2>
        <ul style="margin:0 0 26px;padding-left:24px;color:#3f4f63;">
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git#_reset_restore_and_revert" style="color:#4557b4;font-weight:700;text-decoration:underline;">Git 공식 문서: Reset, restore and revert 비교</a> — 세 명령의 책임 범위</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-restore" style="color:#4557b4;font-weight:700;text-decoration:underline;">Git 공식 문서: git-restore</a> — working tree, index, source, patch 모드</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-reset" style="color:#4557b4;font-weight:700;text-decoration:underline;">Git 공식 문서: git-reset</a> — soft, mixed, hard 모드와 ORIG_HEAD</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-revert" style="color:#4557b4;font-weight:700;text-decoration:underline;">Git 공식 문서: git-revert</a> — 새 복구 commit, 충돌 처리, merge mainline</li>
          <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-reflog" style="color:#4557b4;font-weight:700;text-decoration:underline;">Git 공식 문서: git-reflog</a> — 참조 이동 기록과 만료 동작</li>
        </ul>
</div>
