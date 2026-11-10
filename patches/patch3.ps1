$ErrorActionPreference = 'Stop'
$p = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build.ps1'
$t = [IO.File]::ReadAllText($p)
$nl = [string][char]13 + [string][char]10
if (-not $t.Contains($nl)) { $nl = [string][char]10 }

# add SDL include variable
if (-not $t.Contains('$SDLINC')) {
    $t = $t.Replace('$SHIM = "$BASE\shim"', '$SHIM = "$BASE\shim"' + $nl + '$SDLINC = "$ROOT\dl\SDL2-2.30.8\include"' + $nl + '$SDLXTRA = "$ROOT\dl\extra_inc"')
}

# swap the bundled (Windows) SDL2 headers for the Linux 2.30.8 set + image/ttf headers
$old = '"-I$SRC\SDL2\include",'
$new = '"-I$SDLINC",' + $nl + '    "-I$SDLXTRA",'
$t = $t.Replace($old, $new)

[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
$rep = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build\inc-patch.txt'
[IO.File]::WriteAllText($rep, ('done; sdlinc=' + $t.Contains('$SDLINC') + '; old_left=' + $t.Contains($old)), (New-Object Text.UTF8Encoding($false)))
