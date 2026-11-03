-- mvp_267 (2026-11-03) 상품 안내 문구 — 두 몰 공통 위치
-- "공통 영역은 pay_box 위 · 공통 사항은 price-box 아래 (시흥몰은 스마트 패키지가 들어가는 자리)"
--   프라자몰·시흥몰 스킨 둘 다 .price-box · .pay_box 가 있다 (시흥몰은 .price-box 바로 뒤가 스마트 패키지 div.sp26)
--   pos 에 pay_above(네이버페이 위) 추가 · 새 문구 기본 위치를 price_below(가격 아래) 로

alter table sub.goods_note drop constraint if exists goods_note_pos_check;
alter table sub.goods_note add constraint goods_note_pos_check
  check (pos in ('title_below','price_below','benefit_above','benefit_below','buy_above','pay_above','pay_below','detail_top'));
alter table sub.goods_note alter column pos set default 'price_below';

-- fn_store_goods_note_save: 새 문구 위치 기본값 benefit_below → price_below (1곳)
do $$
declare v_src text; v_new text;
begin
  select pg_get_functiondef('public.fn_store_goods_note_save(text, jsonb)'::regprocedure) into v_src;
  v_new := replace(v_src, $q$coalesce(nullif(p_data->>'pos',''), 'benefit_below')$q$, $q$coalesce(nullif(p_data->>'pos',''), 'price_below')$q$);
  if (length(v_src) - length(replace(v_src, $q$'benefit_below')$q$, ''))) / length($q$'benefit_below')$q$) <> 1 or v_new = v_src then
    raise exception 'fn_store_goods_note_save 고칠 곳이 1곳이 아닙니다';
  end if;
  execute v_new;
end $$;
