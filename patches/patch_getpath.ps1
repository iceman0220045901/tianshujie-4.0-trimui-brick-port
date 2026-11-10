$ErrorActionPreference = 'Stop'
$f = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\jysdl-bh-sdl2-surface\src\jymain.c'
$enc = [Text.Encoding]::GetEncoding(936)
$t = [IO.File]::ReadAllText($f, $enc)
$nl = [string][char]13 + [string][char]10
$report = @()

$helper = @'
/* ---- 4.0 config shim: engine-provided `config` table ---- */
static int lua_GetPath(lua_State* pL)
{
    if (lua_gettop(pL) >= 1 && !lua_isnoneornil(pL, 1))
    {
        lua_pushvalue(pL, 1);
        return 1;
    }
    lua_pushstring(pL, "./");
    return 1;
}

static int lua_GetScreenW_shim(lua_State* pL)
{
    extern int g_ScreenW;
    lua_pushinteger(pL, g_ScreenW);
    return 1;
}

static int lua_GetScreenH_shim(lua_State* pL)
{
    extern int g_ScreenH;
    lua_pushinteger(pL, g_ScreenH);
    return 1;
}

static void JY_RegisterConfig(lua_State* pL)
{
    lua_newtable(pL);
    lua_pushcfunction(pL, lua_GetPath);
    lua_setfield(pL, -2, "GetPath");
    lua_pushcfunction(pL, lua_GetScreenW_shim);
    lua_setfield(pL, -2, "GetScreenW");
    lua_pushcfunction(pL, lua_GetScreenH_shim);
    lua_setfield(pL, -2, "GetScreenH");
    lua_setglobal(pL, "config");
}
/* ---- end shim ---- */

'@ -replace "`r`n", $nl

if ($t -notmatch 'JY_RegisterConfig') {
    $anchor = "// 主程序" + $nl + "int main("
    if (-not $t.Contains($anchor)) {
        # fallback: insert before 'int main('
        $t = $t.Replace("int main(int argc, char* argv[])", $helper + "int main(int argc, char* argv[])")
        $report += 'helper inserted (fallback)'
    } else {
        $t = $t.Replace($anchor, $helper + $anchor)
        $report += 'helper inserted (anchor)'
    }
} else {
    $report += 'helper already present'
}

# swap the empty pre-created table for the registered one
$t = $t.Replace("    /* PRE_CONFIG_TABLE */" + $nl + "    lua_newtable(pL);" + $nl + "    lua_setglobal(pL, `"config`");", "    JY_RegisterConfig(pL); /* PRE_CONFIG_TABLE */")
$t = $t.Replace("    /* PRE_CONFIG_TABLE */" + $nl + "    lua_newtable(pL_main);" + $nl + "    lua_setglobal(pL_main, `"config`");", "    JY_RegisterConfig(pL_main); /* PRE_CONFIG_TABLE */")

[IO.File]::WriteAllText($f, $t, $enc)
$out = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build\patch-getpath-report.txt'
[IO.File]::WriteAllText($out, ($report -join $nl) + $nl + 'regCalls=' + ([regex]::Matches($t, 'JY_RegisterConfig\(').Count), (New-Object Text.UTF8Encoding($false)))
