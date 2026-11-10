# 给 JY_GetKey 的 KEYDOWN 分支加按键日志（JY_KEYLOG=1 时写 keylog.txt），幂等
$ErrorActionPreference = 'Stop'
$src = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\jysdl-bh-sdl2-surface\src\sdlfun.c'
$enc = [Text.Encoding]::GetEncoding(936)
$nl = [string][char]13 + [string][char]10
$t = [IO.File]::ReadAllText($src, $enc)

if ($t.Contains('//JY_KEYLOG')) { 'already patched'; exit 0 }

$anchor = 'int JY_GetKey(int* key, int* type, int* mx, int* my)'
$ai = $t.IndexOf($anchor)
if ($ai -lt 0) { throw 'JY_GetKey not found' }
$sp = $t.IndexOf('if (*key == SDLK_SPACE)', $ai)
if ($sp -lt 0) { throw 'space branch not found' }

$lines = @(
  '            //JY_KEYLOG: JY_KEYLOG=1 时把收到的键值追加到 keylog.txt，用于核对按键映射',
  '            {',
  '                static int keylog = -1;',
  '                if (keylog < 0)',
  '                {',
  '                    const char* e = getenv("JY_KEYLOG");',
  '                    keylog = (e != NULL && e[0] == ''1'') ? 1 : 0;',
  '                }',
  '                if (keylog)',
  '                {',
  '                    FILE* fp = fopen("keylog.txt", "a+");',
  '                    if (fp != NULL)',
  '                    {',
  '                        fprintf(fp, "sym=%d", (int)event.key.keysym.sym);',
  '                        fputc(10, fp);',
  '                        fclose(fp);',
  '                    }',
  '                }',
  '            }'
)
$ins = ($lines -join $nl) + $nl
$t = $t.Substring(0, $sp) + $ins + $t.Substring($sp)
[IO.File]::WriteAllText($src, $t, $enc)
'keylog patched'
