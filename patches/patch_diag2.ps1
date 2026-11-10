$ErrorActionPreference = 'Stop'
$f = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\jysdl-bh-sdl2-surface\src\jymain.c'
$enc = [Text.Encoding]::GetEncoding(936)
$t = [IO.File]::ReadAllText($f, $enc)
$nl = [string][char]13 + [string][char]10
$bs = [char]92

foreach ($tag in @('LUA_RUN_ERR', 'LUA_CFG_ERR')) {
    $arg = if ($tag -eq 'LUA_RUN_ERR') { 'pL_main' } else { 'pL' }
    # broken: literal newline inside the string literal
    $broken = $tag + ': %s' + $nl + '", lua_tostring(' + $arg + ', -1)); }'
    $fixed = $tag + ': %s' + $bs + 'n", lua_tostring(' + $arg + ', -1)); }'
    $t = $t.Replace($broken, $fixed)
    $brokenLf = $tag + ': %s' + [string][char]10 + '", lua_tostring(' + $arg + ', -1)); }'
    $t = $t.Replace($brokenLf, $fixed)
}

[IO.File]::WriteAllText($f, $t, $enc)
$out = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build\patch-diag-report2.txt'
$ok = ($t.Contains('LUA_RUN_ERR: %s' + $bs + 'n')) -and ($t.Contains('LUA_CFG_ERR: %s' + $bs + 'n'))
[IO.File]::WriteAllText($out, ('fixed=' + $ok), (New-Object Text.UTF8Encoding($false)))
