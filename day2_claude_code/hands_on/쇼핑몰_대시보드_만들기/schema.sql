-- ==============================================================================
-- [Day 2] 쇼핑몰 관리자 대시보드 통합 마이그레이션 SQL (schema.sql)
-- 데이터베이스: Supabase PostgreSQL
-- 구성: 스키마 생성, RLS 정책, Storage 버킷 생성, 시드 데이터
-- ==============================================================================

-- 1. 확장 기능
-- gen_random_uuid()는 PostgreSQL 13+ 내장 함수이므로 별도 확장이 필요 없습니다.
-- (uuid-ossp는 사용하지 않습니다.)

-- 2. 사용자 프로필 테이블 (auth.users와 1:1 연동)
create table if not exists public.users (
  id uuid references auth.users(id) on delete cascade primary key,
  email text unique not null,
  role text not null default 'customer' check (role in ('admin', 'customer')),
  name text,
  phone text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 3. 상품 테이블
create table if not exists public.products (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  description text,
  price numeric not null check (price >= 0),
  stock integer not null default 0 check (stock >= 0),
  category text not null,
  image_url text,
  status text not null default 'active' check (status in ('active', 'out_of_stock', 'discontinued')),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 4. 고객 통계/프로필 테이블
create table if not exists public.customers (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  email text unique not null,
  phone text,
  total_orders integer default 0,
  total_spent numeric default 0,
  is_vip boolean default false,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 5. 주문 테이블
create table if not exists public.orders (
  id uuid default gen_random_uuid() primary key,
  order_number text unique not null,
  customer_id uuid references public.customers(id) on delete set null,
  customer_name text not null,
  customer_email text not null,
  total_amount numeric not null check (total_amount >= 0),
  status text not null default 'payment_pending' check (
    status in ('payment_pending', 'payment_completed', 'preparing', 'shipping', 'delivered', 'cancelled')
  ),
  shipping_address text not null,
  shipping_carrier text,
  tracking_number text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 6. 주문 항목 테이블
create table if not exists public.order_items (
  id uuid default gen_random_uuid() primary key,
  order_id uuid references public.orders(id) on delete cascade not null,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  unit_price numeric not null,
  quantity integer not null check (quantity > 0),
  total_price numeric not null
);

-- ==============================================================================
-- 7. Row Level Security (RLS) 보안 정책
-- ==============================================================================

alter table public.users enable row level security;
alter table public.products enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

-- 헬퍼 함수: 관리자 권한 확인
-- security definer + 고정 search_path: RLS 재귀를 피하고 스키마 하이재킹을 방지합니다.
create or replace function public.is_admin()
returns boolean as $$
begin
  return exists (
    select 1 from public.users
    where id = auth.uid() and role = 'admin'
  );
end;
$$ language plpgsql security definer set search_path = public;

-- [users] RLS 정책
create policy "사용자는 본인 프로필 조회 가능"
  on public.users for select using (auth.uid() = id or public.is_admin());

create policy "관리자는 전체 사용자 관리 가능"
  on public.users for all using (public.is_admin());

-- [products] RLS 정책: 누구나 조회 가능, 관리자만 등록/수정/삭제
create policy "상품 조회는 누구나 가능"
  on public.products for select using (true);

create policy "상품 관리는 관리자만 가능"
  on public.products for all using (public.is_admin());

-- [customers, orders, order_items] RLS 정책: 관리자 전용
create policy "고객 정보 관리는 관리자만 가능"
  on public.customers for all using (public.is_admin());

create policy "주문 목록 관리는 관리자만 가능"
  on public.orders for all using (public.is_admin());

create policy "주문 상세 항목 관리는 관리자만 가능"
  on public.order_items for all using (public.is_admin());

-- ==============================================================================
-- 8. Supabase Storage 버킷 생성 및 RLS 정책
-- ==============================================================================

-- 상품 이미지 저장소 버킷 생성
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

-- 누구나 이미지 다운로드/조회 가능 (Public Read)
create policy "상품 이미지는 누구나 조회 가능"
  on storage.objects for select
  using (bucket_id = 'product-images');

-- 관리자만 이미지 업로드 가능
create policy "관리자만 상품 이미지 업로드 가능"
  on storage.objects for insert
  with check (
    bucket_id = 'product-images'
    and (public.is_admin() or auth.role() = 'authenticated')
  );

-- 관리자만 상품 이미지 수정 가능 (이미지 교체 시 필요)
create policy "관리자만 상품 이미지 수정 가능"
  on storage.objects for update
  using (
    bucket_id = 'product-images'
    and (public.is_admin() or auth.role() = 'authenticated')
  )
  with check (
    bucket_id = 'product-images'
    and (public.is_admin() or auth.role() = 'authenticated')
  );

-- 관리자만 상품 이미지 삭제 가능
create policy "관리자만 상품 이미지 삭제 가능"
  on storage.objects for delete
  using (
    bucket_id = 'product-images'
    and (public.is_admin() or auth.role() = 'authenticated')
  );

-- ==============================================================================
-- 9. 신규 회원가입 시 public.users 동기화 트리거
-- ==============================================================================

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, email, role, name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'role', 'customer'),
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ==============================================================================
-- 10. 테스트용 시드(Mock) 데이터 주입
--   대시보드의 KPI 카드, 주간 매출 추이(AreaChart), 카테고리별 판매 비율(PieChart),
--   베스트셀러 TOP 5, 주문 상세 화면이 모두 "그럴듯하게" 보이도록 충분한 양을 넣습니다.
-- ==============================================================================

-- 10-1. 상품 더미 데이터 (10건 / 5개 카테고리)
insert into public.products (id, name, description, price, stock, category, status) values
  ('11111111-1111-1111-1111-111111111111', '프리미엄 기계식 키보드', '부드러운 타건감의 무접점 스위치', 189000, 35, '전자제품', 'active'),
  ('22222222-2222-2222-2222-222222222222', '클린 아키텍처 머그컵', '개발자 전용 세라믹 머그컵 450ml', 18000, 120, '생활용품', 'active'),
  ('33333333-3333-3333-3333-333333333333', '노이즈 캔슬링 무선 헤드폰', '몰입감 넘치는 사운드와 강력한 ANC', 299000, 4, '전자제품', 'active'),
  ('44444444-4444-4444-4444-444444444444', '오버핏 데님 자켓', '트렌디한 워싱 데님 자켓', 89000, 0, '의류', 'out_of_stock'),
  ('55555555-5555-5555-5555-555555555555', '수분 진정 크림 50ml', '민감성 피부를 위한 촉촉한 크림', 32000, 58, '화장품', 'active'),
  ('66666666-6666-6666-6666-666666666666', '4K 웹캠 프로', '화상회의용 오토포커스 웹캠', 129000, 22, '전자제품', 'active'),
  ('77777777-7777-7777-7777-777777777777', '유기농 드립백 커피 30개입', '싱글 오리진 원두 드립백', 24000, 3, '식품', 'active'),
  ('88888888-8888-8888-8888-888888888888', '캐시미어 혼방 니트', '가볍고 따뜻한 데일리 니트', 79000, 41, '의류', 'active'),
  ('99999999-9999-9999-9999-999999999999', '스테인리스 텀블러 500ml', '보온보냉 12시간 지속', 26000, 87, '생활용품', 'active'),
  ('aaaa0000-0000-0000-0000-00000000000a', '비타민C 브라이트닝 세럼', '피부 톤 개선 앰플 30ml', 45000, 2, '화장품', 'active')
on conflict (id) do nothing;

-- 10-2. 고객 더미 데이터 (12건)
insert into public.customers (id, name, email, phone, total_orders, total_spent, is_vip) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '김철수', 'customer1@example.com', '010-1234-5678', 0, 0, false),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '이영희', 'customer2@example.com', '010-2345-6789', 0, 0, false),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '박지성', 'customer3@example.com', '010-3456-7890', 0, 0, false),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '최유리', 'customer4@example.com', '010-4567-8901', 0, 0, false),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '정민호', 'customer5@example.com', '010-5678-9012', 0, 0, false),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', '한소희', 'customer6@example.com', '010-6789-0123', 0, 0, false),
  ('a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', '오준석', 'customer7@example.com', '010-7890-1234', 0, 0, false),
  ('b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', '윤서연', 'customer8@example.com', '010-8901-2345', 0, 0, false),
  ('c3c3c3c3-c3c3-c3c3-c3c3-c3c3c3c3c3c3', '장하늘', 'customer9@example.com', '010-9012-3456', 0, 0, false),
  ('d4d4d4d4-d4d4-d4d4-d4d4-d4d4d4d4d4d4', '임도현', 'customer10@example.com', '010-0123-4567', 0, 0, false),
  ('e5e5e5e5-e5e5-e5e5-e5e5-e5e5e5e5e5e5', '신아름', 'customer11@example.com', '010-1122-3344', 0, 0, false),
  ('f6f6f6f6-f6f6-f6f6-f6f6-f6f6f6f6f6f6', '배준영', 'customer12@example.com', '010-2233-4455', 0, 0, false)
on conflict (id) do nothing;

-- 10-3. 주문 60건을 최근 90일에 걸쳐 랜덤 생성
--   * 이미 주문이 10건 이상 있으면 건너뜁니다 (db push 재실행 시 중복 방지)
do $$
declare
  v_addresses text[] := array[
    '서울특별시 강남구 테헤란로 123',
    '경기도 성남시 분당구 판교역로 45',
    '인천광역시 연수구 송도과학로 78',
    '부산광역시 해운대구 센텀중앙로 90',
    '대전광역시 유성구 대학로 291',
    '광주광역시 서구 상무중앙로 58',
    '대구광역시 수성구 동대구로 349',
    '제주특별자치도 제주시 첨단로 242'
  ];
  v_statuses text[] := array[
    'delivered','delivered','delivered','delivered',
    'shipping','shipping','preparing','preparing',
    'payment_completed','payment_completed','payment_pending','cancelled'
  ];
begin
  if (select count(*) from public.orders) >= 10 then
    raise notice '주문 시드 데이터가 이미 존재하여 건너뜁니다.';
    return;
  end if;

  -- (1) 주문 헤더 생성 (금액은 0으로 두고 3단계에서 합계로 갱신)
  insert into public.orders (
    order_number, customer_id, customer_name, customer_email,
    total_amount, status, shipping_address, shipping_carrier, tracking_number, created_at
  )
  select
    'ORD-2026-' || lpad(g::text, 4, '0'),
    c.id, c.name, c.email,
    0,
    v_statuses[1 + floor(random() * array_length(v_statuses, 1))::int],
    v_addresses[1 + floor(random() * array_length(v_addresses, 1))::int],
    null, null,
    now() - (random() * interval '90 days')
  from generate_series(1, 60) as g
  cross join lateral (
    select id, name, email from public.customers order by random() limit 1
  ) as c;

  -- (2) 주문별 상품 1~3종을 랜덤으로 담기
  insert into public.order_items (order_id, product_id, product_name, unit_price, quantity, total_price)
  select
    o.id, p.id, p.name, p.price, q.qty, p.price * q.qty
  from public.orders o
  cross join lateral (
    select id, name, price from public.products
    order by random()
    limit (1 + floor(random() * 3)::int)
  ) as p
  cross join lateral (
    select (1 + floor(random() * 2)::int) as qty
  ) as q;

  -- (3) 주문 총액을 항목 합계로 갱신
  update public.orders o
  set total_amount = agg.sum_total
  from (
    select order_id, sum(total_price) as sum_total
    from public.order_items
    group by order_id
  ) as agg
  where o.id = agg.order_id;

  -- (4) 배송중/배송완료 주문에는 택배사와 운송장 번호 부여
  update public.orders
  set shipping_carrier = (array['CJ대한통운','한진택배','롯데택배','우체국택배'])[1 + floor(random() * 4)::int],
      tracking_number  = lpad(floor(random() * 1000000000000)::bigint::text, 12, '0')
  where status in ('shipping', 'delivered');

  -- (5) 고객 집계 컬럼 갱신 (취소 주문 제외) + 누적 50만원 이상은 VIP
  update public.customers c
  set total_orders = coalesce(agg.cnt, 0),
      total_spent  = coalesce(agg.amount, 0),
      is_vip       = coalesce(agg.amount, 0) >= 500000
  from (
    select customer_id, count(*) as cnt, sum(total_amount) as amount
    from public.orders
    where status <> 'cancelled'
    group by customer_id
  ) as agg
  where c.id = agg.customer_id;

  raise notice '주문 60건 및 주문 항목 시드 데이터를 생성했습니다.';
end $$;

-- ==============================================================================
-- 11. ⚠️ [필수] 관리자 계정 생성 및 권한 부여
-- ==============================================================================
--
-- 이 마이그레이션만 실행하면 대시보드가 "전부 빈 화면"으로 보입니다.
-- 위 7번 RLS 정책이 users/customers/orders/order_items 조회를 관리자에게만 허용하는데,
-- 9번 트리거는 신규 가입자를 무조건 role='customer'로 넣기 때문입니다.
-- 아래 두 단계를 반드시 수행하세요.
--
-- [1단계] Supabase 대시보드 > Authentication > Users > [Add user] > [Create new user]
--         - Email:    admin@shop.com
--         - Password: admin1234!
--         - "Auto Confirm User" 체크 (이메일 인증 생략)
--
-- [2단계] SQL Editor에서 아래 쿼리를 실행하여 role을 admin으로 승격
--
--   update public.users set role = 'admin' where email = 'admin@shop.com';
--
-- [확인] 아래 쿼리가 1행을 반환하면 정상입니다.
--
--   select id, email, role from public.users where role = 'admin';
--
-- 💡 팁: 가입 시 metadata에 role을 넣으면 9번 트리거가 자동으로 admin으로 만들어 줍니다.
--        (Add user 화면의 "User Metadata"에 {"role": "admin"} 입력)
-- ==============================================================================
