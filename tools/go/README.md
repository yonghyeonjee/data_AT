# go.samsungat.co.kr — 단축 링크 착지 (GitHub Pages)

이 폴더를 통째로 별도 저장소(예: `yonghyeonjee/go`) 루트에 올린다. PHP·서버 없음.

1. GitHub 에 빈 공개 저장소 `go` 를 만들고 이 4개 파일을 올린다: `index.html` · `404.html` · `CNAME` · `.nojekyll`
2. 저장소 Settings › Pages › Source: main / (root) · Custom domain 에 `go.samsungat.co.kr` (CNAME 파일이 있으면 자동) · Enforce HTTPS 체크
3. samsungat.co.kr DNS 에 CNAME 레코드: 호스트 `go` → 값 `yonghyeonjee.github.io.`
4. 몇 분 뒤 `https://go.samsungat.co.kr/?zzzzzz` 가 "링크가 만료됐거나…" 안내를 보이면 성공
5. 관리자 › UTM 관리 › 단축 링크 주소 [바꾸기] → `https://go.samsungat.co.kr/?`

주소 모양: `go.samsungat.co.kr/?ab3k9x` (기본) · `go.samsungat.co.kr/ab3k9x` 도 404.html 이 같은 일을 한다.
db.samsungat.co.kr/r/ 은 그대로 남아 있어 옛 주소도 계속 동작한다.
