-- mvp_41: 이카운트 기준코드 (주문서 전송·재고 연동용)
create schema if not exists ec;

create table if not exists ec.warehouse (code text primary key, name text not null, active bool default true);
insert into ec.warehouse(code,name) values
 ('00001','본사창고'),('00002','김성욱창고'),('00003','조용석창고'),('00004','이정우창고'),
 ('00006','이현욱창고'),('00007','홍성민창고'),('00008','이상훈창고'),('00009','이진수창고'),
 ('00010','이동해창고'),('00011','김남형창고'),('00012','삼한공조'),('00013','고병재창고')
on conflict (code) do update set name=excluded.name;

create table if not exists ec.customer (
  code text primary key, name text not null, ceo text, phone text, mobile text,
  addr text, handler text, deal_type text, kind text, note text);

-- 판매채널 ↔ 거래처코드 (거래처코드신규.xlsx)
create table if not exists ec.channel_cust (
  cust_code text primary key, mall text not null, sub text, account text, channel text);
insert into ec.channel_cust(cust_code, mall, sub, account, channel) values
 ('AT0000069508','고도몰','앤텍몰','pcnik35-AT','AT몰'),
 ('AT0000069484','고도몰','프라자몰','pcnik35-P','P몰'),
 ('AT0000069509','고도몰','에스몰','pcnik35-S','S몰'),
 ('AT0000074077','고도몰','시흥몰','pcnik35-SH','시흥'),
 ('AT0000072869','스마트스토어','가전시장','samsungshmall@naver.com','가전시장'),
 ('AT0000069573','스마트스토어','P몰 (B2B몰)','samsung_pmall','B2B'),
 ('AT0000069510','스마트스토어','at몰 (E스토어)','samsungat@naver.com','E스토어'),
 ('AT0000074075','토스쇼핑',null,null,'토스쇼핑'),
 ('AT0000074074','SK스토아',null,null,'SK스토아'),
 ('AT0000074076','Hmall',null,null,'현대홈쇼핑'),
 ('AT0000073802','롯데온',null,null,'롯데온'),
 ('8708801143','SSG',null,null,'SSG'),
 ('AT0000021661','G마켓',null,null,'지마켓'),
 ('8158101244','11번가',null,null,'11번가'),
 ('1208800767','쿠팡',null,null,'쿠팡')
on conflict (cust_code) do update set mall=excluded.mall, sub=excluded.sub,
  account=excluded.account, channel=excluded.channel;

-- 품목 (코다이AI 기준코드: 이카운트코드 ↔ 모델/상품명) — 데이터는 콘솔 업로드로 적재
create table if not exists ec.product_alias (
  id bigserial primary key,
  ec_code text not null,
  alias text not null,
  alias_key text generated always as (upper(regexp_replace(alias, '[^A-Za-z0-9가-힣]', '', 'g'))) stored);
create unique index if not exists ec_product_alias_uq on ec.product_alias(ec_code, alias);
create index if not exists ec_product_alias_key on ec.product_alias(alias_key);
