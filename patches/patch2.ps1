$ErrorActionPreference = 'Stop'
$f = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\jysdl-bh-sdl2-surface\src\luafun.c'
$enc = [Text.Encoding]::GetEncoding(936)
$t = [IO.File]::ReadAllText($f, $enc)
$before = ([regex]::Matches($t, 'zi\.tmz\.')).Count
$t = $t.Replace('zi.tmz.', 'zi.tmz_date.')
[IO.File]::WriteAllText($f, $t, $enc)
$out = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build\patch2-report.txt'
[IO.File]::WriteAllText($out, ('tmz->tmz_date replaced=' + $before), (New-Object Text.UTF8Encoding($false)))
