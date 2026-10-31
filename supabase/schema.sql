-- TRACE SOURCING — run this whole file once in Supabase: SQL Editor > New query > Run
create extension if not exists pgcrypto;
create table public.admins(user_id uuid primary key references auth.users(id) on delete cascade, created_at timestamptz default now());
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.admins where user_id=auth.uid()) $$;
create table public.categories(slug text primary key check (slug ~ '^[a-z0-9-]+$'), name text not null, description text, sort_order int default 0, show_in_menu boolean default true, created_at timestamptz default now());
create table public.products(
 id uuid primary key default gen_random_uuid(), seq bigint generated always as identity unique,
 sku text unique not null, slug text unique not null, name text not null check (length(trim(name))>0),
 short_description text, description text,
 category text references public.categories(slug) on update cascade on delete set null, subcategory text,
 gender text not null default 'unisex' check (gender in ('men','women','kids','unisex')),
 original_price numeric(10,2) not null check (original_price>=0), sale_price numeric(10,2) not null check (sale_price>=0),
 wholesale_price numeric(10,2), stock int not null default 0 check (stock>=0), low_stock_threshold int not null default 10,
 colors text[] default '{}', sizes text[] default '{}', images text[] default '{}', main_image text,
 tiers jsonb not null default '[]', tags text[] default '{}',
 status text not null default 'active' check (status in ('active','draft','hidden','out_of_stock')),
 is_new boolean default false, is_best_seller boolean default false, is_clearance boolean default false, is_winter boolean default false, is_featured boolean default false, is_wholesale boolean default false,
 is_demo boolean default false, material text, fit text,
 rating numeric(2,1) default 0, review_count int default 0,
 created_at timestamptz default now(), updated_at timestamptz default now(),
 check (sale_price<=original_price));
create index on public.products(category); create index on public.products(status); create index on public.products(created_at desc); create index on public.products using gin(tags);
create or replace function public.touch() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;
create trigger products_touch before update on public.products for each row execute function public.touch();
create table public.settings(key text primary key, value jsonb not null);
create sequence public.order_seq start 1001;
create table public.orders(id uuid primary key default gen_random_uuid(), code text unique not null default ('TS'||nextval('public.order_seq')),
 customer_name text not null, phone text not null, whatsapp text, email text, address text, city text, payment_method text default 'cod',
 subtotal numeric(10,2) default 0, delivery_charge numeric(10,2) default 0, total numeric(10,2) default 0,
 status text not null default 'Pending' check (status in ('Pending','Confirmed','Processing','Shipped','Delivered','Cancelled')), created_at timestamptz default now());
create table public.order_items(id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
 product_id uuid references public.products(id) on delete set null, product_name text, sku text, qty int not null check (qty>0), size text, color text, unit_price numeric(10,2) not null);
-- security (row level security): the public can only READ active products; only admins can write
alter table public.admins enable row level security; alter table public.categories enable row level security; alter table public.products enable row level security;
alter table public.settings enable row level security; alter table public.orders enable row level security; alter table public.order_items enable row level security;
create policy "admin self" on public.admins for select using (user_id=auth.uid());
create policy "cat read" on public.categories for select using (true);
create policy "cat write" on public.categories for all using (public.is_admin()) with check (public.is_admin());
create policy "prod read" on public.products for select using (status in ('active','out_of_stock') or public.is_admin());
create policy "prod write" on public.products for all using (public.is_admin()) with check (public.is_admin());
create policy "set read" on public.settings for select using (true);
create policy "set write" on public.settings for all using (public.is_admin()) with check (public.is_admin());
create policy "ord admin" on public.orders for all using (public.is_admin()) with check (public.is_admin());
create policy "item admin" on public.order_items for all using (public.is_admin()) with check (public.is_admin());
-- placing an order: server checks stock + prices, then reduces stock (customers cannot write tables directly)
create or replace function public.place_order(p_customer jsonb, p_items jsonb, p_delivery text) returns jsonb language plpgsql security definer set search_path=public as $$
declare it jsonb; pr public.products%rowtype; q int; unit numeric; sub numeric:=0; ship numeric; oid uuid; v_code text;
 s_in numeric:=coalesce((select (value#>>'{}')::numeric from settings where key='delivery_in'),60);
 s_out numeric:=coalesce((select (value#>>'{}')::numeric from settings where key='delivery_out'),120);
 s_free numeric:=coalesce((select (value#>>'{}')::numeric from settings where key='free_over'),3000);
begin
 if p_items is null or jsonb_array_length(p_items)=0 then raise exception 'Your cart is empty'; end if;
 if coalesce(trim(p_customer->>'name'),'')='' or coalesce(trim(p_customer->>'phone'),'')='' then raise exception 'Name and phone are required'; end if;
 insert into orders(customer_name,phone,whatsapp,email,address,city,payment_method) values(trim(p_customer->>'name'),trim(p_customer->>'phone'),p_customer->>'whatsapp',p_customer->>'email',p_customer->>'address',p_customer->>'city',coalesce(p_customer->>'payment','cod')) returning id,code into oid,v_code;
 for it in select * from jsonb_array_elements(p_items) loop
  q:=(it->>'qty')::int; if q is null or q<1 then raise exception 'Invalid quantity'; end if;
  select * into pr from products where seq=(it->>'seq')::bigint and status in ('active','out_of_stock') for update;
  if not found then raise exception 'A product in your cart is no longer available'; end if;
  if pr.stock<q then raise exception 'Only % left of %',pr.stock,pr.name; end if;
  unit:=coalesce((select (t->>'price')::numeric from jsonb_array_elements(pr.tiers) t where (t->>'min')::int<=least(q,24) order by (t->>'min')::int desc limit 1),pr.sale_price);
  update products set stock=stock-q where id=pr.id;
  insert into order_items(order_id,product_id,product_name,sku,qty,size,color,unit_price) values(oid,pr.id,pr.name,pr.sku,q,it->>'size',it->>'color',unit);
  sub:=sub+unit*q;
 end loop;
 ship:=case when sub>=s_free then 0 when p_delivery='in' then s_in else s_out end;
 update orders set subtotal=sub,delivery_charge=ship,total=sub+ship where id=oid;
 return jsonb_build_object('order_code',v_code,'total',sub+ship);
end $$;
create or replace function public.track_order(p_code text, p_phone text) returns text language sql security definer set search_path=public as $$ select status from orders where code=upper(trim(p_code)) and phone=trim(p_phone) limit 1 $$;
grant execute on function public.place_order(jsonb,jsonb,text) to anon, authenticated;
grant execute on function public.track_order(text,text) to anon, authenticated;
-- product image storage (public read, admin write)
insert into storage.buckets(id,name,public) values('product-images','product-images',true) on conflict (id) do nothing;
create policy "img read" on storage.objects for select using (bucket_id='product-images');
create policy "img insert" on storage.objects for insert with check (bucket_id='product-images' and public.is_admin());
create policy "img update" on storage.objects for update using (bucket_id='product-images' and public.is_admin());
create policy "img delete" on storage.objects for delete using (bucket_id='product-images' and public.is_admin());
-- starter data
insert into public.categories(slug,name,description,sort_order) values
('men','Men','Topwear, bottomwear and layers built for everyday wear.',1),('women','Women','T-shirts, tops, trousers and layers.',2),('kids','Kids','Comfortable everyday wear for boys and girls.',3),
('tshirts','T-Shirts','Everyday tees from half sleeve to full sleeve.',4),('polos','Polos','Smart casual polos.',5),('shirts','Shirts','Casual and formal shirts.',6),('pants','Pants','Jeans, chinos, cargos, joggers and trousers.',7),
('shorts','Shorts','Easy shorts for warm days.',8),('hoodies','Hoodies','Soft, warm hoodies.',9),('sweatshirts','Sweatshirts','Minimal sweatshirts.',10),('jackets','Jackets','Lightweight and winter jackets.',11),
('winter','Winter Collection','Layer up for the season.',12),('accessories','Accessories','Caps, bags and socks.',13) on conflict do nothing;
insert into public.settings(key,value) values('clearance_total','5000'),('delivery_in','60'),('delivery_out','120'),('free_over','3000') on conflict do nothing;
