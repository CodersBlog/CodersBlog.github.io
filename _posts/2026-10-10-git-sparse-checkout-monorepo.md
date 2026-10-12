---
title: "[Git] sparse-checkout으로 대형 monorepo 작업 범위 안전하게 줄이기"
excerpt: "Git sparse-checkout으로 필요한 디렉터리만 펼치고, sparse index 호환 문제와 전체 checkout 복원을 안전하게 다루는 실무 가이드"
description: "Git sparse-checkout과 sparse index로 대형 monorepo의 working tree 범위를 줄이고, partial clone과의 차이 및 안전한 복구 절차를 설명합니다."
categories:
  - Dev
tags:
  - [Git, sparse-checkout, sparse-index, monorepo, partial-clone]
toc: true
toc_sticky: true
date: 2026-10-10
last_modified_at: 2026-10-10
---
<div style="max-width:860px;margin:0 auto;font-family:Arial,'Malgun Gothic',sans-serif;color:var(--text-color);line-height:1.75;">
<div style="margin:0 0 28px;padding:20px 22px;border-left:5px solid #5367c8;border-radius:10px;background:var(--card-bg);">
      <p style="margin:0;color:var(--text-color);">앞선 글 <a href="https://codersblog.github.io/posts/git-stash-worktree/" style="color:var(--link-color);font-weight:700;text-decoration:underline;">stash와 worktree로 긴급 작업 전환하기</a>는 별도 working tree로 핫픽스를 분리하는 방법을 다뤘습니다. 하지만 수십만 파일의 monorepo에서는 working tree 하나만 추가해도 Windows 실시간 검사와 IDE 인덱싱이 길어질 수 있습니다. 이번 글은 커밋 이력을 그대로 둔 채 지금 필요한 디렉터리만 펼치고, 도구 호환 문제가 생기면 index 최적화만 끄거나 전체 checkout으로 돌아가는 다음 단계를 설명합니다.</p>
    </div>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">대상 환경과 실패 증상</h2>
    <p style="margin:0 0 16px;color:var(--text-color);">Windows PowerShell과 Git 2.x를 사용하고, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">services/vision-api</code>만 수정하지만 저장소에는 여러 서비스·문서·도구가 함께 있다고 가정합니다. clone은 끝났는데 checkout 직후 파일 수가 너무 많아 백신과 IDE가 오래 스캔하고, 새 worktree를 만들 때마다 같은 지연이 반복됩니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>핵심 경계:</strong> sparse-checkout은 추적 파일을 Git 기록에서 삭제하지 않습니다. 기존 clone에서는 working tree에 보이는 범위만 줄이며, 이미 받은 object database의 용량은 그대로입니다. 네트워크 전송량까지 줄이려면 새 clone에서 partial clone 옵션을 별도로 사용해야 합니다.</p>

    <table style="width:100%;margin:0 0 22px;border-collapse:collapse;border:1px solid var(--main-border-color);font-size:14px;">
      <thead><tr style="background:var(--highlight-bg-color);"><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">기능</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">줄이는 것</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">줄이지 않는 것</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">주의점</th></tr></thead>
      <tbody>
        <tr><td style="padding:11px;border:1px solid var(--main-border-color);">sparse-checkout</td><td style="padding:11px;border:1px solid var(--main-border-color);">working tree 파일 수</td><td style="padding:11px;border:1px solid var(--main-border-color);">기존 object database</td><td style="padding:11px;border:1px solid var(--main-border-color);">제외할 디렉터리의 ignored 파일 확인</td></tr>
        <tr style="background:var(--card-bg);"><td style="padding:11px;border:1px solid var(--main-border-color);">sparse index</td><td style="padding:11px;border:1px solid var(--main-border-color);">index 항목과 일부 명령 비용</td><td style="padding:11px;border:1px solid var(--main-border-color);">커밋·추적 경로</td><td style="padding:11px;border:1px solid var(--main-border-color);">외부 도구·구버전 Git 호환성</td></tr>
        <tr><td style="padding:11px;border:1px solid var(--main-border-color);">partial clone</td><td style="padding:11px;border:1px solid var(--main-border-color);">초기 blob 다운로드</td><td style="padding:11px;border:1px solid var(--main-border-color);">필요해진 blob의 지연 다운로드</td><td style="padding:11px;border:1px solid var(--main-border-color);">서버 지원과 이후 네트워크 필요</td></tr>
      </tbody>
    </table>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">1. 줄이기 전에 숨겨질 로컬 파일부터 찾습니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git --version
git status --short --branch
git ls-tree -d --name-only HEAD
git clean -nd
git clean -ndX</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);">첫 세 줄은 현재 상태와 선택 가능한 최상위 디렉터리를 확인합니다. 뒤의 두 명령은 실제 삭제 없이 각각 untracked 파일과 ignored 파일의 삭제 후보를 미리 보여 줍니다. 빌드 결과나 로컬 데이터가 제외할 디렉터리에 있고 다시 만들 수 없다면 저장소 밖으로 백업한 뒤 진행합니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>중단 기준:</strong> status에 의도하지 않은 변경이 있거나 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git clean -ndX</code>가 보존해야 할 ignored 파일을 보여 주면 아직 sparse-checkout을 적용하지 않습니다. 특히 cone을 바꿀 때 선택 밖의 tracked 디렉터리에 ignored 파일만 남아 있으면 Git이 그 디렉터리를 정리할 수 있습니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">2. 기본 cone mode에서 필요한 디렉터리만 선택합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git sparse-checkout set --cone --sparse-index `
  services/vision-api libs/schema
git sparse-checkout list
git config --show-origin --get-regexp `
  "^(core\.sparseCheckout|index\.sparse|extensions\.worktreeConfig)"
git status --short</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);"><strong>기대 관찰값:</strong> list에는 두 디렉터리가 나오고 working tree에는 그 하위 파일, 저장소 최상위 파일, 선택 경로의 상위 디렉터리에 바로 놓인 파일만 남습니다. 다른 서비스가 화면에서 사라져도 커밋에서 삭제된 것이 아니므로 status에는 대량 삭제가 나타나지 않아야 합니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);">cone mode는 디렉터리 단위 선택에 맞춘 기본 모드입니다. 임의 glob이 필요한 non-cone mode는 패턴 비용과 명령 호환 문제가 커지므로 첫 도입에서는 사용하지 않습니다. sparse index는 선택 밖 디렉터리를 축약된 index 항목으로 표현해 status와 add 비용을 줄일 수 있지만, 외부 도구가 이 표현을 이해하지 못할 수 있습니다.</p>

    <figure style="margin:22px 0 28px;padding:12px;border:1px solid var(--main-border-color);border-radius:12px;background:#f7f9fc;">
      <img src="/assets/img/post/git-sparse-checkout/git-sparse-checkout-safety-flow.png" alt="기존 Git object database는 유지하고 sparse index를 거쳐 vision-api와 schema 디렉터리만 working tree에 펼치는 구조, set add reapply 명령의 차이, 적용 전 로컬 파일 검사와 no-sparse-index 및 disable 복구 경로를 보여 주는 도식" width="1200" height="720" style="display:block;width:100%;height:auto;border:0;border-radius:10px;">
      <figcaption style="margin:10px 8px 2px;color:var(--text-muted-color);font-size:13px;text-align:center;">sparse-checkout은 기록을 지우는 기능이 아니라 working tree의 관심 범위를 줄이는 기능입니다. 안전성은 적용 전 로컬 파일 확인과 index 최적화·전체 checkout을 각각 되돌릴 수 있는 데서 나옵니다.</figcaption>
    </figure>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">3. set은 교체, add는 확장으로 구분합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git sparse-checkout add tools/dev
git sparse-checkout list

&#35; 임시 도구 작업이 끝나면 전체 선택을 다시 명시해 교체
git sparse-checkout set services/vision-api libs/schema
git sparse-checkout list</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);"><code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">add</code>는 기존 선택을 유지한 채 디렉터리를 더하고, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">set</code>은 목록 전체를 새 값으로 바꿉니다. set에 한 경로를 빼먹으면 그 경로가 working tree에서 사라지므로 팀 공용 명령에는 항상 전체 선택 목록을 명시합니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>검증:</strong> list 결과를 확인하고 프로젝트 테스트를 실행합니다. import·빌드·코드 생성 단계가 선택 밖 디렉터리를 암묵적으로 참조한다면 필요한 디렉터리를 add하거나 sparse 적용 범위를 재설계합니다. 파일이 안 보인다는 이유로 같은 파일을 새로 만들면 추적 파일과 충돌할 수 있습니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">4. merge·rebase 뒤에는 conflict와 materialized path를 먼저 정리합니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git fetch origin
git rebase origin/main
git status --short
git diff --check

&#35; conflict 해결·테스트·commit/rebase 완료 뒤 실행
git sparse-checkout reapply</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);">merge나 rebase는 충돌 해결을 위해 선택 밖 경로를 일시적으로 working tree에 꺼낼 수 있습니다. 충돌 중이거나 unstaged 변경이 남아 있으면 reapply가 그 파일을 정리하지 못할 수 있으므로, 먼저 status와 diff를 확인하고 진행 중인 작업을 완료하거나 abort합니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>진단 분기:</strong> reapply 뒤에도 선택 밖 디렉터리가 남으면 그 안의 untracked·ignored 파일과 충돌 상태를 다시 확인합니다. 해결되지 않은 파일을 없애기 위해 reset이나 clean을 바로 실행하지 말고, 필요한 데이터인지부터 판단합니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">5. 도구 호환 문제는 sparse index만 먼저 끕니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git sparse-checkout reapply --no-sparse-index
git config --get index.sparse
git status --short
python -m pytest -q services/vision-api</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);">IDE 플러그인이나 구버전 도구가 sparse directory index entry를 이해하지 못하면 working tree 선택은 유지하고 index만 일반 형태로 되돌립니다. config 출력은 false가 되어야 하며, status와 테스트가 정상이라면 checkout 전체를 복원할 필요가 없습니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>실측 경계:</strong> 격리한 Git 2.53.0.windows.3 저장소에서 8개 추적 파일 중 4개만 working tree에 보이게 한 뒤에도 커밋의 8개 경로는 유지됐습니다. add는 도구 디렉터리를 확장했고, set은 다시 제외했으며, <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">reapply --no-sparse-index</code> 후 index.sparse=false, disable 후 8개 파일 복원과 clean status를 확인했습니다. 실제 대형 저장소의 시간·디스크 절감률은 이 환경에서 측정하지 않았습니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">6. 새 clone이라면 blob 다운로드도 분리해서 줄입니다</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git clone --filter=blob:none --sparse `
  https://github.com/ORG/REPO.git repo-vision
Set-Location repo-vision
git sparse-checkout set --cone --sparse-index `
  services/vision-api libs/schema
git count-objects -vH</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);">blobless partial clone은 처음에 파일 내용 blob을 생략하고 실제 필요한 시점에 내려받습니다. 원격 서버가 filter를 지원해야 하며, 선택 범위를 넓히거나 과거 파일 내용을 열 때 네트워크 요청이 발생할 수 있습니다. 기존 clone에 sparse-checkout만 켠 경우와 효과가 다릅니다.</p>
    <p style="margin:0 0 18px;color:var(--text-color);"><strong>진단 분기:</strong> clone 로그에 filter 미지원 경고가 나오면 working tree는 sparse여도 object 다운로드는 기대만큼 줄지 않을 수 있습니다. 오프라인 개발이 필수라면 필요한 경로와 이력을 미리 열어 blob을 받아 두거나 일반 clone을 사용합니다.</p>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">7. 전체 checkout 복원과 롤백 기준</h2>
    <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git status --short
git sparse-checkout disable
git status --short
git ls-tree -r --name-only HEAD | Measure-Object -Line</code></pre>
    <p style="margin:0 0 16px;color:var(--text-color);">disable은 sparse-checkout 설정을 끄고 모든 추적 파일을 working tree에 다시 채웁니다. 일반 clone에서는 로컬 object를 사용하지만 blobless partial clone은 누락된 blob을 받기 위해 네트워크가 필요할 수 있으므로 연결과 디스크 여유를 먼저 확인합니다.</p>

    <h3 style="margin:26px 0 12px;color:var(--heading-color);font-size:19px;">운영 적용 체크리스트</h3>
    <ul style="margin:0 0 20px;padding-left:24px;color:var(--text-color);">
      <li style="margin:0 0 8px;">적용 전 status, untracked, ignored 파일을 확인하고 재생성 불가능한 결과는 백업합니다.</li>
      <li style="margin:0 0 8px;">첫 적용은 기본 cone mode와 저장소별 선택으로 시작하고, list와 실제 빌드를 함께 확인합니다.</li>
      <li style="margin:0 0 8px;">도구 오류가 생기면 전체 기능을 버리기 전에 sparse index만 끄고 재검증합니다.</li>
      <li style="margin:0 0 8px;">선택 밖 경로를 자주 add해야 하거나 빌드가 저장소 전체를 요구하면 sparse 범위가 너무 좁다는 신호입니다.</li>
      <li style="margin:0;">partial clone을 disable하기 전에는 누락 blob 다운로드를 위한 네트워크와 디스크를 확보합니다.</li>
    </ul>

    <table style="width:100%;margin:0 0 22px;border-collapse:collapse;border:1px solid var(--main-border-color);font-size:14px;">
      <thead><tr style="background:var(--highlight-bg-color);"><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">관찰</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">판단</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">복구</th></tr></thead>
      <tbody>
        <tr><td style="padding:11px;border:1px solid var(--main-border-color);">IDE만 index 오류</td><td style="padding:11px;border:1px solid var(--main-border-color);">sparse index 호환 문제</td><td style="padding:11px;border:1px solid var(--main-border-color);">reapply --no-sparse-index</td></tr>
        <tr style="background:var(--card-bg);"><td style="padding:11px;border:1px solid var(--main-border-color);">빌드가 선택 밖 경로 요구</td><td style="padding:11px;border:1px solid var(--main-border-color);">cone이 너무 좁음</td><td style="padding:11px;border:1px solid var(--main-border-color);">sparse-checkout add</td></tr>
        <tr><td style="padding:11px;border:1px solid var(--main-border-color);">팀 도구 전반이 비호환</td><td style="padding:11px;border:1px solid var(--main-border-color);">운영 이득보다 복잡도 큼</td><td style="padding:11px;border:1px solid var(--main-border-color);">sparse-checkout disable</td></tr>
      </tbody>
    </table>

    <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">공식 출처</h2>
    <ul style="margin:0 0 24px;padding-left:24px;color:var(--text-color);">
      <li style="margin:0 0 8px;"><a href="https://git-scm.com/docs/git-sparse-checkout" style="color:var(--link-color);text-decoration:underline;">Git sparse-checkout 문서</a> — set, add, reapply, disable, cone mode와 ignored 파일 주의사항</li>
      <li style="margin:0 0 8px;"><a href="https://git-scm.com/docs/sparse-index" style="color:var(--link-color);text-decoration:underline;">Git sparse-index 문서</a> — index 축약의 목적과 명령 호환 범위</li>
      <li style="margin:0 0 8px;"><a href="https://git-scm.com/docs/git-clone" style="color:var(--link-color);text-decoration:underline;">Git clone 문서</a> — --sparse와 --filter=blob:none의 차이</li>
      <li style="margin:0 0 8px;"><a href="https://git-scm.com/docs/git-clean" style="color:var(--link-color);text-decoration:underline;">Git clean 문서</a> — -n dry-run, untracked·ignored 파일 점검</li>
      <li style="margin:0;"><a href="https://git-scm.com/docs/git-worktree" style="color:var(--link-color);text-decoration:underline;">Git worktree 문서</a> — working tree별 설정과 병렬 checkout</li>
    </ul>
</div>
