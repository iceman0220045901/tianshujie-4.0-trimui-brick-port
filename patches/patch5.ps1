$ErrorActionPreference = 'Stop'
$p = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build.ps1'
$t = [IO.File]::ReadAllText($p)
$nl = [string][char]13 + [string][char]10
if (-not $t.Contains($nl)) { $nl = [string][char]10 }

$old = '$o = "$OUT\obj\mz\minishared.o"' + $nl + 'Compile "$SHIM\minishared.c" $o' + $nl + '$objs.Add($o)'
$new = 'foreach ($f in (Get-ChildItem -LiteralPath $SHIM -Filter *.c)) {' + $nl +
       '    $o = "$OUT\obj\mz\$($f.BaseName).o"' + $nl +
       '    Compile $f.FullName $o' + $nl +
       '    $objs.Add($o)' + $nl +
       '}'

$t2 = $t.Replace($old, $new)
[IO.File]::WriteAllText($p, $t2, (New-Object Text.UTF8Encoding($true)))
$rep = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build\shim-patch.txt'
[IO.File]::WriteAllText($rep, ('changed=' + ($t2 -ne $t)), (New-Object Text.UTF8Encoding($false)))
