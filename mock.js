/* 실제 DB 에서 뽑은 모양 그대로 — 필드명·값 형식이 운영과 같다 */
(function(){
window.__rpc=[]; window.__writes=[];
const MGR = /mgr/.test(location.search);
const ME = MGR ? '차효범' : '송희봉';
const STAFF=['차효범','송희봉','김규완','최태웅','권혁찬','이수혁','고창재'];
function row(o){ return Object.assign({
  id:0, ref:'', at:'2026-09-08T14:09:21+00:00', name:'', tel:'', phone:'', key:'k',
  src:'홈페이지 문의', src2:'상품 문의', route:null, model:null, moved:null, prior:0,
  quote:null, quotes:[], bought:null, bucket:'open', ch_etc:null, detail:null, method:null,
  result:'진행중', consent:false, content:'', handler:ME, expected:null, interest:null,
  next_cat:null, order_id:null, next_date:null, next_note:null, buy_amount:null,
  deleted_at:null, next_model:null, restorable:true, callback_at:null, expect_date:null,
  callback_done:false, delete_reason:null }, o); }
const ROWS=[
  row({id:138, ref:'28', name:'지용현', tel:'01022222222', phone:'010-****-2222', route:'리뷰·혜택',
       content:'리뷰·혜택', consent:true, interest:'삼성 ai 콤보 세탁기랑 tv랑 공기청정기 였던것 같아요', prior:1,
       quotes:[{no:'SH260901-002',ver:1,final:4556612,monthly:102850,models:'AI 콤보'},
               {no:'SH260831-001',ver:1,final:6177600,monthly:90420,models:'냉장고'}],
       callback_at:'2026-09-12T05:00:00+00:00', method:'메시지'}),
  row({id:132, ref:'22', name:'이순신', tel:'01144446666', phone:'011-****-6666', src:'매장 직접 방문',
       route:'지인 소개', content:'매장방문 · 휴대폰·태블릿', consent:true, interest:'TV·사운드바'}),
  row({id:374, ref:'csv:2026-08-31:94007734:김규연', at:'2026-08-31T00:00:00+00:00', name:'김규연',
       tel:'01094007734', phone:'010-****-7734', content:'홈페이지 견적문의 · 개인 · 게시글 13'}),
  row({id:368, ref:'csv:2026-08-24:74852102:이일곤', at:'2026-08-24T00:00:00+00:00', name:'이일곤',
       tel:'01074852102', phone:'010-****-2102', content:'홈페이지 견적문의 · 개인 · 게시글 8'}),
  row({id:366, ref:'csv:2026-08-19:99609294:유영주', at:'2026-07-15T00:00:00+00:00', name:'유영주',
       tel:'01099609294', phone:'010-****-9294', content:'홈페이지 견적문의 · 개인 · 게시글 177'}),
  row({id:301, ref:'SC260901-000101', name:'박상현', tel:'01033334444', phone:'010-****-4444',
       src:'매장 직접 방문', interest:'냉장고', model:'RF85DG9', result:'상담완료', bucket:'done',
       content:'가격만 물어봄'}),
  row({id:302, ref:'SC260902-000102', name:'김하늘', tel:'01055556666', phone:'010-****-6666',
       interest:'세탁건조기', result:'보류', bucket:'hold', content:'예산 때문에 보류'}),
  row({id:303, ref:'SC260903-000103', name:'정수민', tel:'01077778888', phone:'010-****-8888',
       interest:'에어컨', result:'구매완료', bucket:'done', bought:'무풍에어컨', buy_amount:2450000}),
];
const CNT={open:5,hold:1,done:2,reject:0,all:8,trash:0};
const STATUS={ me:ME, dept:'매장', is_mgr:MGR,
  perms:['consult','sale','stock','order','report','channel','send','stock_move','callback'],
  staff:STAFF, callbacks:[{id:138,ref:'28',name:'지용현',tel:'01022222222',at:'2026-09-12T05:00:00+00:00',late:false}],
  open_count:5, open_sales:[{id:178485,date:'2026-09-09',kind:'일시불',mine:true,amount:151515,handler:ME,product:'AI 콤보',customer:'지*현'}],
  closed_mine:[], today_sales:[], my_customers:[{key:'k1',name:'최유정',phone:'010-****-3976',spent:0,orders:0,consent:false,last_at:'2026-09-09T00:00:00+00:00',last_what:'상담 냉장고'}],
  unassigned_n: MGR?3:0, closed_recent:[], unclosed_days:['2026-08-28'], unclosed_mine:[],
  callback_today:1, today_consults:2, recent_products:['ai 콤보','무풍에어컨'],
  my_open_consults:ROWS.slice(0,3), my_customer_count:31 };
const D={
  fn_store_status: STATUS,
  fn_store_consults_my: {ok:true, me:ME, who:ME, rows:ROWS, total:ROWS.length, counts:CNT, filter:'open', is_mgr:MGR, limit:20, offset:0, q:null},
  fn_store_consults_all: {ok:true, rows:ROWS.slice(0,3), total:3, counts:{}, handlers:STAFF},
  fn_store_quotes: [], fn_store_customers: [], fn_staff_leave_list: [],
  fn_store_stats: {rows:[{k:'2026-09',n:8,open:5,hold:1,done:2,reject:0,buy:1,rate:12.5}], total:{n:8,buy:1,rate:12.5,open:6}},
  fn_store_quick_links: [], fn_store_sec_order: [], fn_store_daily_prefill:{rows:[],total:{}},
  fn_store_links: [],
  fn_store_handler_load: {ok:true, me:ME, total:71, d14:40, d30:21, rows:[
    {handler:'송희봉',n:11,d14:8,d30:6,cb_late:0,oldest:'2026-07-15',days:58},
    {handler:'차효범',n:12,d14:7,d30:4,cb_late:1,oldest:'2026-07-29',days:44},
    {handler:'김규완',n:11,d14:7,d30:3,cb_late:0,oldest:'2026-07-14',days:59},
    {handler:'(미배정)',n:1,d14:1,d30:1,cb_late:0,oldest:'2026-07-08',days:65}]},
};
window.supabase={ createClient(){ return {
  auth:{ getSession:async()=>({data:{session:null}}), onAuthStateChange(){return{data:{subscription:{unsubscribe(){}}}}} },
  rpc:async(n,a)=>{ window.__rpc.push(n);
    if(/submit|update|assign|delete|restore|save|method|leave/i.test(n)){ window.__writes.push({fn:n,args:a});
      return {data:{ok:true, ref:'SC260911-000999', order_no:'SO260911-001'}, error:null}; }
    return {data:(n in D)?D[n]:[], error:null}; } }; } };
})();
