$ErrorActionPreference = 'Stop'

# ---- paths ----
$ROOT = 'C:\Users\qq410\WorkBuddy\2026-11-02-10-05-59'
$SRC  = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\jysdl-bh-sdl2-surface'
$ZL   = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\zlib-1.2.11'
$MZ   = "$ZL\contrib\minizip"
$BASE = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64'
$OUT  = "$BASE\build"
$ZIG  = "$ROOT\zig-windows-x86_64-0.13.0\zig.exe"
$T    = 'aarch64-linux-gnu.2.33'
$LUA  = "$ROOT\dl\lua-5.2.4\src"
$SHIM = "$BASE\shim"
$SDLINC = "$ROOT\dl\SDL2-2.30.8\include"
$SDLXTRA = "$ROOT\dl\extra_inc"

$env:ZIG_GLOBAL_CACHE_DIR = "$ROOT\.zig-global"
$env:ZIG_LOCAL_CACHE_DIR  = "$ROOT\.zig-local"

$INC = @(
    "-I$SRC\src",
    "-I$LUA",
    "-I$SHIM",
    "-I$MZ",
    "-I$ZL",
    "-I$SDLINC",
    "-I$SDLXTRA",
    "-I$SRC\Bass\include",
    "-I$SRC\tinypot\include"
)

New-Item -ItemType Directory -Force "$OUT\obj\zlib", "$OUT\obj\mz", "$OUT\obj\lua", "$OUT\obj\game" | Out-Null

$script:log = New-Object System.Collections.Generic.List[string]

function Compile([string]$src, [string]$obj) {
    $argsList = @('cc', '-target', $T, '-O2', '-w', '-std=gnu89', '-Wno-incompatible-function-pointer-types', '-Wno-int-conversion', '-Wno-implicit-function-declaration', '-Wno-implicit-int', '-Wno-error') + $INC + @('-c', '-o', $obj, $src)
    & $ZIG @argsList 2>&1 | ForEach-Object { $script:log.Add([string]$_) }
    if ($LASTEXITCODE -ne 0) {
        $script:log | Set-Content -LiteralPath "$OUT\build.log" -Encoding utf8
        throw "COMPILE FAILED: $src  (see $OUT\build.log)"
    }
}

$objs = New-Object System.Collections.Generic.List[string]

Write-Host '== zlib =='
foreach ($f in (Get-ChildItem -LiteralPath $ZL -Filter *.c)) {
    $o = "$OUT\obj\zlib\$($f.BaseName).o"
    Compile $f.FullName $o
    $objs.Add($o)
}

Write-Host '== minizip =='
foreach ($n in @('unzip', 'zip', 'ioapi')) {
    $o = "$OUT\obj\mz\$n.o"
    Compile "$MZ\$n.c" $o
    $objs.Add($o)
}
foreach ($f in (Get-ChildItem -LiteralPath $SHIM -Filter *.c)) {
    $o = "$OUT\obj\mz\$($f.BaseName).o"
    Compile $f.FullName $o
    $objs.Add($o)
}

Write-Host '== lua 5.2.4 =='
foreach ($f in (Get-ChildItem -LiteralPath $LUA -Filter *.c)) {
    if ($f.Name -in @('lua.c', 'luac.c')) { continue }
    $o = "$OUT\obj\lua\$($f.BaseName).o"
    Compile $f.FullName $o
    $objs.Add($o)
}

Write-Host '== engine =='
foreach ($n in @('charset', 'jymain', 'luafun', 'mainmap', 'piccache', 'sdlfun', 'SDL2_rotozoom')) {
    $o = "$OUT\obj\game\$n.o"
    Compile "$SRC\src\$n.c" $o
    $objs.Add($o)
}

Write-Host '== link =='
$link = @('cc', '-target', $T, '-O2', '-o', "$OUT\jysdllua") + $objs.ToArray() + @(
    "-L$ROOT\sysroot\usr\trimui\lib",
    "-L$ROOT\sysroot\usr\lib",
    "-L$ROOT\dl\bass\bass24\libs\aarch64",
    "-L$ROOT\dl\bass\bassmidi24\libs\aarch64",
    '-l:libSDL2-2.0.so.0.3000.8',
    '-l:libSDL2_image-2.0.so.0.2.3',
    '-l:libSDL2_ttf-2.0.so.0.14.1',
    '-l:libbass.so',
    '-l:libbassmidi.so',
    '-Wl,-rpath,/usr/trimui/lib:/usr/lib:$ORIGIN',
    '-lc', '-lpthread', '-lm', '-ldl'
)
& $ZIG @link 2>&1 | ForEach-Object { $script:log.Add([string]$_) }
if ($LASTEXITCODE -ne 0) {
    $script:log | Set-Content -LiteralPath "$OUT\build.log" -Encoding utf8
    throw "LINK FAILED (see $OUT\build.log)"
}

$fi = Get-Item -LiteralPath "$OUT\jysdllua"
Write-Host ("OK  {0}  {1} bytes  {2}" -f $fi.FullName, $fi.Length, $fi.LastWriteTime)
