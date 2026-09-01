# [Hands-on] Claude Code로 만드는 쇼핑 리뷰 분석 RAG 챗봇

> **과정명**: 개발자를 위한 클로드 코드와 커서 AI 실전 (**Day 1 오후** 실습)  
> **실습 주제**: Claude Code CLI를 활용한 풀스택 RAG(검색 증강 생성) 쇼핑 리뷰 분석 챗봇 구축  
> **예상 소요 시간**: 따라하기 실습 120분 + 개인 미션 60분 (실측 기준)  
> **핵심 기술 스택**: Next.js 16 (App Router), TypeScript, Tailwind CSS, LangChain.js (LCEL), Pinecone, Supabase, Claude API (Anthropic - 주최측 제공)

> [!NOTE]
> **기술 선택 안내**: 답변 생성 LLM은 **Claude(`claude-haiku-4-5`)**, 개발 도구는 **Claude Code**를 사용합니다.
> 임베딩은 별도 키가 필요 없는 **Pinecone 무료 통합 임베딩(llama-text-embed-v2)** 을 사용합니다.
> (인터넷 자료에는 OpenAI 기준 예제가 많습니다. 차이가 나는 부분은 부록에 정리해 두었습니다.)

---

## 📌 실습 개요 및 아키텍처

본 실습에서는 수백 개의 실제 고객 쇼핑 리뷰를 벡터 데이터베이스에 적재하고, 사용자의 자연어 질문에 맞춰 가장 관련도 높은 리뷰를 실시간으로 검색(Retrieval)하여 정확하고 환각 없는 답변(Generation)을 제공하는 **RAG(검색 증강 생성) 분석 챗봇**을 구축합니다.

모든 과정은 터미널 에이전트인 **Claude Code**의 지휘 아래 **EPCC (Explore ➡️ Plan ➡️ Code ➡️ Commit)** 워크플로우로 진행됩니다.

```mermaid
flowchart TB
    subgraph Client ["클라이언트 (Next.js 16 + Tailwind)"]
        UI["채팅 & 분석 대시보드 UI"]
        Btn["[샘플 데이터 인덱싱] 버튼"]
    end

    subgraph Backend ["Next.js App Router API"]
        IndexAPI["/api/index-data (데이터 적재)"]
        ChatAPI["/api/chat (LangChain LCEL RAG)"]
    end

    subgraph VectorDB ["Pinecone (Vector DB)"]
        Index["인덱스: review-chatbot\n통합 임베딩 llama-text-embed-v2 (1024 dim)\nupsertRecords / searchRecords"]
    end

    subgraph RDB ["Supabase (PostgreSQL)"]
        TableReviews["reviews (원본 리뷰 100건)"]
        TableMessages["messages (대화 히스토리)"]
    end

    subgraph LLM ["Anthropic (교육장 제공 키)"]
        Claude["Claude Haiku 4.5 (claude-haiku-4-5, 답변 생성)"]
    end

    Btn -->|1. CSV 파싱 및 임베딩 요청| IndexAPI
    IndexAPI -->|2. 벡터 저장| Index
    IndexAPI -->|3. 원본 데이터 저장| TableReviews

    UI -->|4. 자연어 질문 전송| ChatAPI
    ChatAPI -->|5. 유사도 Top-5 검색| Index
    ChatAPI -->|6. 컨텍스트 + 질문 프롬프트| Claude
    Claude -->|7. 리뷰 기반 분석 답변| ChatAPI
    ChatAPI -->|8. 답변 + 근거 리뷰 반환| UI
    ChatAPI -.->|대화 기록 저장| TableMessages
```

---

## 0단계: 환경 준비 및 사전 체크리스트

### 0.1 필수 준비물
실습 시작 전 아래 3가지 서비스의 계정과 키가 준비되어 있어야 합니다.

1. **Claude API Key (주최측 제공)**: 특강 교육장에서 강사가 배포하는 Anthropic API Key (`sk-ant-api03-...`)
2. **Pinecone 계정 및 API Key**: [pinecone.io](https://www.pinecone.io) 회원가입 후 API Key 발급
3. **Supabase 계정**: [supabase.com](https://supabase.com) 가입 후 새 프로젝트 생성 준비

### 0.2 환경 점검 및 도구 설치 (macOS / Windows 공통)

#### 🪟 Windows 환경 설정 (winget 사용)
Windows 터미널(PowerShell)을 **관리자 권한**으로 실행한 후 아래 명령어로 개발 환경을 준비합니다:
```powershell
# 1. Node.js LTS 및 Git 설치 (winget 활용)
winget install OpenJS.NodeJS.LTS
winget install Git.Git

# 2. PowerShell 스크립트 실행 권한 허용 (npm/npx 보안 오류 방지)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# 3. Claude Code 전역 설치
npm install -g @anthropic-ai/claude-code
```
> 💡 *Chocolatey를 사용하는 경우*: `choco install nodejs-lts git -y`

#### 🍎 macOS 환경 설정 (Homebrew 사용)
```bash
brew install node git
npm install -g @anthropic-ai/claude-code
```

#### 도구 설치 및 버전 확인
```bash
node -v          # v18 이상 권장
claude --version # Claude Code 정상 설치 확인
```

### 0.3 실습 프로젝트 폴더 생성
```bash
# macOS / Linux
mkdir -p ~/dev/review-chatbot
cd ~/dev/review-chatbot

# Windows (PowerShell)
New-Item -ItemType Directory -Force -Path $HOME\dev\review-chatbot
Set-Location $HOME\dev\review-chatbot
```

---

## 1단계: Claude Code로 프로젝트 초기화 & `CLAUDE.md` 세팅 (Explore & Plan)

Claude Code의 핵심은 **프로젝트의 규칙과 아키텍처를 `CLAUDE.md`에 명시**하여 AI가 일관된 품질로 코드를 작성하도록 통제하는 것입니다.

### 1.1 `CLAUDE.md` 생성

프로젝트 루트(`~/dev/review-chatbot/CLAUDE.md`)에 아래 내용을 **그대로 복사해서** 파일을 만듭니다.
(배포 자료의 `CLAUDE_TEMPLATE.md`와 동일한 내용입니다.)

```markdown
# Review Chatbot Guidelines

## Project Overview
Next.js 16 (App Router) 기반의 쇼핑 리뷰 분석 RAG(Retrieval-Augmented Generation) 챗봇입니다.
Pinecone 벡터 데이터베이스와 Supabase, LangChain.js (LCEL)를 활용하여 고객 리뷰를 분석하고 근거 기반 답변을 제공합니다.

## Tech Stack & Architecture
- **Framework**: Next.js 16 (App Router), React 19, TypeScript
- **Styling**: Tailwind CSS, Lucide React
- **Generation**: LangChain.js (`@langchain/core`, `@langchain/anthropic`) — 프롬프트 조립 및 답변 생성 전용
- **Retrieval**: `@pinecone-database/pinecone` SDK 직접 호출
- **Vector DB**: Pinecone 인덱스 `review-chatbot`
  - **통합 임베딩(Integrated Inference) 인덱스**: `llama-text-embed-v2`, 1024 dim, cosine
- **Database**: Supabase PostgreSQL (`reviews`, `messages` tables)
- **LLM**: Anthropic `claude-haiku-4-5` (주최측 제공 API Key 사용)

## 🚫 절대 금지 사항 (Hard Constraints)
1. **`@langchain/pinecone`의 `PineconeStore`를 사용하지 않는다.**
   본 프로젝트의 Pinecone 인덱스는 통합 임베딩 인덱스이므로 클라이언트 측 Embeddings 객체를 주입하는 `PineconeStore`와 호환되지 않는다.
2. **`OpenAIEmbeddings` 등 외부 임베딩 라이브러리를 추가하지 않는다.**
   Anthropic API는 임베딩 엔드포인트를 제공하지 않으며, 본 실습에는 임베딩용 키가 존재하지 않는다.
3. 벡터 적재는 반드시 `namespace.upsertRecords()`, 검색은 반드시 `namespace.searchRecords()`를 사용한다.
   - 적재 레코드 형태: `{ _id, text, rating, author, title, content }` (`text`가 임베딩 대상 필드)
   - 검색 결과: `res.result.hits[]` → 각 hit의 `_id` / `_score` / `fields`
4. 모델 ID는 `claude-haiku-4-5`를 사용한다. 날짜 suffix를 붙이지 않는다.

## Development Workflow & Rules
1. **Explore & Plan First**:
   - 큰 기능이나 파일 변경 전에는 반드시 `/plan`을 거쳐 파일 구조와 의존성을 파악한 뒤 구현합니다.
2. **App Router Conventions**:
   - `src/app` 구조를 유지합니다.
   - 클라이언트 상태가 필요한 경우에만 명시적으로 `'use client'` 지시어를 선언합니다.
   - API 라우트는 `src/app/api/.../route.ts` 규격을 준수합니다.
3. **Defensive UI Implementation**:
   - 한글 입력 시 IME 중복 전송 버그를 방지하기 위해 `onKeyDown` 이벤트에서 `e.nativeEvent.isComposing` 상태를 항상 체크합니다.
4. **Environment Variables**:
   - 환경변수는 하드코딩하지 않고 항상 `process.env.*`를 참조합니다.
   - Supabase 공개 키는 `process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY` 순으로 fallback 처리합니다.
5. **API Response Format**:
   - 모든 API 응답은 `{ success: boolean, data?: unknown, error?: string }` 포맷을 반환합니다.
6. **Git Commit Rule**:
   - 단위 작업 완료 후 Conventional Commits 규칙(`feat:`, `fix:`, `refactor:`)에 맞춰 간결한 한국어 커밋 메시지를 작성합니다.
```

> [!IMPORTANT]
> **「🚫 절대 금지 사항」 섹션을 지우지 마세요.**
> 이 규칙이 없으면 Claude Code가 인터넷에 흔한 일반적인 LangChain RAG 예제를 따라
> `PineconeStore` + `OpenAIEmbeddings` 조합으로 코드를 작성합니다.
> 그런데 우리에게는 임베딩용 API 키가 없으므로 **401 에러로 실습이 통째로 멈춥니다.**

### 1.2 Claude Code 실행 및 Next.js 프로젝트 생성
터미널에서 `claude`를 실행합니다.

```bash
claude
```

Claude Code 대화창에 아래 프롬프트를 입력하여 Next.js 프로젝트 스캐폴딩을 진행합니다.

> 💬 **Claude Code 프롬프트 1-1 (스캐폴딩)**
> ```text
> 현재 디렉토리에 Next.js 16 최신 프로젝트를 생성해줘.
> - App Router 사용
> - TypeScript 사용
> - Tailwind CSS 사용
> - ESLint 사용
> - src/ 디렉토리 구조 사용
> - import alias: @/*
> 패키지 매니저는 npm을 사용하고, 설치가 완료되면 CLAUDE.md 규칙을 확인해줘.
> ```

### 1.3 기본 UI 레이아웃 구현 (Explore ➡️ Plan ➡️ Code)
현업 실전처럼 **Plan Mode**를 거쳐 UI 컴포넌트를 설계하도록 지시합니다.

> 💬 **Claude Code 프롬프트 1-2 (Plan & UI 구현)**
> ```text
> /plan 쇼핑 리뷰 분석 챗봇의 메인 대시보드 UI를 구현하려고 해.
> 
> [화면 구성 요구사항]
> 1. 좌측 사이드바 (Sidebar):
>    - 서비스 타이틀 ("쇼핑 리뷰 AI 분석기")
>    - [샘플 데이터 인덱싱] 버튼 (로딩 스피너 및 상태 표시)
>    - 최근 분석 질문 히스토리 목록
> 2. 우측 메인 영역 (Chat Area):
>    - 상단: 분석 대상 상품 정보 배너 (예: "노이즈캔슬링 무선 이어폰 PRO")
>    - 중앙: 대화 메시지 스트림 (사용자 질문, AI 답변)
>    - AI 답변 하단: 답변 근거로 활용된 "참고 리뷰 카드(Top 3~5)" 아코디언/배지 표시
>    - 하단: 질문 입력창 및 전송 버튼 (한글 IME 엔터 입력 시 두 번 전송되지 않도록 방어 코드 포함)
> 
> 먼저 컴포넌트 구조를 계획(Plan)해주고, 내가 확인하면 코드를 작성해줘.
> Lucide-react 아이콘을 적극적으로 활용해줘.
> ```

Claude Code가 제시하는 계획을 확인한 뒤 승인(`y` 또는 `proceed`)하여 코드를 생성합니다.

---

## 2단계: 외부 인프라 연동 및 샘플 데이터 준비

### 2.1 Pinecone 인덱스 생성 (통합 임베딩 방식)
1. [Pinecone Console](https://app.pinecone.io/) 접속 ➡️ 좌측 **Database ➡️ Indexes ➡️ [Create Index]** 클릭
2. 설정값 입력:
   - **Index Name**: `review-chatbot`
   - **Configuration(모델)**: NVIDIA `llama-text-embed-v2` 선택
     - 👉 **모델을 고르면 Dimensions(1024)와 Metric(cosine)이 자동으로 확정됩니다.** 차원을 직접 입력하는 칸은 없습니다.
   - **Capacity mode**: `Advanced settings ➡️ On-demand`
   - **Cloud / Region**: `AWS / us-east-1 (Virginia)` — 무료 요금제의 유일한 옵션
3. 생성 완료 후 인덱스 상세 화면의 **Host URL** (예: `https://review-chatbot-xxxx.svc.aped-4627-b74a.pinecone.io`)과 **API Key**를 복사해 둡니다.

방금 만든 인덱스는 리뷰 문장을 좌표로 바꿔서 저장합니다. 비슷한 내용의 리뷰끼리는 가까운 좌표에 놓이고,
사용자의 질문도 같은 방식으로 좌표를 얻어 **가장 가까운 리뷰들만** 찾아옵니다.

![diagram w:900](assets/embedding-space.svg)

예를 들어 "러닝머신에서 안 빠지나요?"라는 질문은 고정력·운동 관련 리뷰 근처에 놓이고,
음질을 다루는 리뷰들과는 자연히 멀어집니다. 뒤에 나올 `searchRecords()`가 바로 이 좌표 거리를 계산해줍니다.

> [!IMPORTANT]
> **왜 이 모델을 쓰나요? — 임베딩 키가 필요 없기 때문입니다.**
> 위 방식으로 만든 인덱스는 **Integrated Inference(통합 임베딩) 인덱스**입니다.
> 텍스트를 그대로 넣으면 Pinecone 서버가 임베딩까지 대신 처리하므로 **OpenAI 등 별도 임베딩 API 키가 전혀 필요 없습니다.**
> (참고: Anthropic Claude API는 임베딩 엔드포인트를 제공하지 않습니다. 그래서 임베딩은 Pinecone, 답변 생성은 Claude로 역할을 나눕니다.)
>
> 대신 **일반 벡터 인덱스와 API가 다릅니다.**
> 적재는 `namespace.upsertRecords()`, 검색은 `namespace.searchRecords()`를 사용해야 하며,
> LangChain의 `PineconeStore`는 클라이언트 측 임베딩 객체를 필수로 요구하기 때문에 **이 인덱스에는 사용할 수 없습니다.**
> 3단계 프롬프트에 이 제약이 명시되어 있으니 그대로 사용하세요.

### 2.2 Supabase 프로젝트 생성 및 테이블 설정
1. [Supabase Dashboard](https://supabase.com/dashboard) ➡️ **New project** 클릭 (이름: `chat`, Region: `Northeast Asia (Seoul)`)

> [!NOTE]
> **프로젝트 생성 화면의 `Advanced Configuration ➡️ Security`는 셋 다 기본값 그대로 두세요.**
>
> | 항목 | 기본값 | 실습 설정 | 이유 |
> | :--- | :--- | :--- | :--- |
> | Enable Data API | ✅ 켬 | **그대로 켬** | `supabase-js`가 사용하는 PostgREST 엔드포인트입니다. 끄면 클라이언트 라이브러리 자체가 동작하지 않습니다. |
> | Automatically expose new tables | ✅ 켬 | **그대로 켬** | 끄면 마이그레이션으로 만든 테이블에 Data API 권한(GRANT)이 부여되지 않아, RLS 정책이 정확해도 `permission denied` 또는 빈 배열이 반환됩니다. |
> | Enable automatic RLS | ⬜ 끔 | **그대로 끔** | `schema.sql`이 테이블별로 `enable row level security`를 명시적으로 실행하므로 불필요합니다. |
>
> 💡 **화면의 "We recommend disabling this"를 따르지 마세요.** 그 권장은 운영 환경 기준입니다.
> 실습에서 두 번째 항목을 끄면 *"마이그레이션도 성공하고 Table Editor에 데이터도 보이는데 앱에서만 빈 화면"* 이라는
> 원인 추적이 극도로 어려운 상황이 발생합니다.
> 세 번째 항목을 켜면 이후 실습 중 새로 만드는 테이블마다 정책 없는 RLS가 자동으로 걸려 조용히 빈 결과를 반환합니다.

2. **SQL Editor**로 이동하여 다음 테이블 마이그레이션 쿼리를 실행합니다.

```sql
-- 1. 리뷰 원본 저장 테이블
create table if not exists reviews (
  id text primary key,
  rating integer not null,
  title text,
  content text not null,
  author text,
  date text,
  helpful_votes integer default 0,
  verified_purchase boolean default true,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 2. 채팅 메시지 저장 테이블
create table if not exists messages (
  id uuid default gen_random_uuid() primary key,
  chat_id text not null,
  role text not null check (role in ('user', 'assistant', 'system')),
  content text not null,
  sources jsonb,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 3. RLS 정책 활성화 및 모든 사용자 접근 허용 (실습용)
alter table reviews enable row level security;
alter table messages enable row level security;

create policy "Allow all access to reviews" on reviews for all using (true) with check (true);
create policy "Allow all access to messages" on messages for all using (true) with check (true);
```

3. 화면 상단의 **[Connect]** 버튼을 누르고 **[Framework]** 탭에서 다음과 같이 선택합니다.

   | 항목 | 값 |
   | :--- | :--- |
   | Framework | `Next.js` |
   | Variant | `App Router` |
   | Shadcn | ⬜ 끔 (본 실습은 shadcn/ui를 사용하지 않습니다) |

   아래 **[Follow these steps]** 영역의 **2. Add files ➡️ `.env.local` 탭**에 환경 변수가 그대로 나옵니다. 이를 복사합니다.

> [!IMPORTANT]
> **키 이름이 인터넷 자료나 영상과 다를 수 있습니다.** 2025년 이후 생성한 Supabase 프로젝트는 기본이 **Publishable / Secret 키** 체계입니다.
>
> | 화면에 보이는 이름 | 값 형태 | 예전 이름 |
> | :--- | :--- | :--- |
> | `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY` | `sb_publishable_...` | anon public key (`eyJ...`) |
>
> 콘솔에서 "anon key"가 안 보여도 정상입니다. **Publishable 키를 쓰면 됩니다.**
> 기존 프로젝트라 `anon` 키만 보인다면 그대로 쓰셔도 동작합니다. 아래 `.env.local`에는 두 이름을 모두 적어두었습니다.

### 2.3 환경 변수 설정 (`.env.local`)
프로젝트 루트에 `.env.local`을 작성합니다.

```env
# Claude (Anthropic - 교육장 제공 키)
ANTHROPIC_API_KEY=sk-ant-api03-xxxxxxxxxxxxxxxxxxxx

# Pinecone
PINECONE_API_KEY=pcsk_xxxxxxxxxxxxxxxxxxxx
PINECONE_INDEX_NAME=review-chatbot
PINECONE_HOST=https://review-chatbot-xxxx.svc.aped-4627-b74a.pinecone.io

# Supabase
NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co

# 신규 프로젝트(권장) — Connect 화면에서 복사
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY=sb_publishable_xxxxxxxxxxxx
# 구 프로젝트라 anon 키만 보이는 경우 이쪽을 사용
# NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOi...
```

> [!TIP]
> 코드에서는 `process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY` 로 받도록
> Claude Code에게 지시해두면 두 경우 모두 안전하게 동작합니다.

### 2.4 샘플 리뷰 데이터 배치

배포 자료의 **`samples/review.csv`(리뷰 100건)** 를 프로젝트 루트의 `samples/` 폴더에 그대로 복사합니다.

```bash
# macOS / Linux (강의 저장소를 클론한 경로는 각자 환경에 맞게 수정)
mkdir -p samples && cp ~/dev/ai_24h/day1_cursor_rag/hands_on/2_쇼핑_리뷰_분석_챗봇_만들기/samples/review.csv samples/
```

> [!TIP]
> **시간을 아끼기 위해 완성된 CSV를 제공합니다.** 리뷰 100건을 AI로 생성하면 5~10분과 상당한 토큰이 소모되고,
> 결과 품질도 매번 달라져 검색 테스트 결과가 흔들립니다.
> 데이터 생성 자체를 경험해보고 싶은 분은 아래 **[선택] 프롬프트**를 사용하세요.

<details>
<summary>💬 <b>[선택] Claude Code 프롬프트 2-1 (샘플 데이터 직접 생성)</b></summary>


> ```text
> 무선 블루투스 노이즈캔슬링 이어폰에 대한 한국어 고객 리뷰 100건을 CSV 형태로 `samples/review.csv` 파일에 만들어줘.
> 
> [컬럼 규격]
> id,rating,title,content,author,date,helpful_votes,verified_purchase
> 
> [내용 요구사항]
> 1. 별점(rating): 1점~5점까지 고르게 분포
> 2. 구체적인 구매 후기 포함:
>    - 음질(저음, 고음, 해상력)
>    - 착용감(장시간 사용 시 통증, 운동/러닝 시 고정력)
>    - 통화 품질(지하철, 길거리 바람 소리)
>    - 배터리 수명 및 충전 속도
>    - 노이즈 캔슬링 강도 및 윈드노이즈
> 3. 실제 리뷰처럼 구어체, 오타, 칭찬과 불만이 섞인 현실적인 내용으로 100행 작성해줘.
> ```

</details>

---

## 3단계: LangChain LCEL 기반 RAG 파이프라인 구축 (Code & Verify)

필요한 백엔드 패키지를 설치하고 RAG 파이프라인을 구축합니다. 이번 단계에서 만들 것은 크게 두 갈래입니다.

![diagram w:1000](assets/rag-two-phase.svg)

- **인덱싱 (3.2)**: `review.csv`를 읽어 임베딩한 뒤 Pinecone에 저장해두는, 미리 한 번만 해두는 작업
- **질의응답 (3.3)**: 사용자 질문이 들어오면 가까운 리뷰 5건을 검색하고, 그 내용을 근거로 Claude가 답하는 작업

**"인덱싱은 미리, 검색은 매 질문마다"** — 이 둘을 헷갈리면 API를 잘못된 곳에 걸게 되니 구분해서 진행하세요.

### 3.1 종속성 설치
Claude Code 대화창에서 설치를 지시하거나 터미널에서 실행합니다.

```bash
npm install @langchain/anthropic @langchain/core @pinecone-database/pinecone @supabase/supabase-js papaparse
npm install -D @types/papaparse
```

> [!WARNING]
> **`@langchain/pinecone`은 설치하지 않습니다.**
> 2.1절에서 만든 통합 임베딩 인덱스는 `PineconeStore`와 호환되지 않습니다.
> 역할을 이렇게 나눕니다:
>
> | 단계 | 담당 |
> | :--- | :--- |
> | 임베딩 + 벡터 적재/검색 | **Pinecone SDK 직접 호출** (`upsertRecords` / `searchRecords`) |
> | 프롬프트 조립 + 답변 생성 | **LangChain LCEL** (`@langchain/core` + `@langchain/anthropic`) |
>
> Claude Code가 임의로 `PineconeStore`나 `OpenAIEmbeddings`를 끌어오면 **키가 없어 401 에러로 실습이 멈춥니다.**
> 아래 프롬프트에 금지 조항이 들어 있으니 문구를 빼지 말고 그대로 붙여넣으세요.

### 3.2 샘플 데이터 인덱싱 API 구현 (`/api/index-data`)
> 💬 **Claude Code 프롬프트 3-1 (인덱싱 API)**
> ```text
> `src/app/api/index-data/route.ts`에 샘플 리뷰 데이터를 인덱싱하는 POST 라우트를 구현해줘.
> 
> [중요 제약 — 반드시 지킬 것]
> - Pinecone 인덱스 `review-chatbot`은 llama-text-embed-v2를 쓰는 "통합 임베딩(Integrated Inference)" 인덱스다.
> - 따라서 LangChain의 PineconeStore를 절대 사용하지 마라. OpenAIEmbeddings 등 외부 임베딩 라이브러리도 절대 추가하지 마라.
> - 반드시 @pinecone-database/pinecone SDK를 직접 호출하고, 텍스트를 그대로 넘겨 Pinecone이 서버에서 임베딩하게 한다.
> 
> [구현 흐름]
> 1. `samples/review.csv`를 fs.readFile로 읽어 papaparse로 파싱한다 (header: true).
> 2. Supabase `reviews` 테이블에 원본 데이터를 id 기준으로 upsert한다.
> 3. Pinecone 클라이언트를 생성한다:
>    const pc = new Pinecone({ apiKey: process.env.PINECONE_API_KEY! });
>    const ns = pc.index(process.env.PINECONE_INDEX_NAME!, process.env.PINECONE_HOST!).namespace('reviews');
> 4. 각 리뷰를 아래 레코드 형태로 변환한다. 통합 임베딩 인덱스는 `_id`와 임베딩 대상 텍스트 필드(`text`)가 필수다:
>    { _id: r.id, text: `${r.title} ${r.content}`, rating: Number(r.rating), author: r.author, title: r.title, content: r.content }
> 5. `await ns.upsertRecords(records)` 로 적재한다. 한 번에 96개 이하로 잘라서 순차 호출한다.
> 6. 성공 시 { success: true, data: { indexed: 개수 } } 형태로 반환한다. 실패 시 { success: false, error }.
> 
> UI의 [샘플 데이터 인덱싱] 버튼과 연동하여 버튼 클릭 시 이 API가 호출되도록 프론트엔드도 연결해줘.
> ```

> [!TIP]
> `upsertRecords`는 인덱스를 만들 때 지정한 **필드명(기본 `text`)** 을 임베딩 대상으로 삼습니다.
> "field not found" 계열 에러가 나면 Pinecone 콘솔의 인덱스 상세에서 실제 필드명을 확인하세요.

### 3.3 LangChain LCEL 기반 질의응답 Chat API 구현 (`/api/chat`)
> 💬 **Claude Code 프롬프트 3-2 (RAG Chat API)**
> ```text
> `src/app/api/chat/route.ts`에 사용자의 질문을 받아 RAG로 응답하는 POST 라우트를 구현해줘.
> 
> [중요 제약 — 반드시 지킬 것]
> - 검색(Retrieval)은 LangChain retriever가 아니라 Pinecone SDK의 searchRecords를 직접 호출한다.
>   (통합 임베딩 인덱스라서 PineconeStore / OpenAIEmbeddings를 쓸 수 없다.)
> - 답변 생성(Generation)만 LangChain LCEL로 구성한다.
> 
> [구현 세부사항]
> 1. 요청 본문: { query: string, chatId?: string }
> 2. Pinecone 통합 검색으로 상위 5건을 가져온다:
>    const res = await ns.searchRecords({
>      query: { topK: 5, inputs: { text: query } },
>      fields: ['title', 'content', 'rating', 'author'],
>    });
>    결과는 res.result.hits 배열이며, 각 hit은 _id / _score / fields 를 가진다.
>    _score(0~1)를 백분율로 환산해 UI에 넘길 수 있도록 그대로 보존한다.
> 3. hits를 "[리뷰 N] ★{rating} {title} — {content} (작성자: {author})" 형태의 문자열로 합쳐 context를 만든다.
> 4. LangChain Expression Language(LCEL)로 RAG 체인을 구성한다:
>    ChatPromptTemplate.fromMessages([...]) .pipe(model) .pipe(new StringOutputParser())
>    - 시스템 프롬프트:
>      "당신은 전자제품 쇼핑몰의 전문 리뷰 분석가입니다.
>       아래 제공된 [실제 구매 고객 리뷰 데이터]만을 바탕으로 사용자의 질문에 친절하고 솔직하게 답변하세요.
>       리뷰에 없는 사실을 추측하여 지어내지 마세요.
>       장점과 단점이 모두 존재한다면 균형 있게 설명하고, 관련 리뷰 작성자의 의견을 인용하세요."
>    - 모델: new ChatAnthropic({ model: "claude-haiku-4-5", apiKey: process.env.ANTHROPIC_API_KEY })
> 5. 검색된 5건의 리뷰 정보와 AI 최종 답변을 함께 JSON으로 반환한다:
>    {
>      success: true,
>      answer: string,
>      sources: Array<{ id, title, content, rating, author, score }>   // score는 hit._score
>    }
> 6. 사용자 질문과 AI 답변을 Supabase `messages` 테이블에 기록한다 (sources는 jsonb 컬럼에 저장).
> ```

### 3.4 기능 검증 및 질의 테스트
Next.js 개발 서버를 실행하고 브라우저(`http://localhost:3000`)에서 동작을 확인합니다.

1. **[샘플 데이터 인덱싱]** 버튼 클릭 ➡️ "100건 인덱싱 완료" 알림 확인
2. **질문 테스트 1**: `운동할 때 러닝머신 뛰면서 써도 귀에서 잘 안 빠지나요?`
   - *검증*: 러닝/운동 관련 키워드가 포함된 리뷰 내용이 근거로 제시되는지 확인.
3. **질문 테스트 2**: `통화 품질에 대한 사용자들의 솔직한 평가는 어떤가요?`
   - *검증*: 조용한 곳 vs 지하철/바람 부는 곳에서의 통화 품질 차이를 구분하여 요약하는지 확인.

---

### 3.5 💡 [Advanced 도파민] Claude Code에게 DB 저장 결과를 직접 검증시키기

화면에 답변이 잘 나왔다고 해서 **대화 기록이 DB에 제대로 쌓였는지는 알 수 없습니다.**
보통은 Supabase 웹 콘솔을 열어 Table Editor에서 눈으로 확인하겠지만,
**터미널을 벗어나지 않고 Claude Code에게 검증까지 맡겨보겠습니다.**

> 💬 **Claude Code 프롬프트 3-3 (DB 저장 셀프 검증)**
> ```text
> 방금 브라우저에서 나눈 대화가 Supabase의 messages 테이블에 제대로 저장됐는지 네가 직접 확인해줘.
> 
> [확인 항목]
> 1. messages 테이블의 전체 행 수와 가장 최근 chat_id
> 2. 해당 chat_id의 메시지가 user / assistant 쌍으로 순서대로 저장됐는지
> 3. assistant 메시지의 sources 컬럼에 참고 리뷰 5건이 JSON 배열로 들어있는지
>    (각 항목에 id, title, author, rating, score가 모두 있는지)
> 4. created_at 타임스탬프가 정상인지
> 
> 확인 방법은 네가 판단해서 진행하고, 결과를 표로 정리해서 보여줘.
> .env.local에 Supabase 접속 정보가 있어.
> ```

**무슨 일이 벌어지나요?**
Claude Code는 이 요청을 받고 스스로 검증 수단을 고릅니다. 대개 다음 중 하나로 진행됩니다.

- `npx supabase` CLI를 **직접 설치**하고 프로젝트에 연결해 쿼리 실행
- `.env.local`의 키를 읽어 `@supabase/supabase-js`로 **일회성 조회 스크립트를 작성 후 실행**
- 이미 Supabase MCP를 붙여둔 경우 MCP 도구로 조회

> [!TIP]
> 중간에 **설치 승인이나 명령 실행 허용을 묻는 프롬프트**가 뜨면 승인해 주세요.
> "AI가 필요한 도구를 스스로 설치해서, 스스로 검증한다"는 것이 이 실습의 핵심 감상 포인트입니다.
> 개발자가 웹 콘솔과 터미널을 왔다 갔다 할 필요가 없어지는 워크플로우를 직접 체감할 수 있습니다.

**기대 결과 (예시)**

```text
┌──────────────┬───────────────────────────────────────────────────────┐
│ 항목         │ 결과                                                  │
├──────────────┼───────────────────────────────────────────────────────┤
│ 총 메시지 수 │ 4건 (user 2 / assistant 2)                            │
├──────────────┼───────────────────────────────────────────────────────┤
│ 최근 chat_id │ chat-1788155922768                                    │
├──────────────┼───────────────────────────────────────────────────────┤
│ Sources 저장 │ ✅ 5개의 리뷰 정보 (id, title, author, rating, score) │
├──────────────┼───────────────────────────────────────────────────────┤
│ 타임스탬프   │ 2026-08-31 06:06:49                                   │
└──────────────┴───────────────────────────────────────────────────────┘

저장된 구조:
messages 테이블
├── id: UUID
├── chat_id: "chat-1788155922768"
├── role: "user" | "assistant"
├── content: 메시지 내용
├── sources: [리뷰 객체들] (assistant만 해당)
└── created_at: 타임스탬프
```

> [!WARNING]
> **`sources`가 `null`로 저장돼 있다면** `/api/chat`에서 검색 결과를 `messages` 테이블에 기록하지 않은 것입니다.
> 아래처럼 범위를 좁혀 수정을 요청하세요.
> > "`src/app/api/chat/route.ts`에서 assistant 메시지를 저장할 때 `sources`를 jsonb 컬럼에 함께 넣도록 수정해줘."
>
> **행이 아예 0건이라면** RLS 정책 문제일 가능성이 높습니다. 부록 FAQ의 **Q2**를 참고하세요.

---

## 4단계: 실전 트러블슈팅 & Claude Code 셀프 디버깅

현업에서 가장 빈번하게 발생하는 이슈 2가지를 Claude Code를 통해 능동적으로 해결해 봅니다.

### 4.1 한글 IME 중복 입력 버그 해결
> ⚠️ **현상**: 한글 입력 후 Enter 키를 치면 메시지가 2번 연속 전송되는 브라우저 IME 조합 이슈

> 💬 **Claude Code 프롬프트 4-1 (버그 픽스)**
> ```text
> 채팅 입력창에서 한글을 입력하고 Enter를 누르면 메시지가 두 번 전송되는 버그가 있어.
> 키보드 이벤트의 `e.nativeEvent.isComposing` 상태를 확인해서 한글 조립 중(isComposing === true)일 때는 Enter 이벤트가 발생해도 전송되지 않도록 입력 컴포넌트를 수정해줘.
> 수정 후 git diff로 변경 사항을 확인해줘.
> ```

### 4.2 답변 신뢰도 향상을 위한 "참고 리뷰 카드" UI 고도화
> 💬 **Claude Code 프롬프트 4-2 (UI 고도화)**
> ```text
> AI 답변 아래에 표시되는 `sources`(참고 리뷰)를 더 직관적인 카드로 개선해줘.
> - 별점(★ 1~5)을 노란색 별 아이콘으로 시각화
> - 작성자명과 날짜를 메타 태그로 표시
> - 리뷰 원문 내용이 길 경우 2줄 말줄임(line-clamp-2) 처리하고 클릭 시 전체 펼쳐보기 기능 추가
> - 유사도 점수(Relevance Score)를 백분율 배지(예: 89% 일치)로 표시
> ```

### 4.3 Claude Code로 깔끔한 작업 단위 커밋 남기기
```bash
git add .
git status
```
> 💬 **Claude Code 프롬프트 4-3 (Git Commit)**
> ```text
> 지금까지 구현한 쇼핑 리뷰 분석 RAG 챗봇 기능에 대해 Conventional Commits 규칙에 맞게 한국어로 명확한 커밋 메시지를 작성해서 커밋을 완료해줘.
> ```

---

## 5단계: 개인 미션 (Self-Practice Challenge)

따라하기 실습이 끝난 후, 본인의 속도에 맞춰 아래 미션을 수행합니다.

### 🥉 [기본 미션] 긍정/부정 감성 필터 및 별점 필터 추가 (소요 시간: 30분)
- **요구사항**:
  1. 채팅창 상단에 `[전체 리뷰]`, `[긍정 리뷰 (4~5점)]`, `[부정 리뷰 (1~2점)]` 필터 칩 추가.
  2. 필터 선택 시 `searchRecords`의 메타데이터 필터를 적용하여 특정 관점의 리뷰만 집중 분석하도록 구현.
     ```ts
     query: { topK: 5, inputs: { text: query }, filter: { rating: { $gte: 4 } } }
     ```
- **Claude Code 힌트 프롬프트**:
  > "`/api/chat`의 `searchRecords` 호출에 rating 메타데이터 필터를 옵션으로 넘길 수 있도록 API와 프론트엔드 필터 칩을 확장해줘. PineconeStore는 쓰지 마."

### 🥇 [심화 미션] 다차원 비교 분석 리포트 생성 및 다운로드 (소요 시간: 40분)
- **요구사항**:
  1. 채팅창 우측 상단에 **[종합 분석 리포트 생성]** 버튼 추가.
  2. 버튼 클릭 시 전체 리뷰 100건을 대상으로 5대 핵심 항목(음질, 착용감, 배터리, 통화품질, 가성비)에 대한 정량적 점수(5점 만점)와 요약 총평을 생성.
  3. 생성된 리포트를 Markdown 파일 또는 인쇄(PDF) 가능한 모달로 제공.

---

## 🚀 3일차 해커톤 브릿지 (생각해보기)

내일 진행될 해커톤에서는 이 RAG 파이프라인을 여러분이 원하는 비즈니스 도메인으로 확장할 수 있습니다.

- 🏢 **사내 규정/업무 매뉴얼 Q&A 챗봇**: 신규 입사자를 위한 사내 위키 RAG
- ⚖️ **법률/약관 독소조항 분석기**: 복잡한 서비스 이용약관 및 계약서 비교 분석
- 📚 **기술 공식 문서 어시스턴트**: Next.js, Flutter 등 특정 프레임워크 전용 질의 봇

---