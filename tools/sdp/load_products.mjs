/* SDP 구독 계산기 제품 파일(data_products.js) → 데이터센터 core.product (mvp_194 · 2026-10-08)
   쓰는 법 (PC · node 18+):
     set DC_URL=https://wdahskrcpjooqhwwxjiu.supabase.co
     set DC_ANON=<anon 키 · admin.html 안의 값>      set DC_ID=<관리자 아이디>   set DC_PW=<비밀번호>
     node load_products.mjs data_products_0910.js data_products_1001.js
   · 파일을 실행하지 않고 글자로만 읽어 DATA·SPECS·PREPAY_NO 를 JSON 으로 꺼낸다 (여러 파일이면 뒤 파일이 이김 · 빈 값만 앞 파일로 채움)
   · 관리자(또는 dbuploader) 로그인으로 fn_product_sdp_upsert 를 한 번 부른다 — 같은 파일을 다시 넣어도 중복되지 않는다
   · --json out.json 을 주면 올리지 않고 합친 JSON 만 쓴다 (tools/sdp/products_sdp.json 갱신용 · DB 가 raw.githubusercontent.com 에서 가져가는 파일) */
import fs from 'node:fs';
const args=process.argv.slice(2); const jsonOut=args.includes('--json')?args[args.indexOf('--json')+1]:null;
const files=args.filter((a,i)=>!a.startsWith('--')&&args[i-1]!=='--json');
if(!files.length){ console.error('파일을 주세요: node load_products.mjs data_products.js [...]'); process.exit(1); }
function vars(txt){ const out={}; const re=/\bvar\s+(\w+)\s*=\s*/g; const st=[]; let m; while((m=re.exec(txt))) st.push({name:m[1],at:m.index,vs:m.index+m[0].length});
  st.forEach((s,i)=>{ let end=i+1<st.length?st[i+1].at:txt.length; let body=txt.slice(s.vs,end).trim().replace(/\/\*[\s\S]*?\*\/\s*$/,'').trim(); if(body.endsWith(';')) body=body.slice(0,-1).trim(); out[s.name]=JSON.parse(body); }); return out; }
const verOf=t=>(t.match(/버전\s*(\d{4})/)||[])[1]||'';
const rows=new Map(); let lastVer='';
for(const f of files){ const t=fs.readFileSync(f,'utf8'); const V=vars(t); const ver=verOf(t)||f.replace(/\D/g,'').slice(-4); lastVer=ver; const pn=new Set(V.PREPAY_NO||[]);
  for(const [cat,ms] of Object.entries(V.DATA||{})) for(const [model,x] of Object.entries(ms)){ const prev=rows.get(model)||{}; const sp=((V.SPECS||{})[cat]||{})[model];
    rows.set(model,{model,cat,sub:x.s??prev.sub??null,v:x.v??prev.v??null,plans:x.p||prev.plans||[],prepay_no:pn.has(model),q:x.q??prev.q??null,features:(sp&&sp.features)||prev.features||null,type:(sp&&sp.type)||prev.type||null,ver,vers:[...(prev.vers||[]),ver]}); } }
const care=new Map(), plans=new Map(), feats=new Map(); const id=(m,k)=>{ if(!m.has(k)) m.set(k,m.size+1); return m.get(k); };
const models=[...rows.values()].map(r=>{ const pk=JSON.stringify(r.plans.map(p=>[p[0],id(care,p[1]),p[2],p[3]])); const fk=r.features?JSON.stringify(r.features):null;
  return [r.model,r.cat,r.sub,r.v,id(plans,pk),fk?id(feats,fk):null,r.prepay_no?1:0,r.q,r.type,r.ver,r.vers.join(',')]; });
const payload={ver:lastVer, made_at:new Date().toISOString().slice(0,10), models, plans:[...plans.entries()].map(([k,i])=>[i,JSON.parse(k)]), feats:[...feats.entries()].map(([k,i])=>[i,JSON.parse(k)]), care:[...care.entries()].map(([k,i])=>[i,k])};
console.log(`모델 ${models.length} · 플랜 묶음 ${payload.plans.length} · 특징 묶음 ${payload.feats.length} · 버전 ${lastVer}`);
if(jsonOut){ fs.writeFileSync(jsonOut, JSON.stringify(payload)); console.log('썼습니다:', jsonOut); process.exit(0); }
const URL_=process.env.DC_URL, ANON=process.env.DC_ANON, ID=process.env.DC_ID, PW=process.env.DC_PW;
if(!URL_||!ANON||!ID||!PW){ console.error('DC_URL · DC_ANON · DC_ID · DC_PW 환경변수가 필요합니다'); process.exit(1); }
const email = ID.includes('@') ? ID : ID+'@samsungat.local';
const lg=await fetch(`${URL_}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:ANON,'content-type':'application/json'},body:JSON.stringify({email,password:PW})});
if(!lg.ok){ console.error('로그인 실패', lg.status, await lg.text()); process.exit(1); }
const tok=(await lg.json()).access_token;
const r=await fetch(`${URL_}/rest/v1/rpc/fn_product_sdp_upsert`,{method:'POST',headers:{apikey:ANON,authorization:'Bearer '+tok,'content-type':'application/json'},body:JSON.stringify({p_file:files.map(f=>f.split(/[\\/]/).pop()).join(' + '),p_payload:payload})});
console.log(r.status, await r.text());
