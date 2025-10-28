---
title: "Video Summury vs Video Synopsis"
excerpt: "Video Summury vs Video Synopsis by sehoon-lee"

categories:
    - Video Synopsis
tags:
    - [Video Synopsis]

toc: true
toc_sticky: true

date: 2025-10-28
last_modified_at: 2025-10-28

math: true

---

<br>

최근 지능형 CCTV 관련 업무를 보고 있는데, 요구사항 들 중 특정 시간 동안 등장한 객체, 이벤트를 짧은 시간에 한번에 봐 관측 피로도를 감소하고싶어 하는 경우가 있다.

관련 개발을 진행하려고 서치를 하는데 두 가지 다른 방향이 있다는 것을 알게되어 공유하고자 한다.

<br>

### Video Summary

- Video Summary의 경우 영상의 시간 순서를 지키며, 중요한 객체 및 이벤트 등장시의 클립들만 조합하여 짧은 시간의 하이라이트 영상을 만드는 태스크를 의미한다.

<br>

**빠르게 영상의 전체 내용을 이해하는데 도움이 됨. 예시로는 스포츠 하이라이트가 있다.**

<br>

### Video Synopsis

- Video Synopsis의 경우 영상의 길이를 최대한 압축하여, 시간내에 등장한 객체들의 시공간 배치를 재배열하여 짧은 시간동안 모든 객체를 동시에 관측할 수 있도록 하는 태스크를 의미 한다.

<br>

**여러 객체의 움직임을 동시에 관찰하는데 도움을 줌**

<br>

![img_file](/assets/img/post/video_synopsis_1/Video_Synopsis_before-after.jpg)

### 실제 요구사항

- CCTV 업계에서는 영상의 하이라이트 보다는 관측하는 시간을 줄여 관측 실수를 줄이고, 짧은 시간 동안 집중해서 객체의 움직임을 분석하여 관측의 효율을 높이고자 한다.
- 그러한 의미에서 현재 업계에서 요구하는 태스크는 Video Synopsis 이며, 구현 및 실험을 하며 알게된 것과 기존 논문을 분석해서 앞으로 공유하고자 한다.

**Video Synopsis 의 산출물은 합성영상으로 객체가 일부 공간에 겹치게 등장하기도 하기때문에 각 객체 또는 배경 등에 투명도를 부여하게 된다.**


### 정리
- 원본 영상 길이를 줄여 빠르게 영상을 분석하는 태스크에는 Video Summary 와 Video Synopsis가 있다.
- 현재 CCTV 업계에서 요구하는 영상 요약은 Video Synopsis 태스크이다.
- Video Synopsis는 합성 영상으로 서로 다른 시간 및 공간에 존재하는 객체들이 동시에 등장하여, 공간을 겹치게 차지하는 경우도 있다.