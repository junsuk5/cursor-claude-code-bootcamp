# [Hands-on 2] MCP와 스킬로 AI에게 일 시키기 (Day 2 후반부)

> **"이제 코드를 짜는 게 아니라, 코드를 짜는 AI를 운영합니다."**
> 전반부에서 만든 대시보드 위에 상품 등록 기능을 **TDD로** 붙이고,
> **Playwright MCP로 AI가 직접 브라우저를 조작해 검증**하게 한 뒤,
> 반복 작업을 **나만의 스킬**로 굳힙니다.

> **선행**: [Hands-on 1 — 관리자 대시보드 만들기](HANDS_ON_ADMIN_DASHBOARD_1.md) 완료 + Claude Code 장표 Part 3~4
> **시작 상태**: `admin@shop.com`으로 로그인하면 KPI·차트가 보이는 대시보드

---

## 📌 0. 실습 개요

### 0.0 ⏱️ 진행 로드맵

| 절  | 내용                                        | 배정 시간 |
| :-- | :------------------------------------------ | :-------- |
| 1   | [TDD] 상품 목록 + TanStack Form/Zod 등록 폼 | 25분      |
| 2   | 테스트·린트·타입 검증 + 손으로 한 바퀴      | 10분      |
| 3   | **Playwright MCP**로 브라우저 자동 E2E 검증 | 10분      |
| 4   | **스킬(Skills)** 설치·분석·직접 제작        | 15분      |
| 5   | 마무리 · 결과물 공유                        | 10분      |

### 0.1 시작 전 확인

```bash
cd ecommerce-admin
npm run dev
```

`http://localhost:3000/login`에서 `admin@shop.com` / `admin1234!` 로 로그인해
대시보드가 보이면 준비 완료입니다.

> [!TIP]
> 전반부에서 막힌 부분이 있어도 괜찮습니다. 이번 실습은 **상품 페이지부터** 시작하므로,
> 대시보드가 조금 덜 완성되어 있어도 그대로 이어갈 수 있습니다.

> [!CAUTION]
> `.env.local`의 **`NEXT_PUBLIC_USE_MOCK`이 `false`인지 확인하세요.**
> `true`로 남아 있으면 지금부터 만드는 기능이 실제 DB에 저장되지 않고,
> 3절 Playwright 검증에서 원인을 찾기 어려운 형태로 어긋납니다.

---

## 🛍️ 1. [TDD] 상품 관리 기능 만들기

여기서 **Red ➡️ Green ➡️ Refactor** 사이클을 한 번 제대로 돌립니다.
"테스트를 먼저 짜라"고 말로만 지시하지 말고, **실패하는 것을 눈으로 확인한 뒤** 구현시키는 것이 핵심입니다.

### 1.1 상품 목록 (`/admin/products/page.tsx`)

**[Claude Code 프롬프트]**

```text
상품 관리 목록 화면(/admin/products)을 구현해줘.

- 상단: '상품 등록' CTA 버튼 (파란색)
- 검색/필터: 상품명 검색 인풋, 카테고리 선택 드롭다운, 재고 상태(정상, 재고부족, 품절) 필터
- 상품 테이블: 체크박스, 썸네일 이미지, 상품명, 카테고리, 판매가, 재고수량(5개 이하는 빨간색 경고 뱃지), 상태
- 행별 액션: [수정], [삭제] 버튼
- 하단: 페이지네이션 및 선택 항목 일괄 삭제 버튼
```

### 1.2 [TDD] 상품 등록 유스케이스 — 테스트 먼저

화면을 만들기 전에 **비즈니스 규칙부터 테스트로 못 박습니다.**

**[Claude Code 프롬프트]**

```text
CLAUDE.md의 클린 아키텍처와 TDD 규칙을 준수하여 상품 등록 기능을 구현해줘.
단, 아래 순서를 반드시 지켜줘.

1. core/domain/entities/product.ts 에 Product 엔티티와
   core/domain/repositories/product-repository.interface.ts 를 정의해줘.
2. tests/application/create-product.usecase.test.ts 를 먼저 작성해줘. 검증할 시나리오:
   - 정상 입력이면 생성된 Product를 반환한다
   - 가격이 0 이하이면 '가격은 0원보다 커야 합니다' 에러가 발생한다
   - 재고가 음수이면 에러가 발생한다
   - 상품명이 2자 미만이면 에러가 발생한다
3. 여기서 멈추고 npm run test:run 을 실행해서 **실패하는 것(Red)** 을 먼저 보여줘.
   아직 구현 코드는 작성하지 마.
```

> [!IMPORTANT]
> 3번을 빼먹으면 AI는 테스트와 구현을 한 번에 만들어버립니다. **빨간 실패를 눈으로 보는 것**이 TDD의 절반입니다.

실패를 확인했으면 통과시킵니다.

**[Claude Code 프롬프트]**

```text
이제 core/application/use-cases/create-product.usecase.ts 와
infrastructure/repositories/supabase-product.repository.ts 를 구현해서
방금 실패한 테스트를 통과(Green)시켜줘.
마지막에 npm run test:run 결과를 보여주고, 작업을 마치면 npm run lint 도 실행해줘.
```

### 1.3 TanStack Form + Zod 상품 등록 폼 (`/admin/products/new/page.tsx`)

**[Claude Code 프롬프트]**

```text
CLAUDE.md의 폼 표준에 따라 TanStack Form(@tanstack/react-form)과 Zod를 결합하여 상품 등록 페이지(/admin/products/new)를 구현해줘.

1. Zod 스키마 정의 (productFormSchema):
   - name: 필수, 최소 2자 이상
   - price: 필수, 0원 초과 숫자
   - stock: 필수, 0 이상의 정수
   - category: 필수 선택 ('전자제품' | '의류' | '식품' | '생활용품' | '화장품')
   - description: 최소 10자 이상

2. 폼 인터랙션:
   - 입력 필드에서 포커스가 벗어나거나(blur) 제출(submit) 시 유효성 검증
   - 각 인풋 아래에 빨간색 오류 메시지 표시
   - 저장 시 CreateProductUseCase를 호출하여 DB에 저장 후 목록으로 이동
```

> [!TIP]
> 1.2에서 만든 유스케이스의 검증 규칙과 여기 Zod 스키마의 규칙이 **같은 내용**입니다.
> 화면에서 잘못된 값을 넣어보고, 폼 에러 메시지와 테스트가 같은 규칙을 지키는지 확인해보세요.

---

## 🧪 2. 전체 검증 — 테스트 · 린트 · 타입

### 2.1 Vitest 전체 테스트 커버리지 확인

모든 도메인과 유스케이스가 정상적으로 통과하는지 검증합니다.

```bash
npm run test:run
```

**[Claude Code 점검 프롬프트]**

```text
전체 Vitest 테스트를 실행하고, 실패하는 테스트가 있다면 원인을 분석해서 클린 아키텍처 원칙에 맞게 수정해줘. 테스트 커버리지가 80% 이상인지 리포트를 확인해줘.
```

### 2.2 타입 체크 & 린트 에러 무결성 검증

```bash
npm run lint
npx tsc --noEmit
```

> [!CAUTION]
> **자주 발생하는 Next.js 런타임 오류 체크리스트**:
>
> - **Hydration Mismatch**: 서버 렌더링 날짜와 클라이언트 날짜 포맷이 일치하지 않을 때 발생 ➡️ `suppressHydrationWarning` 또는 `useEffect` 후 렌더링 처리.
> - **`'use client'` 지시어 누락**: `useState`, `recharts`, TanStack Form 훅을 사용하는 컴포넌트 상단에 `'use client'`가 누락되었는지 확인.

> [!TIP]
> 검증을 매번 따로 시키기보다, **프롬프트 끝에 "작업을 마치면 `npm run lint`와 `npx tsc --noEmit`을 실행하고 에러를 고쳐줘"를 습관처럼 붙이세요.**
> 1절 프롬프트에도 이 한 줄을 붙여두면 검증 단계에서 쌓아 둔 에러를 한꺼번에 치울 일이 없습니다.

## 🎭 3. Playwright MCP로 브라우저 자동 E2E 테스트

> 개발자가 직접 브라우저를 열고 클릭하며 테스트할 필요 없이, **Playwright MCP**를 통해 AI가 스스로 브라우저를 띄워 로그인부터 화면 렌더링, 스크린샷 캡처까지 원스톱으로 검증합니다.

### 3.1 MCP 서버 설정

`.mcp.json`에 `playwright` 서버를 추가합니다:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

> [!CAUTION]
> 패키지명은 `@playwright/mcp` 입니다.
> 최초 실행 시 브라우저 바이너리를 내려받느라 1~2분 걸릴 수 있습니다. 미리 받아두려면:
>
> ```bash
> npx playwright install chromium
> ```
>
> 설정 후 Claude Code를 재시작하고 `/mcp` 명령으로 `playwright` 서버가 connected 상태인지 확인하세요.
> (6.4의 Supabase MCP도 함께 쓴다면 `mcpServers` 안에 두 서버를 나란히 두면 됩니다.)

### 3.2 Claude Code에 자동 E2E 테스트 및 캡처 요청

먼저 로컬 서버를 띄운 상태(`npm run dev`)에서 요청합니다:

**[Claude Code 프롬프트]**

```text
Playwright MCP를 사용해서 E2E 브라우저 테스트를 수행해줘:
1. http://localhost:3000/login 페이지로 이동
2. 관리자 이메일과 비밀번호를 입력하고 '로그인' 버튼 클릭
3. 계정은 admin@shop.com / admin1234! 를 사용해줘
4. /admin 대시보드로 이동되었는지 URL 확인
5. 상단 4대 KPI 카드와 Recharts 차트가 제대로 렌더링되었는지 검증 (숫자가 0이거나 차트가 비어 있으면 RLS/관리자 권한 문제이므로 그 원인까지 알려줘)
6. 최종 대시보드 화면을 캡처해서 'public/e2e-dashboard-preview.png'로 저장하고 결과를 요약해줘.
```

> [!TIP]
> AI가 마우스 커서와 폼 입력을 대신 조작하며 실시간으로 대시보드를 검증하고 스크린샷을 찍어내는 모습을 보면, "E2E 테스트 자동화의 미래"를 직접 경험할 수 있습니다!

---

## 🧩 4. 스킬(Skills) — 남의 스킬 뜯어보고 내 스킬 만들기

`CLAUDE.md`는 **모든 세션에 항상 로드**되는 프로젝트 지침입니다. 반대로 **스킬(Skill)** 은
`.claude/skills/<이름>/SKILL.md`에 두고 **필요할 때만 불려 나오는** 지침입니다.
자주 쓰지는 않지만 절차가 긴 작업을 스킬로 빼두면, 평소 컨텍스트를 낭비하지 않고도
그 작업을 할 때만 정확한 절차를 따르게 만들 수 있습니다.

이 절에서는 **공개된 스킬을 설치해서 써보고 → 코드를 뜯어보고 → 같은 구조로 내 스킬을 만드는** 순서로 진행합니다.

> [!NOTE]
> 스킬의 전체 스펙(frontmatter 필드, 트리거 방식, 우선순위 등)은 공식 문서에 정리되어 있습니다.
> [Agent Skills — 공식 문서](https://platform.claude.com/docs/ko/agents-and-tools/agent-skills/overview)

### 4.1 공개 스킬 설치해서 써보기 (`eli5`)

Claude Code는 **플러그인 마켓플레이스**로 스킬을 배포합니다.
공식 커뮤니티 마켓플레이스에서 `eli5`(Explain Like I'm 5) 스킬을 설치해봅니다.

**1) 마켓플레이스 등록** (최초 한 번만)

```bash
claude plugin marketplace add anthropics/claude-plugins-community
```

**2) 스킬 설치**

```bash
claude plugin install eli5@claude-community
```

> [!TIP]
> 세션 안에서는 `/plugin` 명령으로 마켓플레이스를 둘러보며 설치할 수도 있습니다.
> 파일을 직접 복사할 필요가 없고 업데이트도 명령 한 줄이라, 팀에 배포할 때 특히 편합니다.

**3) 써보기**

Claude Code를 재시작한 뒤, 오늘 배운 것 중 헷갈렸던 개념을 넣어보세요.

**[Claude Code 프롬프트]**

```text
/eli5 Supabase RLS
```

```text
/eli5 클린 아키텍처의 의존성 역전
```

큰 그림과 짧은 문장으로 된 HTML 설명 페이지가 만들어집니다.

> [!NOTE]
> `/eli5`라고 명시적으로 부르지 않고 **"이거 초등학생도 알아듣게 설명해줘"** 라고만 해도 동작합니다.
> `SKILL.md` 맨 위 `description`에 **어떤 말이 나오면 이 스킬을 쓸지**가 적혀 있고,
> Claude가 그걸 보고 스스로 판단하기 때문입니다. 이 `description`이 스킬의 절반입니다.

### 4.2 스킬 코드 뜯어보기

설치한 스킬이 어떻게 생겼는지 직접 열어봅니다.

```bash
cat ~/.claude/plugins/marketplaces/claude-community/eli5/skills/eli5/SKILL.md
```

> [!TIP]
> 경로가 다르면 아래로 찾으세요.
>
> ```bash
> find ~/.claude/plugins -name "SKILL.md" -path "*eli5*"
> ```

**전문이 이게 전부입니다. 10줄입니다.**

```markdown
---
name: eli5
description: Explain a topic like I'm a 5 year old. Use when the user types /eli5 <topic> or asks for a dead-simple picture explainer of how something works.
---

# eli5

Explain like I'm someone who knows nothing about this topic, using a HTML artifact with big pictures and few words.

Topic: $ARGUMENTS
```

읽어야 할 포인트는 3가지입니다.

| 요소          | 역할                                                                                                                                                                |
| :------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `name`        | 스킬 식별자. 디렉터리명과 맞춥니다. `/eli5` 슬래시 명령이 여기서 나옵니다.                                                                                          |
| `description` | **트리거**. 어떤 상황·어떤 표현에서 호출될지를 적습니다. 여기서는 `/eli5`뿐 아니라 _"dead-simple picture explainer"_ 같은 **요청의 의도**까지 적어둔 게 핵심입니다. |
| 본문          | 실제 지침. `$ARGUMENTS` 자리에 사용자가 입력한 값이 들어갑니다.                                                                                                     |

> [!IMPORTANT]
> **스킬은 프로그램이 아니라 지시문입니다.**
> 코드도, 설정도, 빌드도 없습니다. 마크다운 몇 줄이 전부입니다.
> 잘 만든 스킬과 대충 만든 스킬의 차이는 **문장의 정확도**에서 갈립니다.

직접 읽기 전에 Claude에게 먼저 분석시켜도 좋습니다.

**[Claude Code 프롬프트]**

```text
방금 설치한 eli5 스킬의 SKILL.md를 찾아서 읽고,
description이 트리거로서 어떻게 동작하는지, $ARGUMENTS가 무슨 역할인지 설명해줘.
```

### 4.3 우리 프로젝트 전용 스킬 만들기

이제 같은 구조로 **이 프로젝트 전용 스킬**을 만듭니다.
전반부와 이번 실습에서 페이지를 여러 번 추가했는데, 매번 같은 절차를 밟았습니다. 그 절차를 스킬로 굳혀 둡니다.

관리자 화면에만 쓰는 스킬이 아니라 **앞으로 어떤 페이지를 추가할 때든 쓸 수 있도록** 만듭니다.

**[Claude Code 프롬프트]**

```text
이 프로젝트 전용 새로운 페이지 추가 스킬을 만들어줘

- name: add-page
- description: 새로운 페이지를 추가할 때 호출되도록, "페이지 추가", "새 화면 만들어줘", "~ 페이지 만들어줘" 같은 표현을 포함해서 구체적으로 작성
- 본문에는 우리가 실제로 따랐던 절차를 단계로 정리해줘:
  1. core/domain 엔티티/리포지토리 인터페이스 확인 또는 추가
  2. core/application 유스케이스 작성 + tests/ 에 Vitest 테스트 먼저 작성 (Red)
  3. infrastructure/supabase 리포지토리 구현 (Green)
  4. src/app/<경로>/page.tsx 생성 (관리자 화면이면 사이드바 링크도 함께 추가)
  5. npm run test:run, npm run lint, npx tsc --noEmit 로 마무리 검증
- CLAUDE.md의 클린 아키텍처 4계층 규칙을 위반하지 않도록 주의 문구도 넣어줘.
```

**만들어진 파일을 먼저 눈으로 확인하세요.**

```bash
cat .claude/skills/add-page/SKILL.md
```

4.2에서 본 `eli5`와 똑같은 형태(frontmatter + 본문)인지, `description`이 충분히 구체적인지 보세요.

#### 스킬 인식시키기

> [!IMPORTANT]
> **`.claude/skills/` 디렉터리를 이번에 처음 만들었다면 Claude Code를 재시작해야 합니다.**
> Claude Code는 스킬 폴더의 변경을 실시간으로 감지하지만,
> **세션 시작 시점에 없던 최상위 디렉터리**는 감시 대상에 들어 있지 않기 때문입니다.
>
> 한 번 인식된 뒤로는 `SKILL.md`를 고쳐도 재시작 없이 바로 반영됩니다.

```bash
# 세션 종료 후 다시 실행
claude
```

#### 등록 확인

슬래시 명령 목록에서 확인하는 게 가장 확실합니다.

```text
/add-page
```

입력창에 `/add` 까지만 쳐도 자동완성 목록에 **`add-page`** 가 떠야 합니다.
목록에 없다면 아래를 점검하세요.

| 증상             | 확인할 것                                                               |
| :--------------- | :---------------------------------------------------------------------- |
| 목록에 안 뜸     | 경로가 `.claude/skills/<이름>/SKILL.md` 가 맞는지 (`SKILL.md`는 대문자) |
| 이름이 다르게 뜸 | frontmatter의 `name` 과 디렉터리명이 일치하는지                         |
| 여전히 안 됨     | Claude Code 재시작                                                      |

#### 써보기

**[Claude Code 프롬프트]**

```text
/admin/low-stock 재고 부족 상품 전용 페이지를 추가해줘. products 테이블에서 재고 5개 미만인 상품만 목록으로 보여줘.
```

스킬 이름을 부르지 않았는데도 `add-page` 스킬이 호출되는지 보세요.
`description`을 잘 썼다면 Claude가 스스로 이 스킬을 집어 듭니다.

> [!TIP]
> 스킬을 쓰기 전과 후를 비교해 보세요. 스킬이 없을 때는 매번 "테스트 먼저 짜고, 계층 지키고…"를
> 프롬프트에 다시 적어야 했지만, 스킬이 있으면 **한 줄만 말해도 같은 절차**가 반복됩니다.
> `.claude/skills/`는 프로젝트에 커밋되므로 팀원 전체가 같은 절차를 공유하게 됩니다.

> [!NOTE]
> **`CLAUDE.md`에 넣을까, 스킬로 뺄까?**
>
> - 항상 지켜야 하는 규칙(아키텍처 계층, 코딩 컨벤션) ➡️ `CLAUDE.md`
> - 가끔 하지만 절차가 긴 작업(페이지 추가, 배포, 마이그레이션) ➡️ **스킬**
>
> 모든 걸 `CLAUDE.md`에 넣으면 매 세션 토큰을 낭비하고, 정작 중요한 규칙이 묻힙니다.

---

## 🏆 5. 마무리 & Day 3 해커톤 브릿지

### 📸 오늘의 결과물

3절에서 Playwright가 찍어준 `public/e2e-dashboard-preview.png`가 오늘의 산출물입니다.
**내가 클릭하지 않았는데 AI가 로그인해서 찍어온 화면**입니다.

```bash
git add -A && git commit -m "상품 관리 + MCP 검증 + 커스텀 스킬"
```

### 🎯 더 해보기

시간이 남는 분들을 위해 **6절 개인 실습**에 다섯 가지 주제를 정리해두었습니다.
주문 관리, 고객 관리, 이미지 업로드, AI 어시스턴트, 실시간 알림입니다.

### 🚀 Day 3 해커톤으로의 연결

- **Day 1**: Cursor로 감각 깨우기 ➡️ Claude Code로 RAG 챗봇
- **Day 2**: 클린 아키텍처 · Supabase · TDD · MCP · 커스텀 스킬
- **Day 3 (해커톤)**: 기획 ➡️ 아키텍처 ➡️ 인프라 ➡️ TDD 구현까지 AI 에이전트를 직접 지휘

이제 **CLAUDE.md로 규칙을 세우고, 스킬로 절차를 굳히고, MCP로 검증까지 맡기는** 한 바퀴를 다 돌았습니다.
해커톤에서는 이 사이클을 여러분의 아이디어에 그대로 적용하면 됩니다.
(주제 선정과 기획은 **3일차 오전**에 함께 합니다. 오늘 미리 정해오지 않아도 됩니다.)

---

## 🎒 6. 개인 실습 (선택)

수업에서는 여기까지 다루지 않습니다. **시간이 남는 분들을 위한 재료**입니다.
**4절에서 만든 `add-page` 스킬을 쓰면 훨씬 빨리 끝납니다.** 스킬을 만들어 둔 값을 확인해보세요.

|     | 주제                                      | 난이도                  |
| :-- | :---------------------------------------- | :---------------------- |
| 6.1 | 주문 관리 · 고객 관리 화면                | ⭐ 스킬로 바로          |
| 6.2 | Supabase Storage 이미지 업로드            | ⭐⭐                    |
| 6.3 | AI 어시스턴트 (상품 설명 생성 · SEO 태그) | ⭐⭐ Claude API 키 필요 |
| 6.4 | Supabase MCP로 DB 셀프 검증               | ⭐ 설정만 하면 끝       |
| 6.5 | 실시간 주문 알림 (Supabase Realtime)      | ⭐⭐⭐ 직접 설계        |

### 6.1 주문 및 고객 관리

#### 주문 목록 (`/admin/orders/page.tsx`)

**[Claude Code 프롬프트]**

```text
주문 관리 목록 화면(/admin/orders)을 구현해줘.

- 상태별 탭 필터: [전체 | 결제대기 | 결제완료 | 배송준비 | 배송중 | 배송완료 | 주문취소]
- 탭 옆에 해당 상태의 주문 건수 카운트 뱃지 표시
- 검색 및 기간 필터: 주문번호/고객명 검색창, 날짜 범위(시작일~종료일) 선택
- 주문 테이블 컬럼: 주문번호, 주문일시, 고객명, 주문상품 요약, 결제금액, 배송상태(색상 뱃지)
- 행 클릭 시 상세 페이지(/admin/orders/[id])로 이동
```

#### 주문 상세 (`/admin/orders/[id]/page.tsx`)

**[Claude Code 프롬프트]**

```text
주문 상세 화면(/admin/orders/[id])을 구현해줘.

- 상단: 주문번호 및 5단계 가로 진행바 (결제대기 -> 결제완료 -> 배송준비 -> 배송중 -> 배송완료)
  - 현재 단계까지 브랜드 컬러로 하이라이트 표시
- 2열 레이아웃 카드 구성:
  - 좌측 카드: 주문 정보(주문일시, 결제수단), 고객 정보(이름, 연락처, 이메일)
  - 우측 카드: 배송 정보(수령인, 주소, 배송메모), 택배사 선택 드롭다운 및 운송장 번호 입력 폼
- 하단: 주문 상품 상세 목록 및 최종 결제 금액 요약 카드
- 하단 액션 버튼: [배송 상태 업데이트] 버튼, [주문 취소] (빨간색) 버튼
```

#### 고객 목록 및 상세 (`/admin/customers`, `[id]`)

**[Claude Code 프롬프트]**

```text
고객 관리(/admin/customers) 및 고객 상세(/admin/customers/[id]) 페이지를 구현해줘.

1. 고객 목록:
   - 검색(이름/이메일), 정렬(최근 가입순, 누적 구매액순)
   - VIP 고객은 이름 옆에 노란색 별 아이콘 뱃지 표시
   - 상단 요약 배너: 총 고객 수, 이번달 신규 고객, VIP 회원 수
2. 고객 상세:
   - 좌측: 고객 프로필 카드 및 누적 주문 수, 총 구매액 지표
   - 우측: 해당 고객의 주문 히스토리 테이블 및 선호 카테고리 가로 바 차트
```

---

### 6.2 Supabase Storage 이미지 업로드

**[Claude Code 프롬프트]**

```text
상품 등록 폼에 Supabase Storage 연동 이미지 업로더 컴포넌트를 추가해줘.

1. infrastructure/supabase/supabase-storage.service.ts 생성:
   - uploadProductImage(file: File): Promise<string> 함수 구현
   - Supabase의 'product-images' 버킷에 고유한 파일명(uuid + 확장자)으로 업로드
   - 업로드 성공 후 getPublicUrl()로 퍼블릭 접근 URL을 반환하도록 작성
2. UI 컴포넌트 (ImageUploader):
   - 이미지 드래그앤드롭 및 파일 선택 지원 (PNG, JPG, WEBP, 최대 5MB)
   - 업로드 진행 중 로딩 스피너 표시
   - 업로드 완료 시 미리보기 썸네일 및 [삭제] 버튼 표시
   - 업로드된 이미지 URL을 상품 등록 폼의 'image_url' 필드와 자동 바인딩
```

### 6.3 AI 어시스턴트 (LangChain + Zod)

상품 등록 폼 하단에 AI 편의 기능을 붙여 개발자들에게 큰 호응을 얻는 포인트입니다.

> [!NOTE]
> **왜 공식 SDK가 아니라 LangChain을 쓰나요?**
>
> 1. **Day 1 오후에 배운 LCEL 체인을 그대로 재사용**합니다. 어제 배운 도구가 오늘 다른 프로젝트에서도 쓰인다는 걸 체감하는 지점입니다.
> 2. **1.3절에서 폼 검증에 쓴 그 `zod` 스키마로 AI 응답 형식까지 강제**할 수 있습니다.
>    문자열을 잘라서 해시태그를 뽑는 취약한 파싱 코드가 아예 필요 없어집니다.
> 3. LLM 제공자를 바꿀 때 **모델 생성 3줄만 교체**하면 됩니다. (아래 「참고」 항목)

```bash
npm install @langchain/core @langchain/anthropic
```

`.env.local`에 Day 1 오후 실습에서 받은 Claude API 키를 추가합니다:

```bash
ANTHROPIC_API_KEY=sk-ant-api03-xxxxxxxxxxxx
```

**[Claude Code 프롬프트]**

```text
상품 등록 페이지에 AI 어시스턴트 버튼 2개를 추가해줘:
1. [AI 상품 설명 자동 생성]: 상품명과 카테고리를 기반으로 매력적인 마케팅 문구를 3줄로 생성하여 설명란에 채워줌
2. [SEO 태그 추천]: 상품에 맞는 해시태그 5개를 추천하여 칩(chip) 형태로 표시

[구현 조건]
- 라우트 핸들러: src/app/api/ai/generate-description/route.ts
- LangChain을 사용한다. 공식 SDK(@anthropic-ai/sdk)를 직접 호출하지 마라.
  import { ChatAnthropic } from "@langchain/anthropic";
  const model = new ChatAnthropic({ model: "claude-haiku-4-5", apiKey: process.env.ANTHROPIC_API_KEY });
- 응답 형식은 문자열 파싱이 아니라 model.withStructuredOutput(schema)로 강제한다.
  스키마는 zod로 정의하며, 1.3절의 productFormSchema와 같은 파일 컨벤션을 따른다:
    z.object({
      description: z.string().describe("3줄 이내의 매력적인 상품 설명"),
      tags: z.array(z.string()).length(5).describe("# 없이 키워드만 담은 해시태그 5개"),
    })
- API 키는 서버에서만 읽는다(process.env.ANTHROPIC_API_KEY). 클라이언트로 절대 노출하지 않는다.
- 응답은 { success: boolean, data?: { description, tags }, error?: string } 포맷으로 반환한다.
- 버튼에는 생성 중 로딩 스피너와 disabled 처리를 넣고, 실패 시 토스트로 에러를 표시한다.
```

> [!IMPORTANT]
> 모델 ID는 **`claude-haiku-4-5`** 입니다. `claude-3-5-haiku-latest` 같은 구버전이나
> `claude-haiku-4-5-20251001` 처럼 날짜를 덧붙인 문자열을 쓰지 않도록 주의하세요.

> [!TIP]
> **`withStructuredOutput`이 왜 중요한가**: LLM에게 "해시태그 5개를 줘"라고 하면
> 어떤 날은 `#방수 #무선`, 어떤 날은 `1. 방수\n2. 무선`으로 옵니다. 문자열 파싱은 반드시 언젠가 깨집니다.
> 스키마를 넘기면 모델이 그 형태로 응답하도록 강제되고, 결과는 이미 `string[]` 타입입니다.
> **1.3절의 폼 검증과 똑같은 도구(zod)로 AI 출력까지 통제한다**는 게 이 절의 핵심 학습 포인트입니다.

---

#### 참고: LLM 제공자를 OpenAI로 바꾸려면

주최측 Claude API 키 배포가 지연되거나 rate limit에 걸렸을 때를 위한 대체 경로입니다.
**LangChain을 쓴 덕분에 체인 로직은 한 글자도 바뀌지 않습니다.**

**AI 어시스턴트 쪽**

```bash
npm install @langchain/openai
```

```ts
// Before
import { ChatAnthropic } from "@langchain/anthropic";
const model = new ChatAnthropic({
  model: "claude-haiku-4-5",
  apiKey: process.env.ANTHROPIC_API_KEY,
});

// After
import { ChatOpenAI } from "@langchain/openai";
const model = new ChatOpenAI({
  model: "gpt-5-nano",
  apiKey: process.env.OPENAI_API_KEY,
});
```

이 아래로 이어지는 `withStructuredOutput(schema)`, `.invoke()`는 **변경 없음**입니다.
`.env.local`의 `ANTHROPIC_API_KEY`를 `OPENAI_API_KEY`로 바꾸기만 하면 됩니다.

**Day 1 오후 RAG 챗봇 쪽**

`/api/chat`의 답변 생성 모델만 위와 동일하게 교체합니다.
**검색(Retrieval) 쪽은 건드리지 않습니다.** Pinecone 통합 임베딩은 제공자와 무관하게 그대로 동작하며,
`upsertRecords` / `searchRecords` 코드도 변경할 필요가 없습니다.

> [!TIP]
> OpenAI 키가 생기면 `OpenAIEmbeddings` + `PineconeStore`라는 "인터넷 자료에서 흔히 보는" 정석 구조로도 갈 수 있습니다.
> 다만 그 경우 **Pinecone 인덱스를 1536차원 일반(dense) 인덱스로 새로 만들고 인덱싱/검색 코드를 전면 재작성**해야 합니다.
> 급하게 전환해야 한다면 위의 3줄 교체를 권장합니다.

> [!CAUTION]
> **비용 주의**: Anthropic 키와 달리 OpenAI 키는 개인 결제 수단 등록이 필요할 수 있습니다.
> 결제 등록부터 시작하면 시간이 오래 걸리니, OpenAI로 바꿔볼 분은 미리 키를 준비해 두세요.
> 모델 ID(`gpt-5-nano`)는 사용 시점에 OpenAI 공식 문서에서 유효성을 확인하세요.

### 6.4 Supabase MCP로 DB 셀프 검증하기

Playwright MCP가 **브라우저**를 봐준다면, Supabase MCP는 **DB**를 봐줍니다.
웹 콘솔을 열지 않고도 Claude Code가 테이블·시드 데이터·RLS 정책을 직접 확인합니다.

> **Model Context Protocol (MCP)**를 활용하면, 브라우저 대시보드를 열어보지 않고도 터미널의 Claude Code가 Supabase 인스턴스에 직접 질의하여 테이블, 스키마, RLS 정책을 셀프로 검증합니다.

#### 1) Personal Access Token 발급

Supabase MCP는 프로젝트 키가 아니라 **계정 단위 PAT(Personal Access Token)** 으로 인증합니다.

Supabase 대시보드 우측 상단 프로필 ➡️ **Account Settings ➡️ Access Tokens ➡️ [Generate new token]**
발급된 `sbp_...` 토큰을 복사해 둡니다.

#### 2) MCP 서버 설정

프로젝트 루트에 `.mcp.json`을 추가합니다:

```json
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": [
        "-y",
        "@supabase/mcp-server-supabase@latest",
        "--read-only",
        "--project-ref=<YOUR_PROJECT_REF>"
      ],
      "env": {
        "SUPABASE_ACCESS_TOKEN": "sbp_your_personal_access_token"
      }
    }
  }
}
```

> [!CAUTION]
>
> - 패키지명은 `@supabase/mcp-server-supabase` 입니다. `@modelcontextprotocol/server-supabase`라는 패키지는 **존재하지 않습니다.**
> - 실습에서는 `--read-only`를 반드시 붙이세요. AI가 실수로 테이블을 지우는 사고를 막아줍니다.
> - `.mcp.json`에 토큰이 들어가므로 **`.gitignore`에 `.mcp.json`을 추가**하세요.
> - 설정 후 Claude Code를 재시작하고 `/mcp` 명령으로 `supabase` 서버가 connected 상태인지 확인합니다.

#### 3) Claude Code에 셀프 검증 요청

**[Claude Code 프롬프트]**

```text
Supabase MCP 도구를 사용해서 다음을 직접 확인해줘:
1. 방금 마이그레이션된 'products', 'orders', 'customers', 'order_items' 테이블의 컬럼 구조와 시드 데이터 3건씩 조회
2. 각 테이블의 총 row 수를 세어줘 (products 10 / customers 12 / orders 60건 내외가 정상)
3. 'product-images' Storage 버킷이 정상적으로 존재하는지 확인
4. public.users 테이블에 role='admin'인 계정이 1건 있는지 확인 (없으면 전반부 2.3절을 다시 수행해야 함)
5. RLS 정책이 활성화되어 있는지 점검하고 요약 보고서를 출력해줘.
```

> [!TIP]
> AI가 직접 데이터베이스와 대화하며 스키마를 확인하는 과정을 터미널에서 지켜보면, "개발자가 웹 콘솔을 일일이 확인할 필요 없는 차세대 워크플로우"를 실감할 수 있습니다!

---

### 6.5 실시간 주문 알림 (Supabase Realtime)

여기서부터는 **프롬프트를 직접 설계**해보세요. 지금까지의 패턴이면 충분히 만들 수 있습니다.

> Supabase Realtime 채널(`postgres_changes`)을 구독해서, 다른 창에서 새 주문이 들어오면
> 우측 상단에 "🔔 새 주문이 접수되었습니다! (ORD-XXXX)" 토스트가 뜨도록 만들어보세요.
