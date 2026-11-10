$ErrorActionPreference = 'Stop'
$f = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\jysdl-bh-sdl2-surface\src\jymain.c'
$enc = [Text.Encoding]::GetEncoding(936)
$t = [IO.File]::ReadAllText($f, $enc)
$nl = [string][char]13 + [string][char]10
$report = @()

# pre-create global table "config" before loading chunks (needed by the 4.0 config.lua)
if ($t -notmatch 'PRE_CONFIG_TABLE') {
    $anchorCfg = "    result = luaL_loadfile(pL, filename);"
    $t = $t.Replace($anchorCfg, "    /* PRE_CONFIG_TABLE */`r`n    lua_newtable(pL);`r`n    lua_setglobal(pL, `"config`");`r`n" + $anchorCfg)
    $anchorMain = "    result = luaL_loadfile(pL_main, JYMain_Lua);"
    $t = $t.Replace($anchorMain, "    /* PRE_CONFIG_TABLE */`r`n    lua_newtable(pL_main);`r`n    lua_setglobal(pL_main, `"config`");`r`n" + $anchorMain)
    $report += 'pre-create config table inserted'
} else {
    $report += 'already present'
}

[IO.File]::WriteAllText($f, $t, $enc)
$out = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build\patch-cfg-report.txt'
[IO.File]::WriteAllText($out, ($report -join $nl), (New-Object Text.UTF8Encoding($false)))
