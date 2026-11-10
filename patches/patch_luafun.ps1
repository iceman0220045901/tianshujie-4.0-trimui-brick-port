$ErrorActionPreference = 'Stop'
$f = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\jysdl-bh-sdl2-surface\src\luafun.c'
$enc = [Text.Encoding]::GetEncoding(936)
$t = [IO.File]::ReadAllText($f, $enc)
$crlfText = [string][char]13 + [string][char]10
$lfText = [string][char]10
if ($t.Contains($crlfText)) { $nl = $crlfText } else { $nl = $lfText }

$report = @()
$report += ('crlf=' + $t.Contains($crlfText))

# 1) unzLocateFile third argument: NULL (void*) -> 0 (int)
$old1 = 'unzLocateFile(zip, filename, NULL)'
$n1 = ([regex]::Matches($t, [regex]::Escape($old1))).Count
$t = $t.Replace($old1, 'unzLocateFile(zip, filename, 0)')
$report += ('patch1 replaced=' + $n1)

# 2) get_file_date + zi.dos_date -> fill zlib/tm_zip struct
$old2 = 'get_file_date(filenamezip, &zi.dos_date);'
$n2 = ([regex]::Matches($t, [regex]::Escape($old2))).Count
$new2 = @(
    '{',
    '            struct stat stbuf;',
    '            struct tm tmv;',
    '            if (stat(filename, &stbuf) == 0 && localtime_r(&stbuf.st_mtime, &tmv) != NULL)',
    '            {',
    '                zi.tmz.tm_sec = (uint32_t)tmv.tm_sec;',
    '                zi.tmz.tm_min = (uint32_t)tmv.tm_min;',
    '                zi.tmz.tm_hour = (uint32_t)tmv.tm_hour;',
    '                zi.tmz.tm_mday = (uint32_t)tmv.tm_mday;',
    '                zi.tmz.tm_mon = (uint32_t)tmv.tm_mon;',
    '                zi.tmz.tm_year = (uint32_t)(tmv.tm_year + 1900);',
    '            }',
    '        }'
) -join $nl
$t = $t.Replace($old2, $new2)
$report += ('patch2 replaced=' + $n2)

# 3) ensure stat/uint32_t declarations available
if (-not $t.Contains('#include <sys/stat.h>')) {
    $t = $t.Replace('#include <stdlib.h>', '#include <stdlib.h>' + $nl + '#include <sys/stat.h>')
    $report += 'patch3 include added'
} else {
    $report += 'patch3 include already present'
}

[IO.File]::WriteAllText($f, $t, $enc)
$report += ('file bytes=' + (Get-Item -LiteralPath $f).Length)

$out = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build\patch-report.txt'
[IO.File]::WriteAllText($out, ($report -join $nlText) + $nlText, (New-Object Text.UTF8Encoding($false)))
