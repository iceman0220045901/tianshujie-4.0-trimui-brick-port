$ErrorActionPreference = 'Stop'
$f = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\jysdl-bh-sdl2-surface\src\jymain.c'
$enc = [Text.Encoding]::GetEncoding(936)
$t = [IO.File]::ReadAllText($f, $enc)
$report = @()

# 1) debug build: ignore CONFIG.Debug, always log breadcrumbs
$old1 = "    if (IsDebug == 0)`r`n    { return 0; }"
$new1 = "#ifndef _DEBUG`r`n    if (IsDebug == 0)`r`n    { return 0; }`r`n#endif"
if ($t.Contains($old1)) {
    $t = $t.Replace($old1, $new1)
    $report += 'patch1 ok (crlf)'
} else {
    $old1b = "    if (IsDebug == 0)`n    { return 0; }"
    $new1b = "#ifndef _DEBUG`n    if (IsDebug == 0)`n    { return 0; }`n#endif"
    if ($t.Contains($old1b)) { $t = $t.Replace($old1b, $new1b); $report += 'patch1 ok (lf)' } else { $report += 'patch1 NOT FOUND' }
}

# 2) surface lua runtime error in Lua_Main
if ($t -notmatch 'LUA_RUN_ERR') {
    $pat = 'result = lua_pcall\(pL_main, 0, LUA_MULTRET, 0\);'
    $t = [regex]::Replace($t, $pat, {
        param($m)
        $m.Value + "`r`n#ifdef _DEBUG`r`n    if (result != 0) { fprintf(stderr, `"LUA_RUN_ERR: %s`n`", lua_tostring(pL_main, -1)); }`r`n#endif"
    }, 1)
    $report += 'patch2 lua error print added'
} else {
    $report += 'patch2 already present'
}

# 3) surface lua runtime error in Lua_Config
if ($t -notmatch 'LUA_CFG_ERR') {
    $pat2 = 'result = lua_pcall\(pL, 0, LUA_MULTRET, 0\);'
    $t = [regex]::Replace($t, $pat2, {
        param($m)
        $m.Value + "`r`n#ifdef _DEBUG`r`n    if (result != 0) { fprintf(stderr, `"LUA_CFG_ERR: %s`n`", lua_tostring(pL, -1)); }`r`n#endif"
    }, 1)
    $report += 'patch3 config error print added'
} else {
    $report += 'patch3 already present'
}

[IO.File]::WriteAllText($f, $t, $enc)
$out = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build\patch-diag-report.txt'
[IO.File]::WriteAllText($out, ($report -join [string][char]10), (New-Object Text.UTF8Encoding($false)))
