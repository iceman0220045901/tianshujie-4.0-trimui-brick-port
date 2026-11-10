# 用 tools/fbdev_block.c 整块替换 sdlfun.c 里的 fbdev 代码段（幂等）
$ErrorActionPreference = 'Stop'
$src = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\jysdl-bh-sdl2-surface\src\sdlfun.c'
$blk = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\tools\fbdev_block.c'
$enc = [Text.Encoding]::GetEncoding(936)
$nl = [string][char]13 + [string][char]10

$t = [IO.File]::ReadAllText($src, $enc)
$block = [IO.File]::ReadAllText($blk, [Text.Encoding]::UTF8)
$block = ($block -replace "`r`n", "`n").Replace("`n", $nl)

$startMark = '/* ================= fbdev 直写后端'
$si = $t.IndexOf($startMark)
if ($si -lt 0) { throw 'fbdev start marker missing' }
$tailMark = 'static HSTREAM currentMusic'
$ti = $t.IndexOf($tailMark)
if ($ti -lt 0) { throw 'tail marker missing' }
if ($ti -lt $si) { throw 'markers out of order' }

$out = $t.Substring(0, $si) + $block + $nl + $t.Substring($ti)
[IO.File]::WriteAllText($src, $out, $enc)
"fbdev block replaced ($([math]::Round($block.Length/1024,1)) KB)"
