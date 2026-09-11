import { chromium } from 'playwright';
import http from 'node:http'; import fs from 'node:fs'; import path from 'node:path';
const ROOT='/home/claude/web';
const srv=http.createServer((q,r)=>{ let f=path.join(ROOT, decodeURIComponent(q.url.split('?')[0]));
  if(f.endsWith('/')) f+='index.html';
  fs.readFile(f,(e,d)=>{ if(e){r.writeHead(404);r.end('');return;} r.writeHead(200,{'content-type':'text/html; charset=utf-8'}); r.end(d); }); });
await new Promise(ok=>srv.listen(8768,'127.0.0.1',ok));
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium',headless:false,args:['--headless=new','--no-sandbox','--disable-gpu']});

const MOCK=`(function(){
const D={"no":"SH260910-002","ok":true,"ver":1,"card":"삼성카드 30만↑","memo":null,"name":"김하늘","type":"구독",
"final":5097743,"phone":"010-****-9999","total":6937920,"models":"의류케어 WD90H25AHSN1(72개월 무상수리)",
"benefit":1840177,"monthly":96360,"counselor":"지용현","expires_d":30,"issued_at":"2026-09-10","expires_at":"2026-10-11",
"real_monthly":70802,"tel":"031-8042-3166","counselor":"지용현",
"note":"기존 견적 금액 조회 및 추가 상담은 031-8042-3166 으로 연락해 주세요.",
"valid_until":"2026-09-17","valid_over":false,"valid_d":6,
"quote":{"cust":{"name":"김하늘","type":"구독","phone":"010-5555-9999","movein":"2026.11.20","wedding":"","memo":""},
 "items":[{"name":"Bespoke AI 콤보 프리미엄","model":"WD90H25AHSN1","months":72,"monthly":96360,"total":6937920,
   "care":"무상수리","cycle":"-","cardDesc":"삼성카드 30만↑ · 월 16,000원×72개월(계약기간 기준)","hidden":false},
  {"name":"비스포크 냉장고 4도어","model":"RF85DG9","months":72,"monthly":58200,"total":4190400,
   "care":"방문케어","cycle":"4개월","hidden":false}]}};
const C={tel:"031-8042-3166",counselor:"지용현",no:"SH260910-002",
  note:"기존 견적 금액 조회 및 추가 상담은 031-8042-3166 으로 연락해 주세요."};
const EXPIRED=Object.assign({ok:false,reason:"expired",expired_at:"2026-08-01"},C);
const BAD=Object.assign({ok:false,reason:"notfound"},C);
const PASTDUE=Object.assign({},D,{valid_over:true,valid_until:"2026-08-20",valid_d:-22});
window.supabase={createClient(){return{rpc:async(n,a)=>{
  const t=(a&&a.p_token)||'';
  if(t.startsWith('exp')) return {data:EXPIRED,error:null};
  if(t.startsWith('bad')) return {data:BAD,error:null};
  if(t.startsWith('old')) return {data:PASTDUE,error:null};
  return {data:D,error:null}; }};}};
})();`;

for (const [tag, vp] of [['mobile',{width:390,height:844}], ['desktop',{width:1100,height:1400}]]){
  for (const [name, tok] of [['ok','5358c9e3947f07d38768500e86fc4a9e'],['기한지난견적','old00000000000000000000000000000'],['링크만료','exp0000000000000000000000000000'],['none','']]){
    const ctx=await b.newContext({viewport:vp, deviceScaleFactor:2, timezoneId:'Asia/Seoul', locale:'ko-KR'});
    const pg=await ctx.newPage(); const errs=[]; pg.on('pageerror',e=>errs.push(e.message));
    await pg.route('**/*', r=>{ const u=r.request().url();
      if(/^http:\/\/127\.0\.0\.1:8768/.test(u)) return r.continue();
      if(/supabase-js/.test(u)) return r.fulfill({contentType:'application/javascript', body:MOCK});
      return r.fulfill({status:200, contentType:'text/css', body:''}); });
    await pg.goto('http://127.0.0.1:8768/q/'+(tok?('?t='+tok):''),{waitUntil:'networkidle'});
    await pg.waitForTimeout(600);
    const info=await pg.evaluate(()=>({
      제목:document.title, 본문:document.body.innerText.replace(/\s+/g,' ').slice(0,150),
      가로넘침:document.documentElement.scrollWidth-document.documentElement.clientWidth,
      작은버튼:[...document.querySelectorAll('button,a.btn')].filter(e=>{const r=e.getBoundingClientRect();return r.height&&r.height<44;}).map(e=>e.textContent.trim()),
      금액노출:!!document.querySelector('.big'),
      전화버튼:[...document.querySelectorAll('a[href^=tel]')].map(a=>a.textContent.trim()),
      기한배너:!!document.querySelector('.expired')}));
    console.log(`[${tag}/${name}]`, JSON.stringify(info, null, 0).slice(0,400));
    if(errs.length) console.log('   ERR:', errs[0]);
    if(name==='ok'||name==='기한지난견적') await pg.screenshot({path:`/tmp/claude-0/q_${tag}_${name}.png`, fullPage: tag==='desktop'});
    await ctx.close();
  }
}
await b.close(); srv.close();
