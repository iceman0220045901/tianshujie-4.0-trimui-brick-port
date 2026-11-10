# 给 jysdl-bh (sdl2-surface) 增加 /dev/fb0 直写显示后端
# 用法：JY_FBDEV=1 ./jysdllua   → 走 framebuffer；不设或 0 → 仍走 SDL2/Mali（原行为）
# 该脚本幂等：已插入过则跳过对应步骤。

$ErrorActionPreference = 'Stop'
$src = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\jysdl-bh-sdl2-surface\src'
$enc = [Text.Encoding]::GetEncoding(936)
$nl = [string][char]13 + [string][char]10
$rep = @()

$sdl = Join-Path $src 'sdlfun.c'
$main = Join-Path $src 'jymain.c'

# ---------------------------------------------------------------- sdlfun.c
$t = [IO.File]::ReadAllText($sdl, $enc)

# 1) 头文件 + 全局 + 辅助函数
$block = @'

/* ================= fbdev 直写后端（JY_FBDEV=1 启用） ================= */
#include <linux/fb.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

extern int g_FbEnabled;

static int g_FbFd = -1;
static unsigned char* g_FbMem = NULL;
static int g_FbW = 0;
static int g_FbH = 0;
static int g_FbStride = 0;
static int g_FbBpp = 0;
static int* g_FbXMap = NULL;

static int JY_FbInit(void)
{
    struct fb_fix_screeninfo finfo;
    struct fb_var_screeninfo vinfo;

    g_FbFd = open("/dev/fb0", O_RDWR);
    if (g_FbFd < 0)
    {
        JY_Error("fbdev: open /dev/fb0 failed");
        g_FbEnabled = 0;
        return -1;
    }
    if (ioctl(g_FbFd, FBIOGET_FSCREENINFO, &finfo) != 0 ||
        ioctl(g_FbFd, FBIOGET_VSCREENINFO, &vinfo) != 0)
    {
        JY_Error("fbdev: ioctl failed");
        close(g_FbFd);
        g_FbFd = -1;
        g_FbEnabled = 0;
        return -1;
    }

    g_FbW = vinfo.xres;
    g_FbH = vinfo.yres;
    g_FbBpp = vinfo.bits_per_pixel;
    g_FbStride = finfo.line_length;

    g_FbMem = (unsigned char*)mmap(0, (size_t)finfo.smem_len,
        PROT_READ | PROT_WRITE, MAP_SHARED, g_FbFd, 0);
    if (g_FbMem == MAP_FAILED)
    {
        JY_Error("fbdev: mmap failed");
        g_FbMem = NULL;
        close(g_FbFd);
        g_FbFd = -1;
        g_FbEnabled = 0;
        return -1;
    }

    g_FbXMap = (int*)malloc(sizeof(int) * (g_FbW + 1));
    JY_Debug("fbdev ready: %dx%d %dbpp stride=%d (surface %dx%d)",
        g_FbW, g_FbH, g_FbBpp, g_FbStride, g_ScreenW, g_ScreenH);
    return 0;
}

static void JY_FbExit(void)
{
    if (g_FbMem) { munmap(g_FbMem, 0); g_FbMem = NULL; }
    if (g_FbFd >= 0) { close(g_FbFd); g_FbFd = -1; }
    if (g_FbXMap) { free(g_FbXMap); g_FbXMap = NULL; }
}

/* 把 g_Surface 缩放到 framebuffer（最近邻）。注意：memcpy 分支只在尺寸一致时走 */
static int JY_FbBlit(void)
{
    int x, y;
    int w, h, spitch;
    unsigned char* src;

    if (!g_FbMem || !g_Surface || !g_FbXMap)
    { return 0; }
    if (g_FbBpp != 32 || g_Surface->format->BytesPerPixel != 4)
    { return 0; }

    w = g_Surface->w;
    h = g_Surface->h;
    spitch = g_Surface->pitch;
    src = (unsigned char*)g_Surface->pixels;

    if (w == g_FbW && h == g_FbH && spitch == g_FbStride)
    {
        memcpy(g_FbMem, src, (size_t)g_FbH * g_FbStride);
        return 0;
    }

    for (x = 0; x < g_FbW; x++)
    { g_FbXMap[x] = (int)(((long)x * w) / g_FbW) * 4; }

    for (y = 0; y < g_FbH; y++)
    {
        unsigned char* s = src + (size_t)(((long)y * h) / g_FbH) * spitch;
        unsigned int* d = (unsigned int*)(g_FbMem + (size_t)y * g_FbStride);
        for (x = 0; x < g_FbW; x++)
        { d[x] = *(unsigned int*)(s + g_FbXMap[x]); }
    }
    return 0;
}
/* ================= fbdev 结束 ================= */


'@ -replace "`r`n", $nl

if ($t -notmatch 'JY_FbInit') {
    $anchor = '#include "piccache.h"' + $nl
    $t = $t.Replace($anchor, $anchor + $block)
    $rep += 'sdlfun: helper inserted'
} else { $rep += 'sdlfun: helper already present' }

# 2) SDL_Init 分叉
$old = '    r = SDL_Init(SDL_INIT_VIDEO);'
$new = '    if (getenv("JY_FBDEV") != NULL && atoi(getenv("JY_FBDEV")) != 0)' + $nl +
       '    { g_FbEnabled = 1; }' + $nl +
       '    if (g_FbEnabled)' + $nl +
       '    { r = SDL_Init(SDL_INIT_TIMER | SDL_INIT_EVENTS | SDL_INIT_JOYSTICK); }' + $nl +
       '    else' + $nl +
       '    { r = SDL_Init(SDL_INIT_VIDEO); }'
if ($t.Contains($old)) { $t = $t.Replace($old, $new); $rep += 'sdlfun: SDL_Init branch added' }
else { $rep += 'sdlfun: SDL_Init anchor NOT FOUND (or already patched)' }

# 3) InitGame 里包住窗口/渲染器/纹理四行
$win = '    g_Window = SDL_CreateWindow("The Fall of Star", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, w, h, SDL_WINDOW_RESIZABLE);'
$tex = '    g_Texture = SDL_CreateTexture(g_Renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, w, h);'
if ($t.Contains($win) -and $t.Contains($tex)) {
    $t = $t.Replace($win, '    if (!g_FbEnabled)' + $nl + '    {' + $nl + $win)
    $t = $t.Replace($tex, $tex + $nl + '    }' + $nl + '    else' + $nl + '    { JY_FbInit(); }')
    $rep += 'sdlfun: window/renderer creation guarded'
} else { $rep += 'sdlfun: window anchor NOT FOUND' }

# 4) SDL_SetWindowFullscreen 全部加开关（两处：InitGame 与 JY_FullScreen）
$t = $t.Replace('        SDL_SetWindowFullscreen(g_Window, SDL_WINDOW_FULLSCREEN_DESKTOP);',
    '        if (!g_FbEnabled) { SDL_SetWindowFullscreen(g_Window, SDL_WINDOW_FULLSCREEN_DESKTOP); }')
$t = $t.Replace('        SDL_SetWindowFullscreen(g_Window, 0);',
    '        if (!g_FbEnabled) { SDL_SetWindowFullscreen(g_Window, 0); }')
$rep += 'sdlfun: fullscreen calls guarded'

# 5) JY_ShowSurface 走 fb
$anchor = 'int JY_ShowSurface(int flag)' + $nl + '{' + $nl
if ($t.Contains($anchor) -and ($t -notmatch 'JY_FbBlit\(\); return 0;')) {
    $t = $t.Replace($anchor, $anchor + '    if (g_FbEnabled) { JY_FbBlit(); return 0; }' + $nl)
    $rep += 'sdlfun: ShowSurface -> fbdev'
} else { $rep += 'sdlfun: ShowSurface anchor missing/already patched' }

# 6) 鼠标坐标换算用 fb 尺寸
$old = '            SDL_GetWindowSize(g_Window, &win_w, &win_h);'
$new = '            if (g_FbEnabled) { win_w = g_FbW; win_h = g_FbH; } else { SDL_GetWindowSize(g_Window, &win_w, &win_h); }'
$cnt = ([regex]::Matches($t, [regex]::Escape($old))).Count
$t = $t.Replace($old, $new)
$rep += ('sdlfun: mouse mapping patched (' + $cnt + ' sites)')

# 7) MPEG 播放：fb 模式下没有 SDL 窗口，跳过（避免 PotCreateFromWindow 传 NULL）
$old = '    void* tinypot = NULL;'
if ($t.Contains($old) -and ($t -notmatch 'skip MPEG')) {
    $t = $t.Replace('int JY_PlayMPEG(const char* filename, int esckey)' + $nl + '{' + $nl,
        'int JY_PlayMPEG(const char* filename, int esckey)' + $nl + '{' + $nl +
        '    if (g_FbEnabled) { JY_Error("fbdev mode: skip MPEG video %s", filename); return 0; }' + $nl)
    $rep += 'sdlfun: MPEG guarded'
} else { $rep += 'sdlfun: MPEG anchor missing/already patched' }

# 8) 退出时释放 fb
if ($t -notmatch 'JY_FbExit\(\);') {
    $t = $t.Replace('    SDL_Quit();' + $nl + '    return 0;', '    JY_FbExit();' + $nl + '    SDL_Quit();' + $nl + '    return 0;')
    $rep += 'sdlfun: fb exit added'
} else { $rep += 'sdlfun: fb exit already present' }

[IO.File]::WriteAllText($sdl, $t, $enc)

# ---------------------------------------------------------------- jymain.c
$m = [IO.File]::ReadAllText($main, $enc)
if ($m -notmatch 'g_FbEnabled') {
    $m = $m.Replace('int g_ScreenH = 600;', 'int g_ScreenH = 600;' + $nl + 'int g_FbEnabled = 0;                      // 1 = 走 /dev/fb0 直写（JY_FBDEV=1）')
    $rep += 'jymain: g_FbEnabled defined'
} else { $rep += 'jymain: g_FbEnabled already present' }
[IO.File]::WriteAllText($main, $m, $enc)

$out = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\jysdl-bh-aarch64\build\patch-fbdev-report.txt'
[IO.File]::WriteAllText($out, ($rep -join $nl), (New-Object Text.UTF8Encoding($false)))
