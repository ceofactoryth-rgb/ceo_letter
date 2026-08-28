-- ==========================================================
-- ระบบพิมพ์ซองจดหมาย - Database Schema (Supabase / PostgreSQL)
-- ==========================================================
-- วิธีใช้: เปิดโปรเจกต์ Supabase -> เมนู "SQL Editor" -> วางโค้ดนี้ทั้งหมด -> กด Run

-- ตารางเก็บที่อยู่ผู้รับ
create table if not exists public.recipients (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,           -- ชื่อผู้รับ / บริษัทผู้รับ
  address     text not null,           -- ที่อยู่ผู้รับ (หลายบรรทัดได้)
  phone       text,                    -- เบอร์โทร (ไม่บังคับ)
  note        text,                    -- หมายเหตุ (ไม่บังคับ)
  doc_type    text,                    -- ประเภทเอกสาร (ไม่บังคับ) เช่น "ใบแจ้งหนี้"
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- สำหรับฐานข้อมูลที่เคยรัน schema.sql เวอร์ชันเก่าไปแล้ว (ยังไม่มีคอลัมน์ doc_type)
-- คำสั่งนี้จะเพิ่มคอลัมน์ให้โดยไม่กระทบข้อมูลเดิม รันซ้ำได้อย่างปลอดภัย
alter table public.recipients add column if not exists doc_type text;

-- index สำหรับค้นหาชื่อ/ที่อยู่ให้เร็วขึ้น
create index if not exists recipients_name_idx on public.recipients using gin (to_tsvector('simple', name));
create index if not exists recipients_search_idx on public.recipients using gin (
  to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(address,'') || ' ' || coalesce(phone,''))
);

-- trigger อัปเดต updated_at อัตโนมัติ
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_recipients_updated_at on public.recipients;
create trigger trg_recipients_updated_at
before update on public.recipients
for each row execute function public.set_updated_at();

-- เปิด Row Level Security
alter table public.recipients enable row level security;

-- นโยบายเปิดสิทธิ์แบบสาธารณะ (ใช้กับ anon key)
-- ⚠️ หมายเหตุความปลอดภัย: นโยบายนี้อนุญาตให้ใครก็ตามที่มี anon key
-- อ่าน/เพิ่ม/แก้ไข/ลบข้อมูลได้ทั้งหมด เหมาะสำหรับเครื่องมือใช้งานภายในบริษัท
-- (internal tool) เท่านั้น หากต้องการความปลอดภัยสูงขึ้น ให้เพิ่มระบบ
-- Supabase Auth และปรับเงื่อนไข policy ให้ตรวจสอบ auth.uid()
drop policy if exists "public access" on public.recipients;
create policy "public access"
  on public.recipients
  for all
  using (true)
  with check (true);

-- ==========================================================
-- ตารางบันทึกประวัติการพิมพ์ (Print Log)
-- ==========================================================
-- บันทึก 1 แถวต่อ "ซองที่พิมพ์" 1 ใบ (พิมพ์ทีละหลายใบ = หลายแถว
-- ที่มี print_mode='batch' และ batch_size เท่ากันทุกแถวในชุดเดียวกัน)
create table if not exists public.print_logs (
  id                 uuid primary key default gen_random_uuid(),
  recipient_id       uuid references public.recipients(id) on delete set null,
  recipient_name     text not null,
  recipient_address  text not null,
  recipient_phone    text,
  print_mode         text not null default 'single',  -- 'single' หรือ 'batch'
  batch_size         int  not null default 1,          -- จำนวนซองในชุดพิมพ์นั้น
  printed_at         timestamptz not null default now()
);

-- index สำหรับกรองตามวันที่ให้เร็วขึ้น
create index if not exists print_logs_printed_at_idx on public.print_logs (printed_at desc);

alter table public.print_logs enable row level security;

-- ใช้ policy สาธารณะแบบเดียวกับตาราง recipients (เหมาะกับ internal tool เท่านั้น)
drop policy if exists "public access" on public.print_logs;
create policy "public access"
  on public.print_logs
  for all
  using (true)
  with check (true);
