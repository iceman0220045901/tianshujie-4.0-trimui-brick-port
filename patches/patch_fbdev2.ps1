# 升级 fbdev 后端：支持 JY_FB_SCALE（倍率缩放）、居中、黑边遮罩 JY_FB_MASK
# 默认不设 JY_FB_SCALE 时行为与之前完全一致（拉伸满屏）
$ErrorActionPreference = 'Stop'
$f = 'C:\Users\qq410\Desktop\游戏\天书劫正式版移植工作区\_src\jysdl-bh-sdl2-surface\src\sdlfun.c'
$enc = [Text.Encoding]::GetEncoding(936)
$t = [IO.File]::ReadAllText($f, $enc)

$startMark = '/* ================= fbdev 直写后端'
$endMark = '/* ================= fbdev 结束'
$si = $t.IndexOf($startMark)
$ei = $t.IndexOf($endMark)
if ($si -lt 0 -or $ei -lt 0) { throw 'fbdev block markers not found' }
# 结束标记所在行整行替换
$eiEnd = $t.IndexOf([char]13, $ei)
if ($eiEnd -lt 0) { $eiEnd = $t.IndexOf([char]10, $ei) }

$block = @'
/* ================= fbdev 直写后端（JY_FBDEV=1 启用） ================= */
/* JY_FB_SCALE=1.5  -> 游戏画面按 1.5 倍缩放后居中显示，四周留黑边（遮罩）   */
/* JY_FB_MASK=000000 -> 黑边颜色（十六进制 RRGGBB，默认纯黑）               */
/* 不设 JY_FB_SCALE  -> 仍按原行为拉伸满屏                                  */
#include <linux/fb.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

extern int g_FbEnabled;
extern SDL_Surface* g_Surface;
extern int g_ScreenW;
extern int g_ScreenH;

static int g_FbFd = -1;
static unsigned char* g_FbMem = NULL;
static int g_FbW = 0;
static int g_FbH = 0;
static int g_FbStride = 0;
static int g_FbBpp = 0;
static int* g_FbXMap = NULL;
static int* g_FbYMap = NULL;
static unsigned char* g_FbRow = NULL;
static float g_FbScale = 0.0f;
static unsigned int g_FbMask = 0xFF000000u;

static void JY_FbLog(const char* text)
{
    FILE* fp = fopen("fbdev.txt", "a+");
    if (fp)
    {
        fputs(text, fp);
        fputc('\n', fp);
        fclose(fp);
    }
}

static void JY_FbFillRow(unsigned char* row, int w, unsigned int color)
{
    int x;
    unsigned int* p = (unsigned int*)row;
    for (x = 0; x < w; x++)
    { p[x] = color; }
}

static int JY_FbInit(void)
{
    struct fb_fix_screeninfo finfo;
    struct fb_var_screeninfo vinfo;
    char buf[256];
    const char* s;
    int n;

    s = getenv("JY_FB_SCALE");
    if (s != NULL && s[0] != 0)
    { g_FbScale = (float)atof(s); }
    if (g_FbScale < 0.0f) { g_FbScale = 0.0f; }

    s = getenv("JY_FB_MASK");
    if (s != NULL && s[0] != 0)
    {
        unsigned int v = 0;
        sscanf(s, "%x", &v);
        g_FbMask = 0xFF000000u | (v & 0x00FFFFFFu);
    }

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

    n = g_FbW > g_FbH ? g_FbW : g_FbH;
    g_FbXMap = (int*)malloc(sizeof(int) * (n + 1));
    g_FbYMap = (int*)malloc(sizeof(int) * (n + 1));
    g_FbRow = (unsigned char*)malloc((size_t)g_FbW * 4 + 4);

    snprintf(buf, sizeof(buf),
        "fbdev init: fb=%dx%d bpp=%d stride=%d surface=%dx%d scale=%.2f mask=%08X",
        g_FbW, g_FbH, g_FbBpp, g_FbStride, g_ScreenW, g_ScreenH, g_FbScale, g_FbMask);
    JY_FbLog(buf);
    return 0;
}

static void JY_FbExit(void)
{
    if (g_FbMem) { munmap(g_FbMem, 0); g_FbMem = NULL; }
    if (g_FbFd >= 0) { close(g_FbFd); g_FbFd = -1; }
    if (g_FbXMap) { free(g_FbXMap); g_FbXMap = NULL; }
    if (g_FbYMap) { free(g_FbYMap); g_FbYMap = NULL; }
    if (g_FbRow) { free(g_FbRow); g_FbRow = NULL; }
}

/* 计算目标矩形：按倍率缩放后居中，超面板则等比收进面板 */
static void JY_FbTarget(int srcW, int srcH, int* dstW, int* dstH, int* offX, int* offY)
{
    int dw, dh;

    if (g_FbScale > 0.0f)
    {
        dw = (int)(srcW * g_FbScale + 0.5f);
        dh = (int)(srcH * g_FbScale + 0.5f);
        if (dw > g_FbW || dh > g_FbH)
        {
            float k = (float)g_FbW / (float)dw;
            float k2 = (float)g_FbH / (float)dh;
            if (k2 < k) { k = k2; }
            dw = (int)(dw * k);
            dh = (int)(dh * k);
        }
    }
    else
    { dw = g_FbW; dh = g_FbH; }

    if (dw < 1) { dw = 1; }
    if (dh < 1) { dh = 1; }

    *dstW = dw;
    *dstH = dh;
    *offX = (g_FbW - dw) / 2;
    *offY = (g_FbH - dh) / 2;
    if (*offX < 0) { *offX = 0; }
    if (*offY < 0) { *offY = 0; }
}

static int JY_FbBlit(void)
{
    int srcW, srcH, spitch;
    int dstW, dstH, offX, offY;
    int x, y;
    unsigned char* src;

    if (!g_FbMem || !g_Surface || !g_FbXMap || !g_FbYMap || !g_FbRow)
    { return 0; }
    if (g_FbBpp != 32 || g_Surface->format->BytesPerPixel != 4)
    { return 0; }

    srcW = g_Surface->w;
    srcH = g_Surface->h;
    spitch = g_Surface->pitch;
    src = (unsigned char*)g_Surface->pixels;

    JY_FbTarget(srcW, srcH, &dstW, &dstH, &offX, &offY);

    /* ---- 黑边遮罩：只填不画游戏的那几块 ---- */
    if (offY > 0)
    {
        for (y = 0; y < offY; y++)
        {
            JY_FbFillRow(g_FbRow, g_FbW, g_FbMask);
            memcpy(g_FbMem + (size_t)y * g_FbStride, g_FbRow, (size_t)g_FbW * 4);
        }
    }
    if (offY + dstH < g_FbH)
    {
        for (y = offY + dstH; y < g_FbH; y++)
        {
            JY_FbFillRow(g_FbRow, g_FbW, g_FbMask);
            memcpy(g_FbMem + (size_t)y * g_FbStride, g_FbRow, (size_t)g_FbW * 4);
        }
    }
    if (offX > 0 || offX + dstW < g_FbW)
    {
        for (y = offY; y < offY + dstH; y++)
        {
            unsigned char* row = g_FbMem + (size_t)y * g_FbStride;
            if (offX > 0)
            {
                JY_FbFillRow(g_FbRow, offX, g_FbMask);
                memcpy(row, g_FbRow, (size_t)offX * 4);
            }
            if (offX + dstW < g_FbW)
            {
                int w2 = g_FbW - (offX + dstW);
                JY_FbFillRow(g_FbRow, w2, g_FbMask);
                memcpy(row + (size_t)(offX + dstW) * 4, g_FbRow, (size_t)w2 * 4);
            }
        }
    }

    /* ---- 1:1 且满屏：直接整块拷 ---- */
    if (dstW == srcW && dstH == srcH && offX == 0 && offY == 0 &&
        spitch == g_FbStride && srcH == g_FbH)
    {
        memcpy(g_FbMem, src, (size_t)g_FbH * g_FbStride);
        return 0;
    }

    for (x = 0; x < dstW; x++)
    { g_FbXMap[x] = (int)(((long)x * srcW) / dstW) * 4; }
    for (y = 0; y < dstH; y++)
    { g_FbYMap[y] = (int)(((long)y * srcH) / dstH) * spitch; }

    for (y = 0; y < dstH; y++)
    {
        unsigned char* s = src + g_FbYMap[y];
        unsigned int* r = (unsigned int*)g_FbRow;
        for (x = 0; x < dstW; x++)
        { r[x] = *(unsigned int*)(s + g_FbXMap[x]); }
        memcpy(g_FbMem + (size_t)(y + offY) * g_FbStride + (size_t)offX * 4,
            g_FbRow, (size_t)dstW * 4);
    }
    return 0;
}
'@

$stay = 0
# 去掉旧块尾部可能残留的 "/* ================= fbdev 结束 ...*/" 行
$after = $t.Substring($eiEnd)
$nlAfter = $after.IndexOf([char]10)
if ($nlAfter -ge 0) { $after = $after.Substring($nlAfter + 1) }

$newText = $t.Substring(0, $si) + ($block -replace "`r`n", "`n").Replace("`n", [string][char]13 + [string][char]10) + $after
[IO.File]::WriteAllText($f, $newText, $enc)
"fbdev block replaced"
