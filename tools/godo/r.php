<?php
/* 삼성앤텍 데이터센터 — 단축 링크 착지 (고도몰용)
 * 올릴 곳: www.samsungsh.co.kr/r/index.php  (단축 링크 앞부분 = https://www.samsungsh.co.kr/r/?)
 * 하는 일: /r/?슬러그 → fn_link_go(anon) 로 클릭을 기록하고 UTM 이 붙은 긴 주소로 302.
 * 비밀값 없음 — 아래 키는 공개용(publishable) 키라 노출돼도 된다. RLS 가 crm.link 를 막고 fn_link_go 만 열려 있다.
 * 실패(슬러그 없음·꺼짐·서버 오류)면 홈페이지로 보낸다. 캐시는 절대 남기지 않는다(클릭이 안 세지므로).
 */
const DC_URL  = 'https://wdahskrcpjooqhwwxjiu.supabase.co/rest/v1/rpc/fn_link_go';
const DC_ANON = 'sb_publishable_O74WxjCsacx4G7Dtemgvlw_M9_6VtlW';
const FALLBACK = 'https://www.samsungsh.co.kr';

header('Cache-Control: no-store, no-cache, must-revalidate');
header('Pragma: no-cache');
header('X-Robots-Tag: noindex, nofollow');

$qs = isset($_SERVER['QUERY_STRING']) ? $_SERVER['QUERY_STRING'] : '';
$qs = preg_replace('/^c=/', '', $qs);
$slug = strtolower($qs);
if (!preg_match('/^[a-z0-9]{3,12}$/', $slug)) { header('Location: ' . FALLBACK, true, 302); exit; }

$ref = isset($_SERVER['HTTP_REFERER']) ? substr($_SERVER['HTTP_REFERER'], 0, 300) : null;
$ua  = isset($_SERVER['HTTP_USER_AGENT']) ? substr($_SERVER['HTTP_USER_AGENT'], 0, 200) : null;

$to = null;
if (function_exists('curl_init')) {
  $ch = curl_init(DC_URL);
  curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => json_encode(['p_slug' => $slug, 'p_ref' => $ref, 'p_ua' => $ua]),
    CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'apikey: ' . DC_ANON, 'Authorization: Bearer ' . DC_ANON],
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_CONNECTTIMEOUT => 2,
    CURLOPT_TIMEOUT => 4,
  ]);
  $body = curl_exec($ch);
  $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
  curl_close($ch);
  if ($body !== false && $code >= 200 && $code < 300) {
    $j = json_decode($body, true);
    if (is_array($j) && !empty($j['url']) && preg_match('#^https?://#', $j['url'])) $to = $j['url'];
  }
}
header('Location: ' . ($to ?: FALLBACK), true, 302);
exit;
