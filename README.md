# TRACE SOURCING — database-driven store + admin dashboard

Static site (no build tools) + Supabase (PostgreSQL, Auth, Storage).
- `index.html` — customer website (all products, categories, menu, stock and prices come from the database)
- `admin/index.html` — admin dashboard (open `yoursite.com/admin/`)
- `js/services.js` — service layer (auth, products, categories, settings, storage, orders)
- `supabase/schema.sql` — tables, security rules, order function, image bucket
- `seed/demo-products.csv` — 119 demo products (marked `demo`, delete or edit any time)

If Supabase is not configured, the storefront runs in **demo mode** with built-in sample products and the admin shows "Not configured".

## 1. Run locally
```
npm start        # = npx serve .   → http://localhost:3000  (admin: /admin/)
```
(Any static server works. Opening the files by double-click also works for the storefront.)

## 2. Configure the database
1. Create a free project at supabase.com.
2. Open **SQL Editor → New query**, paste all of `supabase/schema.sql`, click **Run**.
3. Open **Project Settings → API**. Copy the **Project URL** and the **anon public** key.
4. Put them in `js/config.js` (or set `SUPABASE_URL` / `SUPABASE_ANON_KEY` environment variables, see `.env.example`).
   Never use the `service_role` key anywhere in this project.

## 3. Configure storage
`schema.sql` already creates the public bucket `product-images` with admin-only upload/delete.
Check it under **Storage**. Nothing else to do.

## 4. Create the admin account
1. **Authentication → Users → Add user** → enter your email + a strong password (tick "Auto confirm").
2. In the SQL Editor run (use your email):
```
insert into public.admins(user_id) select id from auth.users where email='you@example.com';
```
3. Go to `/admin/` and log in. Accounts not listed in `admins` are refused and cannot change anything (enforced by the database).

## 5. Add a product
Admin → **Products → + ADD NEW PRODUCT** → fill name, SKU, category, prices, stock, colors, sizes, tick tags
(New Arrival, Best Seller, Clearance, Winter, Featured, Wholesale) → **PUBLISH**. It appears on the website immediately
(refresh the site). Homepage sections, category pages, search and filters all read the same tags.

## 6. Upload product images
In the product form use the **Images** box: choose one or many JPG/PNG/WEBP files. They are resized (max 1600px, WEBP)
and stored in Supabase Storage; only the URL is saved in the database. Use ◀ ▶ to reorder, ★ to make an image the main one, ✕ to remove. Click Save.

## 7. Edit stock
Products → **Edit** → change *Stock quantity* → **SAVE CHANGES**. The site shows "Only N left" at or below the low-stock
threshold and "Out of stock" at 0. Orders placed on the website reduce stock automatically. The clearance counter on the
homepage = total stock of products ticked *Clearance*; *Settings* sets the campaign total used for the progress bar.

Bulk work: **CSV Import** (columns listed on that page; start from `seed/demo-products.csv`). New categories: **Categories**.

## 8. Deploy
- **Netlify**: drag the folder or connect the repo. Build command `node scripts/build-config.js`, publish directory `.`
  (already in `netlify.toml`). Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` under Site settings → Environment variables.
- **Vercel**: import the repo; same two environment variables (`vercel.json` included).
- **VPS / any host**: upload the folder to any static web server; edit `js/config.js`.
Then in Supabase **Authentication → URL Configuration** add your site address.

## Notes
- Orders: checkout calls the database function `place_order`, which re-checks stock and prices on the server, creates the order,
  and reduces stock; the customer is then sent to WhatsApp (+8801825505508) with the order details. Online payment is not connected.
- Cart, wishlist and recently viewed stay in the customer's browser (localStorage). Products never do.
- Product list on the website is loaded in pages of 1,000 and filtered in the browser. For many thousands of products, move
  filtering/pagination server-side (the service layer is where to do it).
