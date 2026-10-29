/* 삼성전자 스마트 패키지 — 고도몰 상품상세 가격 아래 안내 카드 (데이터센터 배포 · mvp_255)
   고도몰 goods_view.html 에는 이 파일(https://db.samsungat.co.kr/sdp/spkg/spkg.js)을 부르는 script 태그 한 줄만 둔다.
   데이터는 같은 폴더 data.js(관리자 [스마트 패키지] 에서 반영한 판 · Actions 가 만든다) — 오늘(KST)이 기간 안인 판을 고른다.
   미리보기: 상품 URL 뒤 &sp_preview=1 (기간 전이라도 다음 판으로) · &sp_ver=2611-1 (판 지정) */
(function(){
  /* ---- 설정 ---- */
  var PRICE_SEL=['.price-box','.item_price','dl.item_price','.goods_price','.price_box','.item_price_box','.detail_price','.price'];
  var SCOPE_SEL=['#frmView','.item_info_box','.goods_view_info','.detail_info','.goods_info'];
  var ASK_URL='/main/html.php?htmid=service/SamSungSubscription.html';
  var TEL='031-8042-3166';
  var EXTRA_GOODSNO=[]; /* 모델명 매칭이 안 되는 상품은 goodsNo를 넣으면 일반 문구로 노출 */
  var DC='https://db.samsungat.co.kr/sdp/spkg/';
  var q=location.search, preview=/sp_preview=1/.test(q), force=(q.match(/sp_ver=([\w-]+)/)||[])[1];
  var R,D,MAP={},L,hl,MINTXT,MAX,BONUS,PERIOD;
  function fmt(v){return (Math.round(v*10)/10)+'만'}
  function kst(){return new Date(Date.now()+324e5).toISOString().slice(0,10)}
  function pick(rs){var t=kst(),r=null,i;
    if(force){for(i=0;i<rs.length;i++)if(rs[i].ver===force)return rs[i];}
    for(i=0;i<rs.length;i++)if(rs[i].from<=t&&t<=rs[i].to)r=rs[i];
    if(!r&&preview){for(i=0;i<rs.length;i++)if(rs[i].from>t){r=rs[i];break}if(!r&&rs.length)r=rs[rs.length-1];}
    return r}
  function hlOf(x){var h={};for(var i=2;i<x.length;i++){var j=x[i][1]-x[i-1][1],p=x[i-1][1]-x[i-2][1];if(j>=p*2&&j>=p+15)h[x[i][0]]=1}return h}
  function per(a,b){var x=a.split('-'),y=b.split('-');return x[0]+'.'+x[1]+'.'+x[2]+' – '+(x[0]===y[0]?'':y[0]+'.')+y[1]+'.'+y[2]}
  function init(){
    R=pick(((window.SPKG_DATA||{}).releases)||[]);if(!R||!R.ladder||!R.ladder.length)return false;
    D=R;['p','s','n'].forEach(function(t){for(var c in (D[t]||{})){D[t][c].split(' ').forEach(function(m){MAP[m]=[t,c,m]})}});
    L=R.ladder.map(function(x){return [x[0],fmt(x[1])]});hl=hlOf(R.ladder);
    MINTXT=L[0][0]+'품목 '+L[0][1]+'P';MAX=L[L.length-1][1];BONUS=R.bonus||'3만';PERIOD=per(R.from,R.to);
    var st=document.createElement('style');st.textContent=".sp26{--sp-navy:#1f3f8f;--sp-blue:#2f5aa8;--sp-red:#c8432b;margin:14px 0 6px;font-family:inherit;letter-spacing:-.02em;color:#1d2433;clear:both}\n.sp26 *{box-sizing:border-box}\n.sp26-card{position:relative;overflow:hidden;border-radius:12px;background:linear-gradient(135deg,#eef3fc 0%,#f7f9fe 60%,#fff 100%);border:1px solid #d6e0f3;padding:14px 16px 14px 16px}\n.sp26-card:before{content:\"\";position:absolute;left:0;top:0;bottom:0;width:4px;background:linear-gradient(180deg,var(--sp-blue),var(--sp-navy))}\n.sp26-top{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:6px}\n.sp26-tag{display:inline-flex;align-items:center;gap:5px;background:var(--sp-navy);color:#fff;font-size:11.5px;font-weight:700;padding:4px 9px 4px 8px;border-radius:999px;line-height:1}\n.sp26-tag i{width:14px;height:14px;border-radius:50%;background:#ffc93c;color:#8a5a00;font-style:normal;font-size:9px;font-weight:800;display:inline-flex;align-items:center;justify-content:center}\n.sp26-period{font-size:11.5px;color:#6b7590}\n.sp26-msg{font-size:14.5px;font-weight:700;line-height:1.45;color:#1d2433;margin:0}\n.sp26-msg b{color:var(--sp-blue)}\n.sp26-sub{font-size:12.5px;color:#4a5470;margin:3px 0 0;line-height:1.5}\n.sp26-sub em{font-style:normal;color:var(--sp-red);font-weight:700}\n.sp26-more{margin-top:9px;background:none;border:0;padding:0;font:inherit;font-size:12px;color:var(--sp-blue);font-weight:600;cursor:pointer;display:inline-flex;align-items:center;gap:3px}\n.sp26-more:after{content:\"\";width:6px;height:6px;border-right:1.5px solid currentColor;border-bottom:1.5px solid currentColor;transform:rotate(45deg) translateY(-2px);transition:transform .2s}\n.sp26.open .sp26-more:after{transform:rotate(-135deg) translateY(-1px)}\n.sp26-ladder{display:none;margin-top:10px;grid-template-columns:repeat(auto-fill,minmax(64px,1fr));gap:5px}\n.sp26.open .sp26-ladder{display:grid}\n.sp26-step{background:#fff;border:1px solid #dfe6f4;border-radius:8px;padding:6px 4px;text-align:center;line-height:1.25}\n.sp26-step span{display:block;font-size:10.5px;color:#7a84a0}\n.sp26-step strong{font-size:12.5px;color:var(--sp-navy)}\n.sp26-step.hl{border-color:var(--sp-red);background:#fff6f4}\n.sp26-step.hl strong{color:var(--sp-red)}\n.sp26-note{display:none;margin-top:8px;font-size:11px;color:#8a92a8;line-height:1.55}\n.sp26.open .sp26-note{display:block}\n.sp26-tip{margin:8px 0 0;padding:8px 10px;border-radius:8px;background:#fff;border:1px dashed #b9c8e8;font-size:12.5px;color:#33405e;line-height:1.5}\n.sp26-tip b{color:#1f3f8f}\n.sp26-cta{display:flex;gap:6px;margin-top:10px;flex-wrap:wrap}\n.sp26-btn{flex:1 1 140px;display:inline-flex;align-items:center;justify-content:center;gap:5px;height:38px;border-radius:8px;font-size:13px;font-weight:700;text-decoration:none!important;letter-spacing:-.02em}\n.sp26-ask{background:#1f3f8f;color:#fff!important}\n.sp26-ask:hover{background:#163276}\n.sp26-tel{background:#fff;color:#1f3f8f!important;border:1px solid #1f3f8f}\n.sp26-tel:hover{background:#f1f5fd}\n@media(max-width:480px){.sp26-msg{font-size:13.5px}.sp26-card{padding:12px 13px}}";document.head.appendChild(st);
    return true}
  function first(sels,root){for(var i=0;i<sels.length;i++){var e=(root||document).querySelector(sels[i]);if(e)return e}return null}
  function run(){
    if(document.querySelector('.sp26'))return;
    var scope=first(SCOPE_SEL)||document.body;
    var txt=(scope.innerText||scope.textContent||'').toUpperCase();
    var meta=document.querySelector('meta[property="og:title"]');if(meta)txt+=' '+meta.content.toUpperCase();
    var toks=txt.match(/[A-Z0-9][A-Z0-9\-]{5,}/g)||[], type=null, hit=null;
    for(var i=0;i<toks.length;i++){var t=toks[i].replace(/-+$/,''),h=MAP[t]||MAP[t+'/KR'];if(!h)continue;if(h[0]==='n'){hit=h;break}if(!hit)hit=h}
    if(hit)type=hit[0];
    var gno=(q.match(/goodsNo=(\d+)/)||[])[1];if(!type&&gno&&EXTRA_GOODSNO.indexOf(gno)>-1)type='n';
    if(preview&&!type)type=(q.match(/sp_type=([nsp])/)||[])[1]||'n';
    if(!type)return;
    var price=first(PRICE_SEL,scope);if(!price)return;
    var title=((document.querySelector('meta[property="og:title"]')||{}).content||document.title||'');
    var isSub=/\[\s*구독\s*\]/.test(title);
    var msg,sub,tip='';
    if(type==='p'){
      if(isSub){msg='<b>스마트 패키지</b> 제품, 다른 제품과 함께면 <b>추가 할인</b>이 제공됩니다.';sub='삼성 AI 구독 가입 시 품목 수에 포함 · '+MINTXT+'부터, <em>최대 '+MAX+' 포인트</em>';}
      else{msg='<b>스마트 패키지</b> 대상 제품과 함께 구매하면 <b>추가 혜택</b>이 제공됩니다.';sub='대상 제품과 동시 일반 구매 시 <em>'+BONUS+' 포인트</em> 추가 적립';tip='<b>구독으로 가입하면</b> 스마트 패키지 <b>품목 수에 포함</b>돼 품목 수별 포인트(최대 '+MAX+'P)를 받을 수 있어요.';}
    }else if(type==='s'&&!isSub){
      msg='<b>삼성 AI 구독</b>으로 가입하면 <b>스마트 패키지 품목</b>이 됩니다.';sub='일반 구매 시에는 품목 수 혜택 대상이 아닙니다 · 구독 시 '+MINTXT+'부터, <em>최대 '+MAX+' 포인트</em>';
    }else{msg='<b>스마트 패키지</b> 제품, 다른 제품과 함께면 <b>추가 할인</b>이 제공됩니다.';sub=(type==='s'?'삼성 AI 구독 가입 시 적용 · ':'')+''+MINTXT+'부터, 품목 수에 따라 <em>최대 '+MAX+' 포인트</em>';}
    var gtitle=title.replace(/\s*[-|]\s*삼성스토어.*$/,'').trim();
    var memo='[스마트 패키지 문의] '+gtitle+(hit&&gtitle.toUpperCase().indexOf(hit[2].split('/')[0])<0?' / 모델 '+hit[2]:'')+(gno?' / 상품번호 '+gno:'')+' / '+(isSub?'구독 상품':'일반 구매 상품')+'\n다른 제품과 함께 구매 시 스마트 패키지 혜택 상담 희망';
    var ask=ASK_URL+'&src=smartpackage_detail'+(hit?'&product='+encodeURIComponent(hit[1]):'')+(isSub?'':'&ask=both')+'&memo='+encodeURIComponent(memo);
    var lad=(type==='p'&&!isSub)?'':'<div class="sp26-ladder">'+L.map(function(x){return '<div class="sp26-step'+(hl[x[0]]?' hl':'')+'"><span>'+x[0]+'품목</span><strong>'+x[1]+'</strong></div>'}).join('')+'</div>';
    var box=document.createElement('div');box.className='sp26';
    box.innerHTML='<div class="sp26-card"><div class="sp26-top"><span class="sp26-tag"><i>P</i>삼성전자 스마트 패키지</span><span class="sp26-period">'+PERIOD+'</span></div>'+
      '<p class="sp26-msg">'+msg+'</p><p class="sp26-sub">'+sub+'</p>'+(tip?'<p class="sp26-tip">'+tip+'</p>':'')+
      '<div class="sp26-cta"><a class="sp26-btn sp26-ask" href="'+ask+'">스마트 패키지 상담 문의</a><a class="sp26-btn sp26-tel" href="tel:'+TEL.replace(/-/g,'')+'"><svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path fill="currentColor" d="M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1A17 17 0 0 1 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.3.2 2.5.6 3.6.1.3 0 .7-.2 1z"/></svg>'+TEL+'</a></div>'+
      (lad?'<button type="button" class="sp26-more">품목 수별 포인트 보기</button>':'')+lad+
      '<div class="sp26-note">· 동일 판매전표 기준 합산, 삼성전자 멤버십 포인트로 지급(사전 가입 필요)<br>· 배송완료 D+7일 내 자동 적립 · 세부 대상모델은 매장에서 안내드립니다</div></div>';
    price.parentNode.insertBefore(box,price.nextSibling);
    var b=box.querySelector('.sp26-more');if(b)b.onclick=function(){box.classList.toggle('open');b.textContent=box.classList.contains('open')?'접기':'품목 수별 포인트 보기'};
  }
  function boot(){if(!init())return;if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',run);else run();window.addEventListener('load',run)}
  if(window.SPKG_DATA)boot();
  else{var sc=document.createElement('script');sc.src=DC+'data.js?t='+Math.floor(Date.now()/6e5);sc.async=true;sc.onload=boot;(document.head||document.documentElement).appendChild(sc)}
})();
