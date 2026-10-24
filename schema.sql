-- Lee's Powder & Polish: bookings + team roles. Run once in Supabase SQL Editor.
-- Roles: pending (just signed up), viewer (read bookings), staff (read + update status), admin (everything + manage team), rejected.

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null, phone text, service text, date date, time text, notes text,
  status text not null default 'new'
);
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text, name text,
  role text not null default 'pending' check (role in ('pending','viewer','staff','admin','rejected')),
  see_phone boolean not null default false,
  see_notes boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.bookings enable row level security;
alter table public.profiles enable row level security;

-- Returns the signed-in user's role (security definer avoids policy recursion)
create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as
$$ select role from public.profiles where id = auth.uid() $$;

-- Every new sign-up gets a profile. The two founding admin emails become admin automatically; everyone else is pending.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, name, role)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'name',''),
    case when lower(new.email) in ('lindasmithrose120@gmail.com','fawaazmahama@gmail.com') then 'admin' else 'pending' end);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Make this file safe to run again
drop policy if exists "Read own or admin" on public.profiles;
drop policy if exists "Admin sets roles" on public.profiles;
drop policy if exists "Admin removes people" on public.profiles;

-- Clear any older policies
drop policy if exists "Anyone can book" on public.bookings;
drop policy if exists "Admin can read" on public.bookings;
drop policy if exists "Admin can update" on public.bookings;
drop policy if exists "Admin can delete" on public.bookings;

-- Bookings
create policy "Anyone can book" on public.bookings for insert to anon with check (status = 'new');
create policy "Team can read" on public.bookings for select to authenticated using (public.my_role() in ('viewer','staff','admin'));
create policy "Staff can update" on public.bookings for update to authenticated using (public.my_role() in ('staff','admin')) with check (public.my_role() in ('staff','admin'));
create policy "Admin can delete" on public.bookings for delete to authenticated using (public.my_role() = 'admin');

-- Profiles: you see your own row; admins see and manage everyone. Nobody can change their own role.
create policy "Read own or admin" on public.profiles for select to authenticated using (id = auth.uid() or public.my_role() = 'admin');
create policy "Admin sets roles" on public.profiles for update to authenticated using (public.my_role() = 'admin') with check (public.my_role() = 'admin');
create policy "Admin removes people" on public.profiles for delete to authenticated using (public.my_role() = 'admin');

-- Extra columns if profiles already existed from the earlier version
alter table public.profiles add column if not exists see_phone boolean not null default false;
alter table public.profiles add column if not exists see_notes boolean not null default false;

-- Team members never read the bookings table directly. They read this view, which hides
-- phone numbers and notes unless an admin switched them on for that person (admins always see all).
create or replace view public.team_bookings as
select b.id, b.created_at, b.name, b.service, b.date, b.time, b.status,
  case when p.role = 'admin' or p.see_phone then b.phone end as phone,
  case when p.role = 'admin' or p.see_notes then b.notes end as notes
from public.bookings b
join public.profiles p on p.id = auth.uid() and p.role in ('viewer','staff','admin');

drop policy if exists "Team can read" on public.bookings;
drop policy if exists "Staff can update" on public.bookings;
drop policy if exists "Admin can delete" on public.bookings;
revoke select, update, delete on public.bookings from anon, authenticated;
grant insert on public.bookings to anon;
grant select on public.team_bookings to authenticated;

create or replace function public.set_booking_status(bid uuid, s text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.my_role() not in ('staff','admin') or s not in ('new','confirmed','done','cancelled') then
    raise exception 'not allowed';
  end if;
  update public.bookings set status = s where id = bid;
end $$;

create or replace function public.delete_booking(bid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.my_role() <> 'admin' then raise exception 'not allowed'; end if;
  delete from public.bookings where id = bid;
end $$;

revoke execute on function public.set_booking_status(uuid,text), public.delete_booking(uuid) from public, anon;
grant execute on function public.set_booking_status(uuid,text), public.delete_booking(uuid) to authenticated;

-- Site settings (opening hours, WhatsApp number, address). Public can read; only admins can change.
create table if not exists public.settings (key text primary key, value text not null);
alter table public.settings enable row level security;
drop policy if exists "Anyone reads settings" on public.settings;
drop policy if exists "Admin adds settings" on public.settings;
drop policy if exists "Admin edits settings" on public.settings;
create policy "Anyone reads settings" on public.settings for select to anon, authenticated using (true);
create policy "Admin adds settings" on public.settings for insert to authenticated with check (public.my_role() = 'admin');
create policy "Admin edits settings" on public.settings for update to authenticated using (public.my_role() = 'admin') with check (public.my_role() = 'admin');
insert into public.settings (key, value) values
  ('whatsapp','0596139168'), ('hours','Mon to Sun, 8am to 10pm'), ('address','ATU campus, Accra')
on conflict (key) do nothing;

-- Structured opening hours and email, so the booking time picker follows them
insert into public.settings (key, value) values
  ('email','lindasmithrose120@gmail.com'), ('days','Mon to Sun'), ('open','08:00'), ('close','22:00')
on conflict (key) do nothing;

-- Products shop: Lee manages these in the admin page. Photos live in a public storage bucket.
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null, description text, price text, image_path text,
  active boolean not null default true
);
alter table public.products enable row level security;
drop policy if exists "Public reads products" on public.products;
drop policy if exists "Admin adds products" on public.products;
drop policy if exists "Admin edits products" on public.products;
drop policy if exists "Admin removes products" on public.products;
create policy "Public reads products" on public.products for select to anon, authenticated using (active or public.my_role() = 'admin');
create policy "Admin adds products" on public.products for insert to authenticated with check (public.my_role() = 'admin');
create policy "Admin edits products" on public.products for update to authenticated using (public.my_role() = 'admin') with check (public.my_role() = 'admin');
create policy "Admin removes products" on public.products for delete to authenticated using (public.my_role() = 'admin');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images','product-images', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
drop policy if exists "Public views product images" on storage.objects;
drop policy if exists "Admin uploads product images" on storage.objects;
drop policy if exists "Admin edits product images" on storage.objects;
drop policy if exists "Admin deletes product images" on storage.objects;
create policy "Public views product images" on storage.objects for select to anon, authenticated using (bucket_id = 'product-images');
create policy "Admin uploads product images" on storage.objects for insert to authenticated with check (bucket_id = 'product-images' and public.my_role() = 'admin');
create policy "Admin edits product images" on storage.objects for update to authenticated using (bucket_id = 'product-images' and public.my_role() = 'admin');
create policy "Admin deletes product images" on storage.objects for delete to authenticated using (bucket_id = 'product-images' and public.my_role() = 'admin');

-- Services (with prices) and gallery photos, managed by admins
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null, description text, price text,
  sort int not null default 0, active boolean not null default true
);
create table if not exists public.gallery (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  image_path text not null, active boolean not null default true
);
alter table public.services enable row level security;
alter table public.gallery enable row level security;
drop policy if exists "Public reads services" on public.services;
drop policy if exists "Admin writes services" on public.services;
drop policy if exists "Admin adds services" on public.services;
drop policy if exists "Admin edits services" on public.services;
drop policy if exists "Admin removes services" on public.services;
create policy "Public reads services" on public.services for select to anon, authenticated using (active or public.my_role() = 'admin');
create policy "Admin adds services" on public.services for insert to authenticated with check (public.my_role() = 'admin');
create policy "Admin edits services" on public.services for update to authenticated using (public.my_role() = 'admin') with check (public.my_role() = 'admin');
create policy "Admin removes services" on public.services for delete to authenticated using (public.my_role() = 'admin');
drop policy if exists "Public reads gallery" on public.gallery;
drop policy if exists "Admin adds gallery" on public.gallery;
drop policy if exists "Admin removes gallery" on public.gallery;
create policy "Public reads gallery" on public.gallery for select to anon, authenticated using (active or public.my_role() = 'admin');
create policy "Admin adds gallery" on public.gallery for insert to authenticated with check (public.my_role() = 'admin');
create policy "Admin removes gallery" on public.gallery for delete to authenticated using (public.my_role() = 'admin');
-- Starter services (no prices yet). Only added if the table is empty.
insert into public.services (name, description, sort)
select v.n, v.d, v.s from (values
  ('Acrylic nails','Your shape, length and colour',1),
  ('Press-on nails','Quick, neat and ready the same visit',2),
  ('Cluster lashes','Light, natural or full volume',3),
  ('Pedicure','Clean-up, shaping and polish',4),
  ('Makeup','Everyday, events and photos',5)) as v(n,d,s)
where not exists (select 1 from public.services);

-- Editable page wording
insert into public.settings (key, value) values
  ('home_headline','Nails that look like you.'),
  ('home_intro','Nails, lashes, pedicures, makeup and skincare at ATU campus, Accra. Walk in sure of what you’ll get, at a price you can afford.'),
  ('about_text','We started last year with a simple promise: you get exactly what you asked for, and it stays affordable. We serve beauty lovers around ATU campus with nails, lashes, pedicures, makeup and skincare.')
on conflict (key) do nothing;

-- Hardening: the public site key can only do what is listed here
revoke all on public.team_bookings from anon;
alter table public.bookings drop constraint if exists bookings_length_check;
alter table public.bookings add constraint bookings_length_check check (
  char_length(name) between 1 and 100 and char_length(coalesce(phone,'')) <= 30 and
  char_length(coalesce(service,'')) <= 60 and char_length(coalesce(notes,'')) <= 500 and char_length(coalesce(time,'')) <= 10);

-- Testimonials: customers submit (pending), Lee approves. Only approved ones are public.
create table if not exists public.testimonials (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null, quote text not null, rating int not null default 5,
  image_path text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  source text not null default 'customer' check (source in ('customer','admin')),
  constraint testimonials_len check (char_length(name) between 1 and 60 and char_length(quote) between 5 and 400 and rating between 1 and 5)
);
alter table public.testimonials enable row level security;
drop policy if exists "Public reads approved testimonials" on public.testimonials;
drop policy if exists "Customers submit testimonials" on public.testimonials;
drop policy if exists "Admin adds testimonials" on public.testimonials;
drop policy if exists "Admin edits testimonials" on public.testimonials;
drop policy if exists "Admin removes testimonials" on public.testimonials;
create policy "Public reads approved testimonials" on public.testimonials for select to anon, authenticated using (status = 'approved' or public.my_role() = 'admin');
create policy "Customers submit testimonials" on public.testimonials for insert to anon with check (status = 'pending' and source = 'customer' and image_path is null);
create policy "Admin adds testimonials" on public.testimonials for insert to authenticated with check (public.my_role() = 'admin');
create policy "Admin edits testimonials" on public.testimonials for update to authenticated using (public.my_role() = 'admin') with check (public.my_role() = 'admin');
create policy "Admin removes testimonials" on public.testimonials for delete to authenticated using (public.my_role() = 'admin');

-- Customer photos on reviews: stored in their own bucket, hidden from the public until the review is approved
alter table public.testimonials add column if not exists image_bucket text not null default 'product-images';
drop policy if exists "Customers submit testimonials" on public.testimonials;
create policy "Customers submit testimonials" on public.testimonials for insert to anon with check (
  status = 'pending' and source = 'customer' and (
    image_path is null or (image_bucket = 'review-photos' and image_path ~ '^r-[a-z0-9-]{10,60}[.]jpg$')));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('review-photos','review-photos', true, 1048576, array['image/jpeg'])
on conflict (id) do nothing;
drop policy if exists "Customers upload review photos" on storage.objects;
drop policy if exists "Admin views review photos" on storage.objects;
drop policy if exists "Admin deletes review photos" on storage.objects;
create policy "Customers upload review photos" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'review-photos' and name ~ '^r-[a-z0-9-]{10,60}[.]jpg$');
create policy "Admin views review photos" on storage.objects for select to authenticated using (bucket_id = 'review-photos' and public.my_role() = 'admin');
create policy "Admin deletes review photos" on storage.objects for delete to authenticated using (bucket_id = 'review-photos' and public.my_role() = 'admin');
