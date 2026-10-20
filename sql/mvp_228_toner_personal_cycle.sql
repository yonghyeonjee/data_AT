-- mvp_228 · 2026-10-20 · 자동 발송 product_cycle — 개인 주기 · 첫 회 밀린 사람 · 구매 한 번에 한 통
-- "이미 구매 주기가 파악된 고객은 그 주기로, 안 된 고객은 약 6개월로 · 기존에 안 보낸 사람은 첫 회에 한 번에, 나머지는 기간이 되었을 때"
--  · params.cycle_mode='personal' 이면 소모품 구매일(서로 14일 넘게 떨어진 날) 간격이 2개 이상인 고객은 간격 중앙값(30~365일로 자름),
--    아니면 params.cycle_days(토너 180) 를 쓴다.
--  · 창 = 예정일이 [오늘 + lo, 오늘 + hi] — lo 는 음수(지난 날 수 · 첫 회에 넣을 밀린 사람 한도), hi 는 예정일 며칠 앞에 보낼지.
--  · 이미 보낸 사람 = 같은 규칙으로 '마지막 구매 뒤에' 보낸 적 있음 → 구매 한 번에 한 통. 다시 사면 다음 예정일에 또.
--    (전엔 '주기 절반 안' 이라 창을 넓히면 안 산 사람에게 반 주기마다 다시 갔다)
--  · 응답에 backlog(예정일이 이미 지난 사람) · own_cycle(개인 주기) · default_cycle, 줄마다 cycle · cycle_own.
do $outer$
declare d text; s int; e int; nb text;
begin
  d := pg_get_functiondef('public.fn_auto_rule_preview'::regproc);
  if (length(d)-length(replace(d,'v_cons text; v_body text;','')))/length('v_cons text; v_body text;') <> 1 then raise exception 'decl 지점'; end if;
  d := replace(d, 'v_cons text; v_body text;', 'v_cons text; v_body text; v_personal boolean; v_extra jsonb;');
  if (length(d)-length(replace(d,'''rows'', coalesce(v_rows,''[]''::jsonb));','')))/length('''rows'', coalesce(v_rows,''[]''::jsonb));') <> 1 then raise exception 'ret 지점'; end if;
  d := replace(d, '''rows'', coalesce(v_rows,''[]''::jsonb));', '''rows'', coalesce(v_rows,''[]''::jsonb)) || coalesce(v_extra, ''{}''::jsonb);');
  s := position('    v_cons := r.params->>''consumable'';' in d);
  e := position('into v_total, v_rows from sel;' in d);
  if s = 0 or e = 0 or e < s then raise exception 'block 지점'; end if;
  nb := $nb$    v_cons := r.params->>'consumable'; v_body := nullif(r.params->>'body',''); v_cycle := coalesce((r.params->>'cycle_days')::int, 180);
    v_lo := coalesce((r.params->>'lo')::int, -30); v_hi := coalesce((r.params->>'hi')::int, 14);
    v_personal := coalesce(r.params->>'cycle_mode','') = 'personal';
    with o as (
      select buyer_key::text bk, order_at::date d, product_name_raw pn, nullif(model_key,'') mk from core.orders_live
       where net_amount > 0 and buyer_key is not null and coalesce(channel_type,'') <> '오픈마켓' and coalesce(status,'') not in ('취소','환불') and order_at > now() - interval '3 years'),
    cons as (select bk, max(d) last_d, (array_agg(pn order by d desc))[1] pn, (array_agg(mk order by d desc) filter (where mk is not null))[1] mk from o where pn ~* v_cons group by 1),
    cg as (select bk, d - lag(d) over (partition by bk order by d) gap from (select distinct bk, d from o where v_personal and pn ~* v_cons) z),
    pcy as (select bk, least(greatest(round(percentile_cont(0.5) within group (order by gap))::int, 30), 365) pc
              from cg where gap >= 14 group by bk having count(*) >= 2),
    body as (select bk, max(d) last_d, (array_agg(pn order by d desc))[1] pn, (array_agg(mk order by d desc) filter (where mk is not null))[1] mk from o where v_body is not null and pn ~* v_body and pn !~* v_cons group by 1),
    base as (select coalesce(c.bk, b.bk) bk, coalesce(c.last_d, b.last_d) ref_d, coalesce(c.pn, b.pn) pn, coalesce(c.mk, b.mk) mk, (c.bk is not null) has_cons, p.pc
               from cons c full join body b on b.bk = c.bk left join pcy p on p.bk = coalesce(c.bk, b.bk)),
    sel as (select d.bk, d.ref_d, d.pn, d.mk, d.has_cons, coalesce(d.pc, v_cycle) cyc, (d.pc is not null) cyc_own, d.ref_d + coalesce(d.pc, v_cycle) due_d, cu.name, cu.phone, cu.buyer_key
              from base d join crm.customer cu on cu.buyer_key::text = d.bk
             where d.ref_d + coalesce(d.pc, v_cycle) between v_today + v_lo and v_today + v_hi
               and nullif(cu.phone,'') is not null and not coalesce(cu.is_placeholder,false)
               and not exists (select 1 from crm.sms_optout oo where oo.released_at is null and oo.d8 = right(regexp_replace(cu.phone,'\D','','g'),8))
               and not exists (select 1 from crm.send_log l where l.buyer_key = cu.buyer_key and l.campaign = 'auto_'||r.code and coalesce(l.status,'') <> 'failed' and (l.sent_at at time zone 'Asia/Seoul')::date >= d.ref_d))
    select count(*), coalesce((select jsonb_agg(jsonb_build_object('name', s.name, 'phone', core.f_phone_show(s.phone, false), 'item', s.pn, 'model', s.mk,
             'ref_date', s.ref_d, 'due_date', s.due_d, 'days', (s.due_d - v_today), 'has_cons', s.has_cons, 'optout', false, 'cycle', s.cyc, 'cycle_own', s.cyc_own) order by s.due_d, s.name)
             from (select * from sel order by due_d, name limit v_lim) s), '[]'::jsonb),
           jsonb_build_object('backlog', count(*) filter (where due_d < v_today), 'own_cycle', count(*) filter (where cyc_own),
                              'default_cycle', v_cycle, 'cycle_mode', case when v_personal then 'personal' else 'fixed' end, 'lo', v_lo, 'hi', v_hi)
      into v_total, v_rows, v_extra from sel;$nb$;
  d := substr(d, 1, s-1) || nb || substr(d, e + length('into v_total, v_rows from sel;'));
  execute d;
end $outer$;

-- 토너 규칙: 개인 주기 · 기본 180일 · 예정일 14일 앞부터 · 첫 회에 180일 안에 예정일이 지난 사람까지 (처음 -365 → 사용자 결정으로 -180)
update crm.auto_rule set params = params || '{"cycle_mode":"personal","cycle_days":180,"lo":-180,"hi":14}' where code = 'toner_cycle';
