import { chromium } from 'playwright';
import http from 'node:http'; import fs from 'node:fs'; import path from 'node:path';
const ROOT='/home/claude/web', MOCK=fs.readFileSync('/home/claude/ptest/mock.js','utf8');
const srv=http.createServer((q,r)=>{ let f=path.join(ROOT, decodeURIComponent(q.url.split('?')[0]));
  if(f.endsWith('/')) f+='index.html';
  fs.readFile(f,(e,d)=>{ if(e){r.writeHead(404);r.end('');return;}
    r.writeHead(200,{'content-type': f.endsWith('.html')?'text/html; charset=utf-8':'text/plain'}); r.end(d); }); });
await new Promise(ok=>srv.listen(8767,'127.0.0.1',ok));
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium',headless:false,args:['--headless=new','--no-sandbox','--disable-gpu']});

const MOBILE = process.argv.includes('mobile');
const MGR    = process.argv.includes('mgr');
const VP = MOBILE ? {width:390,height:844} : {width:1280,height:900};
const ctx = await b.newContext({viewport:VP, deviceScaleFactor:2, hasTouch:MOBILE, isMobile:MOBILE,
  timezoneId:'Asia/Seoul', locale:'ko-KR'});
const pg = await ctx.newPage();
const errs=[]; pg.on('pageerror',e=>errs.push(String(e.message)));
/* 바깥 통신은 전부 막고, supabase-js 만 가짜로 바꿔치기 (등록 순서상 뒤에 건 규칙이 먼저 잡히므로 하나로 처리) */
await pg.route('**/*', r=>{ const u=r.request().url();
  if(/^http:\/\/127\.0\.0\.1:8767/.test(u)) return r.continue();
  if(/supabase-js/.test(u)) return r.fulfill({contentType:'application/javascript', body:MOCK});
  if(/\.css/.test(u)) return r.fulfill({status:200, contentType:'text/css', body:''});
  return r.fulfill({status:200, contentType:'application/javascript', body:''}); });
await pg.addInitScript(()=>{ try{ localStorage.setItem('staff_code','8818'); sessionStorage.setItem('st_open','1'); }catch(e){} });

const R=[]; const T=(id,name,ok,note)=>{ R.push({id,name,ok,note:note||''}); };
const tag=MOBILE?'mobile':'desktop'; const who=MGR?'mgr':'staff';
const shot=n=>pg.screenshot({path:`/tmp/claude-0/uat_${who}_${tag}_${n}.png`, fullPage:false});

await pg.goto('http://127.0.0.1:8767/store.html'+(MGR?'?mgr=1':''),{waitUntil:'networkidle'});
await pg.waitForTimeout(1800);
await pg.evaluate(()=>{ try{ MC_LOADED=true; loadMyConsults(0); }catch(e){} });
await pg.waitForTimeout(800);

/* ── T1 로그인 통과 · 내 이름이 보이나 ── */
const nameShown = await pg.evaluate(()=>document.body.innerText.includes(window.ME||''));
T('T1','코드로 들어가면 내 이름이 보인다', nameShown);

/* ── T2 지금 내가 어느 영역인지 ── */
const nav = await pg.evaluate(()=>{
  const on=[...document.querySelectorAll('.side .lk, .tab, .anchor, [class*=active], [class*=" on"]')]
    .filter(e=>/(active|\bon\b)/.test(e.className)).map(e=>e.textContent.trim().slice(0,14));
  return on; });
T('T2','현재 보고 있는 영역이 표시된다', nav.length>0, '강조된 항목: '+JSON.stringify(nav));

/* ── T3 목록 밀도 ── */
const heights = await pg.$$eval('#mcList .crow', r=>r.map(x=>Math.round(x.getBoundingClientRect().height)));
T('T3','한 줄 목록이 조밀하다(터치 1행 ≤80px)', heights.length>0 && Math.max(...heights)<=80, '행 높이 '+JSON.stringify(heights));

/* ── T4 가로 스크롤 없음 ── */
const hscroll = await pg.evaluate(()=>document.documentElement.scrollWidth - document.documentElement.clientWidth);
T('T4','가로로 밀리지 않는다', hscroll<=1, '초과 '+hscroll+'px');

/* ── T5 접힌 줄에서 누구인지 알 수 있나 ── */
const hd0 = await pg.$eval('#mcList .crow .hd', e=>e.innerText.replace(/\s+/g,' ').trim()).catch(()=>'');
T('T5','접힌 줄만 보고 고객을 특정할 수 있다(이름+번호 뒷자리)', /지용현/.test(hd0)&&/2222/.test(hd0), hd0);

/* ── T6 터치 타깃 크기 (모바일 44px 권장) ── */
const small = await pg.evaluate(()=>{
  const out=[]; document.querySelectorAll('#mcList .crow .hd a,#mcList .crow .hd button, .tab, .side .lk').forEach(e=>{
    const r=e.getBoundingClientRect(); if(r.width&&r.height&&(r.height<40||r.width<40))
      out.push((e.textContent.trim()||e.className).slice(0,12)+` ${Math.round(r.width)}x${Math.round(r.height)}`); });
  return out.slice(0,10); });
T('T6','손가락으로 누를 것이 40px 이상', small.length===0, small.join(' / '));

/* ── T7 펼치기 ── */
const haveRows = await pg.$('#mcList .crow');
if(!haveRows){ console.log('!! 목록이 비어 있음. mcList=', await pg.$eval('#mcList', e=>e.innerHTML.slice(0,300)));
  console.log('호출된 RPC:', await pg.evaluate(()=>window.__rpc));
  console.log('오류:', [...new Set(errs)].slice(0,5)); await b.close(); srv.close(); process.exit(1); }
await pg.click('#mcList .crow .hd .nm');
await pg.waitForTimeout(250);
const opened = await pg.$eval('#mcList .crow', e=>e.classList.contains('open'));
const acts = await pg.$$eval('#mcList .crow.open .acts .mini', b=>b.map(x=>x.textContent.trim()));
T('T7','줄을 누르면 펼쳐지고 처리 버튼이 나온다', opened && acts.length>0, acts.join(' · '));
await shot('01_list');

/* ── T8 파괴적 버튼이 자주 쓰는 버튼과 붙어 있지 않은가 ── */
const adj = await pg.evaluate(()=>{
  const bs=[...document.querySelectorAll('#mcList .crow.open .acts .mini')];
  const find=t=>bs.findIndex(b=>b.textContent.trim()===t);
  const del=find('삭제'), rej=find('거절'), done=find('상담완료');
  const gap=(a,c)=>{ if(a<0||c<0) return -1; const ra=bs[a].getBoundingClientRect(), rc=bs[c].getBoundingClientRect();
    return Math.round(Math.hypot(ra.x-rc.x, ra.y-rc.y)); };
  return {삭제_상담완료_거리:gap(del,done), 거절_상담완료_거리:gap(rej,done),
          버튼수:bs.length, 순서:bs.map(b=>b.textContent.trim())}; });
T('T8','되돌리기 어려운 버튼이 자주 쓰는 버튼과 떨어져 있다',
  adj.삭제_상담완료_거리>120, JSON.stringify(adj));

/* ── T9 [구매 확정] → 판매 입력으로 값이 넘어가나 ── */
await pg.evaluate(()=>{ const b=[...document.querySelectorAll('#mcList .crow.open .acts .mini')]
  .find(x=>x.textContent.trim()==='구매 확정'); if(b) b.click(); });
await pg.waitForTimeout(500);
const sale = await pg.evaluate(()=>({ tab:[...document.querySelectorAll('.panel')].filter(p=>!p.classList.contains('hidden')).map(p=>p.id),
  consult:(document.getElementById('s_consult')||{}).value, name:(document.getElementById('s_name')||{}).value,
  phone:(document.getElementById('s_phone')||{}).value, product:(document.getElementById('s_product')||{}).value,
  model:(document.getElementById('s_model')||{}).value, amount:(document.getElementById('s_amount')||{}).value }));
T('T9','[구매 확정]이 판매 입력으로 값을 넘긴다',
  sale.tab.includes('tab-sale') && !!sale.name && !!sale.phone, JSON.stringify(sale));
await shot('02_sale');

/* ── T10 견적서 금액이 판매가로 넘어오나 ── */
const qpick = await pg.evaluate(()=>{ const b=document.getElementById('s_qpick');
  return { 보임: b && !b.classList.contains('hidden'), 버튼: b?[...b.querySelectorAll('.r button')].map(x=>x.textContent.trim()):[] }; });
if(qpick.보임 && qpick.버튼.length>1){ await pg.click('#s_qpick .r button'); await pg.waitForTimeout(300); }
const amt = await pg.evaluate(()=>({amount:(document.getElementById('s_amount')||{}).value,
  kind:[...document.querySelectorAll('#s_kind button')].filter(b=>b.classList.contains('on')).map(b=>b.dataset.v)[0]}));
T('T10','견적서 금액이 판매가에 채워진다', !!amt.amount, JSON.stringify({...qpick, ...amt}));

/* ── T11 삭제 시 확인을 묻나 ── */
await pg.evaluate(()=>goTab('home')); await pg.waitForTimeout(400);
let asked=false; pg.on('dialog', async d=>{ asked=true; await d.dismiss(); });
await pg.evaluate(()=>{ const b=[...document.querySelectorAll('#mcList .crow.open .acts .mini')]
  .find(x=>x.textContent.trim()==='삭제'); if(b) b.click(); });
await pg.waitForTimeout(600);
const delCalled = await pg.evaluate(()=>window.__writes.some(w=>/delete/i.test(w.fn)));
T('T11','삭제는 확인을 거친다', asked || !delCalled, asked?'확인창 뜸':'확인 없이 바로 호출됨');

/* ── T12 점장 전용 영역 ── */
const mgrCards = await pg.evaluate(()=>({
  전체상담: !document.getElementById('allCard').classList.contains('hidden'),
  휴가:    !document.getElementById('lvCard').classList.contains('hidden'),
  전체보기토글: !document.getElementById('st_who').classList.contains('hidden') }));
T('T12', MGR?'점장에게 배정·휴가 영역이 보인다':'일반 담당자에게 점장 영역이 숨겨진다',
  MGR ? (mgrCards.전체상담&&mgrCards.휴가) : (!mgrCards.전체상담&&!mgrCards.휴가), JSON.stringify(mgrCards));

/* ── T16 점장 : 담당자별 밀린 상담 표 ── */
const hl = await pg.evaluate(()=>{ const c=document.getElementById('hlCard');
  if(!c) return {있음:false};
  return {있음:!c.classList.contains('hidden'), 줄:c.querySelectorAll('tbody tr').length,
          내줄강조:!!c.querySelector('tr.me'), 요약:(document.getElementById('hlSub')||{}).textContent}; });
T('T16', MGR?'점장에게 담당자별 밀린 상담 표가 보인다':'담당자에게는 그 표가 숨는다',
  MGR ? (hl.있음 && hl.줄>1) : !hl.있음, JSON.stringify(hl));

/* ── T17 하단 탭바에 판매 입력이 바로 있나 ── */
const bn = await pg.$$eval('#bnav button', b=>b.map(x=>x.textContent.replace(/\d+/g,'').trim()));
T('T17','판매 입력이 [더보기] 안에 숨지 않는다', bn.some(t=>/판매/.test(t)), bn.join(' · '));

/* ── T18 상담번호 칸에 내부 값이 보이지 않나 ── */
T('T18','상담번호 칸에 내부 값(csv:…)이 노출되지 않는다',
  !/^csv:/.test(sale.consult||''), '칸 값: "'+(sale.consult||'')+'"');

/* ── T13 색 대비 (상태 칩) ── */
const chips = await pg.evaluate(()=>{
  const lum=c=>{ const m=c.match(/\d+/g).map(Number).slice(0,3).map(v=>{v/=255; return v<=.03928?v/12.92:Math.pow((v+.055)/1.055,2.4);});
    return .2126*m[0]+.7152*m[1]+.0722*m[2]; };
  return [...document.querySelectorAll('#mcList .res')].slice(0,8).map(e=>{ const s=getComputedStyle(e);
    const a=lum(s.color), b=lum(s.backgroundColor);
    return {t:e.textContent.trim(), ratio:+(((Math.max(a,b)+.05)/(Math.min(a,b)+.05)).toFixed(2))}; }); });
T('T13','상태 칩 글자 대비가 4.5:1 이상', chips.every(c=>c.ratio>=4.5), JSON.stringify(chips));

/* ── T14 상태별 색이 서로 구분되나 ── */
const distinct = await pg.evaluate(()=>{ const s=new Set();
  document.querySelectorAll('#mcList .res').forEach(e=>s.add(e.textContent.trim()+'|'+getComputedStyle(e).backgroundColor));
  const byText={}; document.querySelectorAll('#mcList .res').forEach(e=>byText[e.textContent.trim()]=getComputedStyle(e).backgroundColor);
  return byText; });
T('T14','상태마다 색이 다르다', new Set(Object.values(distinct)).size===Object.keys(distinct).length, JSON.stringify(distinct));

/* ── T15 모바일에서 목록이 잘리지 않나 ── */
/* 보이는 요소가 화면 밖으로 나가는지 — display:none 으로 감춘 것은 셈에서 뺀다 */
const clipped = await pg.evaluate(()=>{ const out=[];
  document.querySelectorAll('#mcList .crow .hd').forEach((hd,i)=>{ const hr=hd.getBoundingClientRect();
    hd.querySelectorAll(':scope > *').forEach(e=>{ const s=getComputedStyle(e); if(s.display==='none') return;
      const r=e.getBoundingClientRect(); if(r.width===0) return;
      if(r.right > hr.right+1 || r.left < hr.left-1) out.push(i+':'+(e.textContent.trim()||e.className).slice(0,10)); }); });
  return out; });
T('T15','접힌 줄에서 잘려 나가는 것이 없다', clipped.length===0, clipped.slice(0,6).join(' / '));

await shot('03_final');
console.log(`\n╔══ ${MGR?'점장':'일반 담당자'} · ${MOBILE?'모바일 390px':'데스크톱 1280px'} ══╗`);
R.forEach(r=>console.log(`${r.ok?'✅':'❌'} ${r.id} ${r.name}${r.note?'\n      └ '+r.note:''}`));
console.log(`\n통과 ${R.filter(r=>r.ok).length}/${R.length}`);
if(errs.length) console.log('스크립트 오류:', [...new Set(errs)].slice(0,4));
await b.close(); srv.close();
