# DRM(NASCA) 엑셀을 이 PC 의 Excel 로 열어 시트마다 UTF-8 TSV 로 뽑는다 (셀 안 줄바꿈은 공백으로)
#   powershell -ExecutionPolicy Bypass -File tools/sub/xlsx_to_tsv.ps1 "<파일.xlsx>" "<출력 폴더>" [이름머리]
#   → <출력 폴더>/<이름머리>_s1.tsv, _s2.tsv … 첫 줄은 '#origin<TAB>행<TAB>열<TAB>시트' (promo_from_xlsx.py 가 건너뛴다)
param([Parameter(Mandatory=$true)][string]$Path, [string]$OutDir = '.', [string]$Stem = 'promo')
$xl = $null
try {
  $xl = New-Object -ComObject Excel.Application; $xl.Visible = $false; $xl.DisplayAlerts = $false
  $wb = $xl.Workbooks.Open((Resolve-Path $Path).Path, 0, $true)
  $i = 1
  foreach ($ws in $wb.Worksheets) {
    $ur = $ws.UsedRange; $v = $ur.Value2; $rows = $v.GetLength(0); $cols = $v.GetLength(1)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("#origin`t$($ur.Row)`t$($ur.Column)`t$($ws.Name)")
    for ($r = 1; $r -le $rows; $r++) { $line = @(); for ($c = 1; $c -le $cols; $c++) { $line += ([string]$v[$r, $c]) -replace "[`r`n]+", ' ' }; [void]$sb.AppendLine(($line -join "`t")) }
    $out = Join-Path $OutDir ("{0}_s{1}.tsv" -f $Stem, $i)
    [IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
    "sheet$i=$($ws.Name) rows=$rows cols=$cols -> $out"; $i++
  }
  $wb.Close($false)
} catch { "ERR: $($_.Exception.Message)" } finally { if ($xl) { $xl.Quit() } }
