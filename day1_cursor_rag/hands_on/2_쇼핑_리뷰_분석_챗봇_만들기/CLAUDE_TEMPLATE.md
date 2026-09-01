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
