// Deploy step: writes js/config.js from environment variables (Netlify / Vercel / any CI).
const fs=require("fs"),u=process.env.SUPABASE_URL||"",k=process.env.SUPABASE_ANON_KEY||"";
if(!u||!k)console.warn("SUPABASE_URL / SUPABASE_ANON_KEY not set — the site will run in demo mode.");
fs.writeFileSync(__dirname+"/../js/config.js","window.TS_CONFIG="+JSON.stringify({SUPABASE_URL:u,SUPABASE_ANON_KEY:k})+";\n");
