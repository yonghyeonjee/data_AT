-- mvp_262 (2026-11-03) 담당자 화면 6개 함수 STABLE → VOLATILE
-- 원인: mvp_257/258 뒤 core.f_staff 가 IP 잠금·세션·기기 기록을 UPDATE 한다.
--      STABLE 함수 안에서 부르면 "cannot execute UPDATE in a read-only transaction" (휴가 탭 목록이 안 뜸).
-- core.f_staff 를 부르는 함수는 반드시 VOLATILE.
alter function public.fn_store_leave_list(text) volatile;
alter function public.fn_store_consult_stats(text,text,date,date,text,text) volatile;
alter function public.fn_store_goods_note_list(text) volatile;
alter function public.fn_store_handler_load(text) volatile;
alter function public.fn_store_month_close(text,date,boolean) volatile;
alter function public.fn_store_sms_info(text) volatile;
