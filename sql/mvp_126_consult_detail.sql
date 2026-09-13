-- mvp_126 · 상담 상세 보기 (2026-09-13)
-- 담당자 화면 [상세 보기] 팝업과 상담 입력 고객 헤더가 쓴다.
-- 이 건의 모든 항목 + 기록(notes 를 ' / ' 로 나눈 일지) + 배정 이력 + 같은 고객의 다른 상담 + 견적서 + 연결 주문.
-- 완료일(done_at) 은 결과가 상담완료·거절·구매완료·확인완료·종료일 때 updated_at.
create or replace function public.fn_store_consult_detail(p_code text, p_id bigint)
returns jsonb language plpgsql volatile security definer
set search_path to 'pg_catalog','public' as $$
declare v_me text := core.f_staff(p_code); k crm.consult%rowtype; v_dig text; v_ok boolean;
begin
  perform set_config('dc.me', coalesce(v_me,''), true);
  if v_me is null then raise exception '권한이 없습니다' using errcode='42501'; end if;
  /* 볼 수 있는 건인지 : 범위 뷰(consult_scoped)에 있거나, 삭제된 내 건·점장님 */
  select exists(select 1 from crm.consult_scoped s where s.id = p_id) into v_ok;
  select * into k from crm.consult c where c.id = p_id
     and (v_ok or (c.deleted_at is not null and (c.handler = v_me or core.f_staff_is_mgr(v_me))));
  if not found then raise exception '상담을 찾을 수 없습니다'; end if;
  v_dig := nullif(regexp_replace(coalesce(k.phone,''),'\D','','g'),'');
  if length(coalesce(v_dig,'')) < 10 then v_dig := null; end if;

  return jsonb_build_object(
    'id', k.id, 'ref', k.source_ref, 'source', k.source, 'at', k.consult_at, 'created_at', k.created_at, 'updated_at', k.updated_at,
    'done_at', case when k.result in ('상담완료','거절','구매완료','확인완료','종료') then k.updated_at end,
    'handler', k.handler, 'mine', k.handler = v_me, 'name', k.customer_name, 'phone', k.phone, 'tel', v_dig, 'key', k.buyer_key,
    'result', k.result, 'bucket', core.f_consult_bucket(k.result),
    'channel', coalesce((select ch.label from core.inq_channel ch where ch.code = k.channel_code), core.f_consult_src(k.source, k.inflow_route)),
    'ch_etc', k.channel_etc, 'route', k.inflow_route, 'type', (select ty.label from core.inq_type ty where ty.code = k.type_code), 'method', k.method,
    'interest', k.interest_category, 'model', k.interest_model_code, 'detail', k.interest_detail, 'membership', k.membership_status,
    'content', k.content, 'notes', k.notes,
    'journal', (select coalesce(jsonb_agg(btrim(j) order by ord desc), '[]'::jsonb)
                  from unnest(string_to_array(coalesce(k.notes,''), ' / ')) with ordinality u(j, ord) where btrim(j) <> ''),
    'expected', k.expected_amount, 'expect_date', k.expected_purchase_date,
    'callback_at', k.callback_at, 'callback_done_at', k.callback_done_at,
    'consent', k.consent_marketing, 'gift', k.gift_name, 'gift_amount', k.gift_amount,
    'bought', k.purchase_item, 'next_cat', k.next_category, 'next_model', k.next_model_code, 'next_date', k.next_expected_date, 'next_note', k.next_note,
    'hidden_reason', k.hidden_reason, 'deleted_at', k.deleted_at, 'deleted_by', k.deleted_by, 'delete_reason', k.delete_reason,
    'order', (select jsonb_build_object('id', o.id, 'no', o.order_no, 'at', o.order_at, 'product', o.product_name_raw, 'amount', o.gross_amount,
                                        'status', o.status, 'kind', o.sale_kind, 'channel', o.channel_name, 'handler', o.handler)
                from core.orders o where o.id = k.linked_order_id),
    'moves', (select coalesce(jsonb_agg(jsonb_build_object('from', a.from_handler, 'to', a.to_handler, 'by', a.by_staff, 'note', a.note, 'at', a.created_at) order by a.created_at desc), '[]'::jsonb)
                from crm.consult_assign a where a.consult_id = k.id),
    'quotes', (select coalesce(jsonb_agg(jsonb_build_object('no', q.quote_no, 'ver', q.version, 'at', q.issued_at, 'final', q.final_price,
                          'monthly', q.monthly, 'models', q.models, 'counselor', q.counselor) order by q.issued_at desc), '[]'::jsonb)
                 from (select distinct on (q0.quote_no) q0.* from crm.quote q0
                        where (k.buyer_key is not null and q0.buyer_key = k.buyer_key)
                           or (v_dig is not null and regexp_replace(coalesce(q0.phone,''),'\D','','g') = v_dig)
                        order by q0.quote_no, q0.version desc) q),
    /* 같은 고객의 다른 상담 (이 건 제외) — 이름·번호가 같으면 같은 고객으로 본다 */
    'others', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'ref', p.source_ref, 'at', p.consult_at, 'handler', p.handler, 'result', p.result,
                          'done_at', case when p.result in ('상담완료','거절','구매완료','확인완료','종료') then p.updated_at end,
                          'channel', coalesce((select ch.label from core.inq_channel ch where ch.code = p.channel_code), core.f_consult_src(p.source, p.inflow_route)),
                          'interest', p.interest_category, 'model', p.interest_model_code, 'content', p.content, 'bought', p.purchase_item,
                          'callback_at', p.callback_at) order by p.consult_at desc), '[]'::jsonb)
                 from crm.consult_scoped p where p.id <> k.id
                  and ((k.buyer_key is not null and p.buyer_key = k.buyer_key)
                    or (v_dig is not null and regexp_replace(coalesce(p.phone,''),'\D','','g') = v_dig))));
end $$;
revoke all on function public.fn_store_consult_detail(text, bigint) from public;
grant execute on function public.fn_store_consult_detail(text, bigint) to anon, authenticated, service_role;

-- fn_store_customer_detail 의 consults 에 phone · done_at 추가 (부분 치환으로 적용)
-- 'id', k.id, 'ref', k.source_ref, 'at', k.consult_at, 'handler', k.handler,
--   → 'id', k.id, 'ref', k.source_ref, 'at', k.consult_at, 'phone', k.phone,
--     'done_at', case when k.result in ('상담완료','거절','구매완료','확인완료','종료') then k.updated_at end, 'handler', k.handler,
