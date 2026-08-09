# 리서치 스윕 로그

blog-post 스킬이 글감을 찾으러 웹을 훑을 때마다 여기에 기록한다.
같은 걸 두 번 조사하지 않기 위한 로그이고, 사용자에게 보고한 내역도 남긴다.

- **검증**: 스타 수·논문 ID·저자를 `gh api` / arxiv 원문으로 직접 확인했는지
- 검증 안 된 항목은 `refs.yml` 로 승격하지 않는다
- Jekyll 빌드 제외 디렉토리 (사이트 노출 없음)

---

## 2026-08-07 — 1차 스윕 (프롬프트 / 에이전트 / 컨텍스트 엔지니어링)

### 레포

| 레포 | ★ | 검증 | 판단 |
|---|---|---|---|
| [openclaw/openclaw](https://github.com/openclaw/openclaw) | 385,447 | ✅ gh api | **글감 승격** — 2026년 최대 화제. 메신저 UI 기반 개인 AI 비서 |
| [ollama/ollama](https://github.com/ollama/ollama) | 177,991 | ✅ gh api | refs 등록 — 토픽 #18 의 1차 출처 |
| [langflow-ai/langflow](https://github.com/langflow-ai/langflow) | 152,923 | ✅ gh api | 보류 — 노코드 에이전트 빌더. 우리 톤(코드 중심)과 거리 |
| [langgenius/dify](https://github.com/langgenius/dify) | 151,695 | ✅ gh api | 보류 — 위와 동일 |
| [x1xhlol/system-prompts-and-models-of-ai-tools](https://github.com/x1xhlol/system-prompts-and-models-of-ai-tools) | 142,641 | ✅ gh api | refs 등록 — 실제 도구의 시스템 프롬프트 실물 |
| [anthropics/claude-code](https://github.com/anthropics/claude-code) | 140,571 | ✅ gh api | 토픽 #21, #22 의 1차 출처 |
| [microsoft/generative-ai-for-beginners](https://github.com/microsoft/generative-ai-for-beginners) | 116,903 | ✅ gh api | refs 등록 — 입문 시리즈 구성 참고 |
| [dair-ai/Prompt-Engineering-Guide](https://github.com/dair-ai/Prompt-Engineering-Guide) | 77,329 | ✅ gh api | refs 등록 — 프롬프트 표준 레퍼런스 |
| [anthropics/claude-cookbooks](https://github.com/anthropics/claude-cookbooks) | 51,092 | ✅ gh api | refs 등록 — **실행 가능한 검증 코드** 확보처 |
| [anthropics/prompt-eng-interactive-tutorial](https://github.com/anthropics/prompt-eng-interactive-tutorial) | 37,569 | ✅ gh api | refs 등록 |
| [humanlayer/12-factor-agents](https://github.com/humanlayer/12-factor-agents) | 25,116 | ✅ gh api | refs 등록. ⚠️ 2025-09 이후 푸시 없음 |
| [VoltAgent/awesome-ai-agent-papers](https://github.com/VoltAgent/awesome-ai-agent-papers) | 1,661 | ✅ gh api | refs 등록 — 논문 스윕 시작점 |
| [caramaschiHG/awesome-ai-agents-2026](https://github.com/caramaschiHG/awesome-ai-agents-2026) | 1,547 | ✅ gh api | 보류 — 링크 나열 위주, 깊이 부족 |
| [natnew/Awesome-Prompt-Engineering](https://github.com/natnew/Awesome-Prompt-Engineering) | 105 | ✅ gh api | 제외 — 검색 상위에 떴으나 스타 105. 검색 순위 ≠ 품질의 사례 |

### 논문

| 논문 | 날짜 | 검증 | 판단 |
|---|---|---|---|
| [TokenPilot: Cache-Efficient Context Management for LLM Agents](https://arxiv.org/abs/2606.17016) | 2026-06-15 | ✅ arxiv 원문 (Xu 외, Ningyu Zhang 그룹) | **글감 승격** — 컨텍스트 압축으로 비용 56~87% 절감 |
| [The Missing Memory Hierarchy: Demand Paging for LLM Context Windows](https://arxiv.org/abs/2603.09023) | 2026-03-09 | ✅ arxiv 원문 (Tony Mason, 단독) | 토픽 #2 의 비유 소재. 컨텍스트 최대 93% 감축 주장 |
| Zhang 외, "Agentic Context Engineering" (ACE), ICLR 2026 | ? | ❌ 미검증 | 2차 출처에서만 언급됨. arxiv ID 확인 필요 |
| "Evaluating AGENTS.md" | ? | ❌ 미검증 | 사람이 쓴 컨텍스트 파일은 +4%, 자동 생성은 -3% 주장. 원문 확인 필요 |
| ContextBench | ? | ❌ 미검증 | LLM 이 precision 보다 recall 을 선호 (과다 검색) 주장. 원문 확인 필요 |

### 개념 트렌드

- **prompt engineering → context engineering 으로 용어 이동.** 프롬프트 문장 다듬기가 아니라 컨텍스트 창에 무엇을 넣을지 설계하는 문제로 재정의됨.
- LangChain 의 4전략 프레이밍: **write / select / compress / isolate**. (원글 URL 재확인 필요)
- "추론 성능이 약 3,000 토큰부터 저하" 류의 수치가 여러 블로그에 돌아다님 — **원 논문 미확인, 인용 금지**.

### 이번 스윕에서 얻은 교훈

검색 1페이지 상위 = 품질 보장 아님. `natnew/Awesome-Prompt-Engineering`(★105)이 ★77,329 짜리 `dair-ai` 보다 위에 뜬 사례.
→ **레포는 반드시 `gh api` 로 스타·최근 푸시 확인 후 등록.**

---

## 2026-08-09 — 2차 스윕 (토큰 절약 / 프롬프트 압축)

### 레포

| 레포 | ★ | 검증 | 판단 |
|---|---|---|---|
| [microsoft/LLMLingua](https://github.com/microsoft/LLMLingua) | 6,533 | ✅ gh api | **refs 등록** — EMNLP'23·ACL'24 논문 뒷받침, 2026-04 푸시. 이 주제의 유일한 신뢰 출처 |
| [vaibkumr/prompt-optimizer](https://github.com/vaibkumr/prompt-optimizer) | 312 | ✅ gh api | 제외 — 2024-02 이후 방치 |
| [pleasedodisturb/awesome-llm-token-optimization](https://github.com/pleasedodisturb/awesome-llm-token-optimization) | 51 | ✅ gh api | 제외 — 링크 나열, 깊이 부족 |
| [base76-research-lab/token-compressor](https://github.com/base76-research-lab/token-compressor) | 9 | ✅ gh api | 제외 |
| maheshmakvana/llm-token-optimizer | **0** | ✅ gh api | 제외 — "LLM 지출 최대 60% 절감" 홍보 문구로 검색 상위 노출. 스타 0, 포크 0 |

### 논문

| 논문 | 날짜 | 검증 | 판단 |
|---|---|---|---|
| [LLMLingua](https://arxiv.org/abs/2310.05736) | 2023-10-09 | ✅ arxiv 원문 (Jiang 외, EMNLP 2023) | refs 등록 — 최대 20배 압축, 성능 손실 적음 |
| [Subword Units (BPE)](https://arxiv.org/abs/1508.07909) | 2015-08-31 | ✅ arxiv 원문 (Sennrich·Haddow·Birch, ACL 2016) | refs 등록 — 토크나이저 정본 |

### 인용 거부한 수치

블로그들이 반복하는 **"토큰 비용 최대 80% 절감", "63% 절감", "95~99% 절감"** 류는 전부 출처가 서로를 가리키는 SEO 양산글이라 인용하지 않음.
대신 **Anthropic 공식 문서에 명시된 수치만** 사용 (캐시 읽기 ≈ 입력가의 1/10, 배치 50%).

### 교훈 (1차 스윕의 강화판)

★0 / 포크 0 레포가 "60% 절감" 마케팅 문구만으로 검색 1페이지에 올라옴.
→ **절감률·성능 수치를 내세운 도구일수록 `gh api` 검증을 먼저.** 수치가 자극적일수록 출처가 없을 확률이 높다.
