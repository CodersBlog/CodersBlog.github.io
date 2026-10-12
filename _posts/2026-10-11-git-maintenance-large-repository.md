---
title: "[Git] maintenance로 대형 저장소 느려짐을 단계적으로 줄이기"
excerpt: "대형 Git 저장소를 측정한 뒤 commit-graph와 incremental-repack을 검증하고 안전하게 자동 유지보수를 적용하는 실무 가이드"
description: "Git maintenance로 대형 저장소의 commit graph와 pack 구조를 단계적으로 최적화하고, Windows 스케줄 등록과 원복 절차를 설명합니다."
categories:
  - Dev
tags:
  - [Git, maintenance, commit-graph, multi-pack-index, repository-performance]
toc: true
toc_sticky: true
date: 2026-10-11
last_modified_at: 2026-10-11
---
<div style="max-width:860px;margin:0 auto;font-family:Arial,'Malgun Gothic',sans-serif;color:var(--text-color);line-height:1.75;">
<div style="margin:22px 0;padding:18px 20px;border-left:5px solid #5367c8;border-radius:10px;background:var(--card-bg);">
        <p style="margin:0;color:var(--text-color);"><strong>대상 환경과 실패 증상:</strong> Windows PowerShell과 Git 2.54 기준입니다. 수개월 동안 fetch와 rebase를 반복한 대형 저장소에서 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git log --all</code>, merge-base 계산, fetch 후 정리가 전보다 느려지고 <code style="padding:2px 6px;border-radius:5px;background:var(--card-bg);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">.git/objects</code>가 계속 커지는 상황을 다룹니다. working tree 파일 수나 untracked 검색이 병목인 경우에는 maintenance만으로 해결되지 않습니다.</p>
      </div>

      <p style="margin:0 0 18px;color:var(--text-color);">앞선 글 <a href="https://codersblog.github.io/posts/git-config-alias-customization/" style="color:var(--link-color);font-weight:700;text-decoration:underline;">.gitconfig와 alias로 설정 충돌 찾기</a>는 설정의 출처와 범위를 확인하는 방법을 설명했습니다. 그러나 설정이 정상이어도 commit과 pack이 누적된 로컬 object database는 별도로 관리해야 합니다. 이번 글은 그 다음 단계로, 측정값과 검증 명령을 남기면서 저장소 내부 구조를 정리합니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">1. 변경 전에 기준선과 설정 출처를 기록합니다</h2>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git --version
git status --short
git count-objects -vH
git config --show-origin --get-regexp "^maintenance\.|^gc\."
Measure-Command { git log --topo-order -n 500 --all | Out-Null }</code></pre>
      <p style="margin:0 0 16px;color:var(--text-color);"><strong>기대 관찰값:</strong> count는 loose object 수, packs는 pack 파일 수, size-pack은 pack 총 크기입니다. 마지막 명령은 같은 이력 조회의 기준 시간을 남깁니다. 저장소가 clean하지 않아도 보조 인덱스 작성은 가능하지만, 장애 대응 중이라면 진행 중인 rebase·merge·bisect를 먼저 끝내거나 중단해 원인 변수를 줄입니다.</p>
      <p style="margin:0 0 18px;color:var(--text-color);"><strong>진단 분기:</strong> <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git status</code>만 느리고 log·merge-base는 빠르다면 untracked 파일, 네트워크 드라이브, 백신 실시간 검사, sparse-index 호환성을 먼저 봅니다. packs가 많아도 명령이 빠르면 숫자만 줄이기 위해 유지보수를 강제하지 않습니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">2. 자동 임계값은 성능 테스트와 구분합니다</h2>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git maintenance is-needed --auto
$LASTEXITCODE</code></pre>
      <p style="margin:0 0 18px;color:var(--text-color);">종료 코드 0은 현재 활성화된 maintenance task의 자동 실행 임계값을 넘었다는 뜻이고, 1은 지금 자동 실행이 필요하지 않다는 뜻입니다. 1은 명령 실패가 아닙니다. 또한 임계값 아래라는 사실이 사용자가 체감하는 지연까지 부정하지는 않으므로, 앞에서 측정한 명령 시간을 함께 판단합니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">3. 이력 탐색이 느리면 commit-graph부터 갱신합니다</h2>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git maintenance run --task=commit-graph
git commit-graph verify
Measure-Command { git log --topo-order -n 500 --all | Out-Null }</code></pre>
      <p style="margin:0 0 16px;color:var(--text-color);">commit-graph는 commit 객체를 다시 쓰는 기능이 아니라, 부모 관계와 generation number를 담는 보조 자료구조입니다. log, merge-base처럼 commit graph를 걷는 명령을 빠르게 만들 수 있습니다. verify가 성공하고 같은 조회가 반복 측정에서 개선되는지 확인합니다.</p>
      <p style="margin:0 0 18px;color:var(--text-color);"><strong>중단 기준:</strong> verify가 실패하거나 replace object·graft·shallow clone처럼 commit-graph 제약이 있는 저장소라면 schedule 등록으로 넘어가지 않습니다. 원본 commit과 working tree는 그대로이므로, 보조 파일을 소비하지 않도록 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git -c core.commitGraph=false log</code>로 비교할 수 있습니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">4. pack이 많다면 incremental-repack을 별도로 시험합니다</h2>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git maintenance run --task=incremental-repack
git multi-pack-index verify
git count-objects -vH</code></pre>
      <p style="margin:0 0 16px;color:var(--text-color);">이 task는 multi-pack-index를 이용해 여러 pack을 하나의 탐색 구조로 보고, 작은 pack 일부를 점진적으로 다시 묶습니다. 첫 실행은 새 pack을 만든 뒤 MIDX가 새 pack을 가리키도록 바꾸므로 packs와 size-pack이 잠시 늘 수 있습니다. 이후 실행의 expire 단계에서 더 이상 참조하지 않는 이전 pack이 삭제됩니다.</p>

      <figure style="margin:24px 0 26px;padding:10px;border:1px solid var(--main-border-color);border-radius:14px;background:var(--card-bg);">
        <img src="/assets/img/post/git-maintenance/git-maintenance-safety-flow.png" alt="대형 Git 저장소에서 count-objects로 기준선을 기록하고 commit-graph와 incremental-repack을 순서대로 검증한 뒤 schedule을 등록하는 흐름, 그리고 첫 repack에서는 pack이 늘었다가 다음 expire에서 줄어드는 두 단계 구조를 설명한 그림" width="1200" height="720" style="display:block;width:100%;height:auto;border:0;border-radius:10px;">
        <figcaption style="margin:10px 8px 2px;color:var(--text-muted-color);font-size:13px;text-align:center;">maintenance는 한 번에 모두 지우는 청소가 아니라, 측정값을 남기고 보조 구조를 단계적으로 갱신하는 절차입니다. incremental-repack은 새 pack 생성과 이전 pack 만료가 서로 다른 실행에서 관찰될 수 있습니다.</figcaption>
      </figure>

      <table style="width:100%;margin:0 0 22px;border-collapse:collapse;border:1px solid var(--main-border-color);font-size:14px;">
        <thead style="background:var(--highlight-bg-color);"><tr><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">증상</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">먼저 시험할 task</th><th style="padding:11px;border:1px solid var(--main-border-color);text-align:left;color:var(--heading-color);">검증값</th></tr></thead>
        <tbody style="color:var(--text-color);">
          <tr><td style="padding:11px;border:1px solid var(--main-border-color);">log·merge-base가 느림</td><td style="padding:11px;border:1px solid var(--main-border-color);">commit-graph</td><td style="padding:11px;border:1px solid var(--main-border-color);">verify와 동일 조회 시간</td></tr>
          <tr style="background:var(--card-bg);"><td style="padding:11px;border:1px solid var(--main-border-color);">pack 파일이 계속 늘어남</td><td style="padding:11px;border:1px solid var(--main-border-color);">incremental-repack</td><td style="padding:11px;border:1px solid var(--main-border-color);">MIDX verify와 여러 회차 추세</td></tr>
          <tr><td style="padding:11px;border:1px solid var(--main-border-color);">working tree 검색만 느림</td><td style="padding:11px;border:1px solid var(--main-border-color);">maintenance 밖 원인 조사</td><td style="padding:11px;border:1px solid var(--main-border-color);">untracked·파일시스템·백신</td></tr>
        </tbody>
      </table>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">5. 수동 검증이 끝난 저장소만 schedule에 등록합니다</h2>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git fetch --dry-run --all --prune
git maintenance register
git config --global --get-all maintenance.repo
git config --local --get maintenance.strategy
git config --local --get maintenance.auto</code></pre>
      <p style="margin:0 0 16px;color:var(--text-color);">register는 현재 저장소를 사용자 전역 maintenance 목록에 추가하고, 별도 값이 없으면 local strategy를 incremental로 둡니다. 이 전략은 commit-graph와 prefetch를 hourly, loose-objects와 incremental-repack을 daily로 예약합니다. 동시에 foreground auto maintenance를 끄기 위해 local <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">maintenance.auto=false</code>를 기록합니다.</p>
      <p style="margin:0 0 18px;color:var(--text-color);"><strong>네트워크 분기:</strong> incremental 전략의 prefetch는 모든 등록 remote에서 객체를 내려받되 일반 remote-tracking branch 대신 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">refs/prefetch/</code>에 둡니다. VPN·프록시·자격 증명이 불안정하거나 종량제 네트워크라면 fetch dry-run이 정상인지 확인하기 전에는 schedule을 시작하지 않습니다.</p>

      <h3 style="margin:26px 0 12px;color:var(--heading-color);font-size:19px;">Windows 작업 스케줄러를 시작하고 확인합니다</h3>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git maintenance start --scheduler=schtasks
schtasks /Query /FO LIST | Select-String "Git Maintenance"
git maintenance run --schedule=hourly</code></pre>
      <p style="margin:0 0 18px;color:var(--text-color);">Windows에서는 Git이 hourly·daily·weekly 작업을 Task Scheduler에 등록합니다. 공식 문서가 설명하듯 기본 작업은 로그인 중 콘솔 창이 보일 수 있습니다. 마지막 수동 hourly 실행으로 자격 증명 오류와 object database lock 충돌이 없는지 먼저 확인하고, 반복 실패하면 schedule을 확대하지 않습니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">6. unregister와 stop의 범위를 구분해 원복합니다</h2>
      <pre style="margin:0 0 14px;padding:18px 20px;overflow:auto;border-radius:12px;background:var(--highlight-bg-color);color:var(--text-color);font-size:14px;line-height:1.55;"><code style="font-family:Consolas,'Courier New',monospace;">git maintenance unregister
git config --local --unset maintenance.auto
git config --local --unset maintenance.strategy
git config --global --get-all maintenance.repo</code></pre>
      <p style="margin:0 0 16px;color:var(--text-color);">unregister는 현재 저장소만 전역 목록에서 제거하지만 local <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">maintenance.auto=false</code>와 strategy는 남깁니다. 도입 전에 값이 없었다면 위처럼 unset하고, 기존 값이 있었다면 1단계에서 기록한 값으로 복원합니다. 다른 저장소의 schedule까지 끄려는 것이 아니라면 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git maintenance stop</code>은 실행하지 않습니다.</p>
      <p style="margin:0 0 18px;color:var(--text-color);"><strong>즉시 롤백 기준:</strong> scheduled prefetch가 인증 팝업을 반복하거나, maintenance가 한 시간을 넘겨 다음 회차와 lock 충돌을 일으키거나, 디스크 여유가 배포 기준 아래로 떨어지면 현재 저장소를 unregister합니다. 전체 사용자 schedule을 중단해야 할 때만 별도로 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git maintenance stop</code>을 사용합니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">7. gc --aggressive를 첫 조치로 쓰지 않습니다</h2>
      <ul style="margin:0 0 18px;padding-left:22px;color:var(--text-color);">
        <li style="margin:8px 0;">일반 GC도 기본적으로 충분한 최적화를 제공하며, aggressive는 훨씬 오래 걸리는 대가로 더 공격적인 최적화를 시도합니다.</li>
        <li style="margin:8px 0;">background maintenance와 수동 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git gc</code>를 동시에 실행하지 않습니다. 필요한 경우 같은 lock 체계를 쓰는 <code style="padding:2px 6px;border-radius:5px;background:var(--highlight-bg-color);color:var(--text-color);font-family:Consolas,'Courier New',monospace;">git maintenance run --task=gc</code>를 유지보수 창에서 검토합니다.</li>
        <li style="margin:8px 0;">pack 수가 줄었다는 이유만으로 성공으로 판정하지 않습니다. 동일 명령의 시간, disk 사용량, verify 결과를 함께 비교합니다.</li>
      </ul>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">실행 검증 범위</h2>
      <div style="margin:0 0 22px;padding:18px 20px;border:1px solid var(--main-border-color);border-radius:12px;background:var(--card-bg);">
        <p style="margin:0;color:var(--text-color);">Git 2.54.0.windows.1의 격리된 저장소에서 72개 commit과 여러 pack을 만들었습니다. commit-graph task 뒤 graph 파일 생성과 verify 성공을 확인했고, incremental-repack 첫 실행에서는 pack이 3개에서 4개로 잠시 늘었다가 두 번째 실행의 expire 뒤 2개로 줄었습니다. MIDX verify도 통과했습니다. 별도 global config 파일로 register를 시험했을 때 strategy는 incremental, maintenance.auto는 false가 되었고, unregister 후에도 두 local 값이 남아 명시적 unset이 필요함을 확인했습니다. 이 실험은 로컬 object database 상태 전이만 검증했습니다. 실제 대형 저장소의 성능 개선 폭, 회사 VPN에서의 prefetch, Windows Task Scheduler 동작은 대상 환경에서 기준선과 함께 검증해야 합니다.</p>
      </div>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">결론</h2>
      <p style="margin:0 0 18px;color:var(--text-color);">저장소가 느리다고 바로 aggressive GC를 실행하면 원인과 효과를 분리하기 어렵습니다. 먼저 count-objects와 동일 명령 시간을 기록하고, 이력 탐색에는 commit-graph, 여러 pack 탐색에는 incremental-repack을 각각 검증합니다. 수동 task가 안정적이고 네트워크 조건까지 확인됐을 때만 register와 scheduler를 적용하면, 작업 파일과 commit 이력을 건드리지 않으면서 유지보수를 운영 절차로 만들 수 있습니다.</p>

      <h2 style="margin:34px 0 14px;padding-bottom:9px;border-bottom:2px solid var(--main-border-color);color:var(--heading-color);font-size:23px;">공식 출처</h2>
      <ul style="margin:0 0 18px;padding-left:22px;color:var(--text-color);">
        <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-maintenance" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-maintenance</a> — task, incremental 전략, register·start·stop·unregister와 Windows scheduler</li>
        <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-count-objects" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-count-objects</a> — loose object, pack 수와 크기 기준선</li>
        <li style="margin:8px 0;"><a href="https://git-scm.com/docs/commit-graph" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: commit-graph 설계</a> — graph walk 가속, generation number와 split graph</li>
        <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-multi-pack-index" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-multi-pack-index</a> — verify, repack과 expire의 단계</li>
        <li style="margin:8px 0;"><a href="https://git-scm.com/docs/git-gc" style="color:var(--link-color);font-weight:700;text-decoration:underline;">Git 공식 문서: git-gc</a> — 일반 GC와 aggressive의 비용 차이</li>
      </ul>
</div>
