/* Service layer: auth, products, categories, settings, storage, orders. UI code never talks to the database directly. */
(function(){const cfg=window.TS_CONFIG||{},TS=window.TS={ready:false};
if(!cfg.SUPABASE_URL||!cfg.SUPABASE_ANON_KEY||!window.supabase)return;
const sb=window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY);TS.sb=sb;TS.ready=true;
const ck=r=>{if(r.error)throw new Error(r.error.message);return r.data},cl=s=>String(s).replace(/[%,()]/g,"");
TS.authService={signIn:async(email,password)=>ck(await sb.auth.signInWithPassword({email,password})),signOut:()=>sb.auth.signOut(),
 isAdmin:async()=>{const{data:{user}}=await sb.auth.getUser();if(!user)return false;const r=await sb.from("admins").select("user_id").eq("user_id",user.id).maybeSingle();return !!r.data}};
TS.categoryService={list:async()=>ck(await sb.from("categories").select("*").order("sort_order").order("name")),create:async c=>ck(await sb.from("categories").insert(c).select().single()),
 update:async(s,c)=>ck(await sb.from("categories").update(c).eq("slug",s).select().single()),remove:async s=>ck(await sb.from("categories").delete().eq("slug",s))};
TS.settingsService={get:async()=>Object.fromEntries(ck(await sb.from("settings").select("*")).map(r=>[r.key,r.value])),set:async(key,value)=>ck(await sb.from("settings").upsert({key,value}))};
TS.resize=file=>new Promise((res,rej)=>{if(!/^image\/(jpeg|png|webp)$/.test(file.type))return rej(new Error("Only JPG, PNG or WEBP images are allowed"));if(file.size>10e6)return rej(new Error("Image is larger than 10 MB"));
 const im=new Image,u=URL.createObjectURL(file);im.onload=()=>{const s=Math.min(1,1600/Math.max(im.width,im.height)),c=document.createElement("canvas");c.width=Math.round(im.width*s);c.height=Math.round(im.height*s);c.getContext("2d").drawImage(im,0,0,c.width,c.height);URL.revokeObjectURL(u);c.toBlob(b=>b?res(b):rej(new Error("Could not process image")),"image/webp",.82)};im.onerror=()=>rej(new Error("Could not read image"));im.src=u});
TS.storageService={bucket:"product-images",async upload(file){const blob=await TS.resize(file),path="products/"+crypto.randomUUID()+".webp";ck(await sb.storage.from(this.bucket).upload(path,blob,{contentType:"image/webp",cacheControl:"31536000"}));return sb.storage.from(this.bucket).getPublicUrl(path).data.publicUrl},
 async remove(urls){const p=urls.map(u=>(u.split("/"+this.bucket+"/")[1]||"")).filter(Boolean);if(p.length)await sb.storage.from(this.bucket).remove(p)}};
TS.productService={async list(o={}){let q=sb.from("products").select("*",{count:"exact"});if(o.q)q=q.or(`name.ilike.%${cl(o.q)}%,sku.ilike.%${cl(o.q)}%`);
 if(o.cat)q=q.eq("category",o.cat);if(o.status)q=q.eq("status",o.status);if(o.stock=="out")q=q.eq("stock",0);if(o.stock=="low")q=q.gt("stock",0).lte("stock",10);if(o.stock=="in")q=q.gt("stock",10);if(o.tag)q=q.eq(o.tag,true);
 const from=o.from||0,r=await q.order(o.sort||"created_at",{ascending:!!o.asc}).range(from,from+(o.size||20)-1);if(r.error)throw new Error(r.error.message);return{rows:r.data,count:r.count}},
 get:async id=>ck(await sb.from("products").select("*").eq("id",id).single()),create:async r=>ck(await sb.from("products").insert(r).select().single()),
 update:async(id,r)=>ck(await sb.from("products").update(r).eq("id",id).select().single()),remove:async id=>ck(await sb.from("products").delete().eq("id",id)),
 upsertMany:async rows=>ck(await sb.from("products").upsert(rows,{onConflict:"sku"}))};
TS.orderService={place:async(f,k)=>ck(await sb.rpc("place_order",{p_customer:{name:f.n,phone:f.p,email:f.e,city:f.d,address:f.ad,payment:"cod"},p_items:k.lines.map(l=>({seq:l.id,qty:l.qty,size:l.size,color:l.color})),p_delivery:f.dm})),
 track:async(c,p)=>ck(await sb.rpc("track_order",{p_code:c,p_phone:p})),
 adminList:async o=>{let q=sb.from("orders").select("*,order_items(*)").order("created_at",{ascending:false}).limit(200);if(o&&o.status)q=q.eq("status",o.status);if(o&&o.q)q=q.or(`code.ilike.%${cl(o.q)}%,phone.ilike.%${cl(o.q)}%,customer_name.ilike.%${cl(o.q)}%`);return ck(await q)},
 setStatus:async(id,status)=>ck(await sb.from("orders").update({status}).eq("id",id))};
const SHAPE={tshirts:"tee",polos:"polo",shirts:"shirt",pants:"pant",shorts:"short",hoodies:"hood",sweatshirts:"hood",jackets:"jack",winter:"hood",accessories:"acc"};
/* storefront: convert a database row into the shape the storefront UI uses */
TS.toFront=r=>{const th=r.low_stock_threshold==null?10:r.low_stock_threshold;return{id:r.seq,uid:r.id,slug:r.slug,name:r.name,gender:r.gender||"unisex",cat:r.category||"shop",shape:SHAPE[r.category]||"tee",sub:r.subcategory||"",clr:!!r.is_clearance,orig:+r.original_price,sale:+r.sale_price,
 tiers:[[1,+r.sale_price],...(r.tiers||[]).filter(t=>t.min>1&&t.min<25).sort((a,b)=>a.min-b.min).map(t=>[t.min,+t.price])],colors:r.colors&&r.colors.length?r.colors:["Grey"],sizes:r.sizes&&r.sizes.length?r.sizes:["One Size"],
 short:r.short_description||"",desc:r.description||"",mat:r.material||"—",fit:r.fit||"—",tags:r.tags||[],rating:(+r.rating||0).toFixed(1),rc:r.review_count||0,qty:r.stock,stock:r.status=="out_of_stock"||r.stock<=0?"out":r.stock<=th?"low":"in",
 sku:r.sku,isNew:r.is_new,isBest:r.is_best_seller,isFeat:r.is_featured,isWholesale:r.is_wholesale,isWinter:r.is_winter,images:r.images||[]}};
TS.catalog=async()=>{try{const [cats,st]=await Promise.all([TS.categoryService.list(),TS.settingsService.get()]);let rows=[],from=0;
 for(;;){const d=ck(await sb.from("products").select("*").order("created_at",{ascending:false}).range(from,from+999));rows=rows.concat(d);if(d.length<1000)break;from+=1000}return{cats,st,rows}}catch(e){console.warn("Catalog load failed",e);return null}};
})();
