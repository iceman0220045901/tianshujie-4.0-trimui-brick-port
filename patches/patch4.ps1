$ErrorActionPreference = 'Stop'
$p = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build.ps1'
$t = [IO.File]::ReadAllText($p)
$nl = [string][char]13 + [string][char]10
if (-not $t.Contains($nl)) { $nl = [string][char]10 }

$old = "`$argsList = @('cc', '-target', `$T, '-O2', '-w', '-std=gnu89') + `$INC + @('-c', '-o', `$obj, `$src)"
$new = "`$argsList = @('cc', '-target', `$T, '-O2', '-w', '-std=gnu89', '-Wno-incompatible-function-pointer-types', '-Wno-int-conversion', '-Wno-implicit-function-declaration', '-Wno-implicit-int', '-Wno-error') + `$INC + @('-c', '-o', `$obj, `$src)"

$t2 = $t.Replace($old, $new)
[IO.File]::WriteAllText($p, $t2, (New-Object Text.UTF8Encoding($true)))
$rep = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build\flag-patch.txt'
[IO.File]::WriteAllText($rep, ('changed=' + ($t2 -ne $t)), (New-Object Text.UTF8Encoding($false)))
