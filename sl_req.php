<?php
/**
 * 샵링커 조건 XML 응답기 — samsungat.co.kr 웹서버에 올려서 GAS 를 대체하는 파일.
 * 샵링커 API 는 조회 조건을 "XML 문서의 URL"(iteminfo_url)로 받고 그 주소를 직접 읽어간다.
 * 이 파일은 받은 쿼리스트링을 그 XML 로 되돌려주기만 한다. 로직도, 저장도 없다.
 *
 * 올리는 곳 : https://samsungat.co.kr/sl_req.php  (경로는 자유. 아래 KEY 는 반드시 바꿀 것)
 * 쓰는 곳   : GitHub 저장소 Secrets 의 SL_REQ_URL 을 이 주소로 바꾸면 GAS 가 필요 없어진다.
 *             예) https://samsungat.co.kr/sl_req.php?k=여기에_긴_임의문자열
 */

// 아무나 고객사 코드를 넣어 호출하지 못하도록 하는 최소한의 자물쇠. 20자 이상 임의 문자열로 바꾸세요.
const KEY = 'CHANGE-ME-TO-A-LONG-RANDOM-STRING';

if (!isset($_GET['k']) || !hash_equals(KEY, $_GET['k'])) {
    http_response_code(403);
    exit('forbidden');
}

$allowed = ['customer_id','st_date','ed_date','sdt_time','edt_time','date_type',
            'order_flag','mall_id','seller_admin_id','shoplinker_order_id',
            'mall_order_id','page_no','total_standard_count'];

$body = '';
foreach ($allowed as $k) {
    if (empty($_GET[$k])) continue;
    $v = preg_replace('/[^A-Za-z0-9_@.\-]/', '', $_GET[$k]);   // 태그가 끼어들 여지를 없앤다
    if ($v === '') continue;
    $body .= "\t\t\t<$k>$v</$k>\n";
}

header('Content-Type: text/xml; charset=euc-kr');
header('Cache-Control: no-store');
echo "<?xml version=\"1.0\" encoding=\"euc-kr\"?>\n<Shoplinker>\n\t<OrderInfo>\n\t\t<Order>\n"
   . $body . "\t\t</Order>\n\t</OrderInfo>\n</Shoplinker>";
