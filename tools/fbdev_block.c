/* ================= fbdev 直写后端（JY_FBDEV=1 启用） ================= */
/* JY_FB_SCALE=1.5   -> 画面按倍率缩放后居中，四周留遮罩/黑边（不设=拉伸满屏） */
/* JY_FB_MASK=000000 -> 边框底色（十六进制 RRGGBB）                          */
/* JY_FB_OVERLAY=x.png -> 用模拟器遮罩（RGBA PNG，中心镂空）填边框           */
/*   遮罩按“镂空区域”对齐游戏画面：镂空正好套住画面，边框铺满剩余区域        */
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
static int* g_FbXS0 = NULL;   /* 下采样：每列/行的源区间起止 */
static int* g_FbXS1 = NULL;
static int* g_FbYS0 = NULL;
static int* g_FbYS1 = NULL;
static unsigned char* g_FbRow = NULL;
static float g_FbScale = 0.0f;
static unsigned int g_FbMask = 0xFF000000u;

/* ---- 遮罩（overlay） ---- */
static SDL_Surface* g_Ov = NULL;
static int g_OvHX = 0;
static int g_OvHY = 0;
static int g_OvHW = 0;
static int g_OvHH = 0;
static unsigned char* g_OvCache = NULL;   /* 面板大小、已合成好的边框 */
static int g_OvCacheX = -1;
static int g_OvCacheY = -1;
static int g_OvCacheW = -1;
static int g_OvCacheH = -1;

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

/* 从中心做连通填充，求遮罩镂空区域的包围盒 */
static int JY_FbOvHole(SDL_Surface* s)
{
    int w = s->w;
    int h = s->h;
    int pitch = s->pitch;
    unsigned char* px = (unsigned char*)s->pixels;
    unsigned char* vis;
    int* q;
    int head = 0, tail = 0;
    int cx = w / 2, cy = h / 2;
    int minx, miny, maxx, maxy;

    if (px[(size_t)cy * pitch + cx * 4 + 3] > 8)
    { return -1; }

    vis = (unsigned char*)calloc((size_t)w * h, 1);
    q = (int*)malloc(sizeof(int) * (size_t)w * h);
    if (vis == NULL || q == NULL)
    {
        if (vis) free(vis);
        if (q) free(q);
        return -1;
    }

    vis[(size_t)cy * w + cx] = 1;
    q[tail++] = cy * w + cx;
    minx = cx; maxx = cx; miny = cy; maxy = cy;

    while (head < tail)
    {
        int idx = q[head++];
        int x = idx % w;
        int y = idx / w;

        if (x < minx) { minx = x; }
        if (x > maxx) { maxx = x; }
        if (y < miny) { miny = y; }
        if (y > maxy) { maxy = y; }

        if (x > 0 && !vis[(size_t)y * w + (x - 1)] &&
            px[(size_t)y * pitch + (x - 1) * 4 + 3] <= 8)
        { vis[(size_t)y * w + (x - 1)] = 1; q[tail++] = y * w + (x - 1); }
        if (x + 1 < w && !vis[(size_t)y * w + (x + 1)] &&
            px[(size_t)y * pitch + (x + 1) * 4 + 3] <= 8)
        { vis[(size_t)y * w + (x + 1)] = 1; q[tail++] = y * w + (x + 1); }
        if (y > 0 && !vis[(size_t)(y - 1) * w + x] &&
            px[(size_t)(y - 1) * pitch + x * 4 + 3] <= 8)
        { vis[(size_t)(y - 1) * w + x] = 1; q[tail++] = (y - 1) * w + x; }
        if (y + 1 < h && !vis[(size_t)(y + 1) * w + x] &&
            px[(size_t)(y + 1) * pitch + x * 4 + 3] <= 8)
        { vis[(size_t)(y + 1) * w + x] = 1; q[tail++] = (y + 1) * w + x; }
    }

    g_OvHX = minx;
    g_OvHY = miny;
    g_OvHW = maxx - minx + 1;
    g_OvHH = maxy - miny + 1;

    free(vis);
    free(q);
    return 0;
}

static int JY_FbOvLoad(const char* path)
{
    SDL_Surface* s;
    char buf[300];

    s = IMG_Load(path);
    if (s == NULL)
    {
        JY_FbLog("overlay: IMG_Load failed (path?)");
        return -1;
    }
    g_Ov = SDL_ConvertSurfaceFormat(s, SDL_PIXELFORMAT_ARGB8888, 0);
    SDL_FreeSurface(s);
    if (g_Ov == NULL)
    {
        JY_FbLog("overlay: convert to ARGB8888 failed");
        return -1;
    }
    if (JY_FbOvHole(g_Ov) != 0)
    {
        JY_FbLog("overlay: no transparent hole in center, ignored");
        SDL_FreeSurface(g_Ov);
        g_Ov = NULL;
        return -1;
    }
    snprintf(buf, sizeof(buf), "overlay: %s %dx%d hole=(%d,%d) %dx%d",
        path, g_Ov->w, g_Ov->h, g_OvHX, g_OvHY, g_OvHW, g_OvHH);
    JY_FbLog(buf);
    return 0;
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
    if (n < g_ScreenW) { n = g_ScreenW; }
    if (n < g_ScreenH) { n = g_ScreenH; }
    g_FbXS0 = (int*)malloc(sizeof(int) * (n + 2));
    g_FbXS1 = (int*)malloc(sizeof(int) * (n + 2));
    g_FbYS0 = (int*)malloc(sizeof(int) * (n + 2));
    g_FbYS1 = (int*)malloc(sizeof(int) * (n + 2));
    g_FbRow = (unsigned char*)malloc((size_t)g_FbW * 4 + 4);

    snprintf(buf, sizeof(buf),
        "fbdev init: fb=%dx%d bpp=%d stride=%d surface=%dx%d scale=%.2f mask=%08X",
        g_FbW, g_FbH, g_FbBpp, g_FbStride, g_ScreenW, g_ScreenH, g_FbScale, g_FbMask);
    JY_FbLog(buf);

    s = getenv("JY_FB_OVERLAY");
    if (s != NULL && s[0] != 0)
    { JY_FbOvLoad(s); }

    return 0;
}

static void JY_FbExit(void)
{
    if (g_FbMem) { munmap(g_FbMem, 0); g_FbMem = NULL; }
    if (g_FbFd >= 0) { close(g_FbFd); g_FbFd = -1; }
    if (g_FbXMap) { free(g_FbXMap); g_FbXMap = NULL; }
    if (g_FbYMap) { free(g_FbYMap); g_FbYMap = NULL; }
    if (g_FbXS0) { free(g_FbXS0); g_FbXS0 = NULL; }
    if (g_FbXS1) { free(g_FbXS1); g_FbXS1 = NULL; }
    if (g_FbYS0) { free(g_FbYS0); g_FbYS0 = NULL; }
    if (g_FbYS1) { free(g_FbYS1); g_FbYS1 = NULL; }
    if (g_FbRow) { free(g_FbRow); g_FbRow = NULL; }
    if (g_OvCache) { free(g_OvCache); g_OvCache = NULL; }
    if (g_Ov) { SDL_FreeSurface(g_Ov); g_Ov = NULL; }
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

/* 预先把“遮罩 + 底色”合成成一张面板大小的边框缓存（只做一次） */
static void JY_FbBuildBorder(int dstW, int dstH, int offX, int offY)
{
    int x, y;

    if (g_OvCache == NULL)
    { g_OvCache = (unsigned char*)malloc((size_t)g_FbW * 4 * (size_t)g_FbH); }
    if (g_OvCache == NULL) { return; }

    for (y = 0; y < g_FbH; y++)
    { JY_FbFillRow(g_OvCache + (size_t)y * g_FbW * 4, g_FbW, g_FbMask); }

    if (g_Ov != NULL && g_OvHW > 0 && g_OvHH > 0)
    {
        unsigned char* op = (unsigned char*)g_Ov->pixels;
        int oPitch = g_Ov->pitch;
        int ow = g_Ov->w;
        int oh = g_Ov->h;
        float kw = (float)dstW / (float)g_OvHW;
        float kh = (float)dstH / (float)g_OvHH;
        float k = kw > kh ? kw : kh;
        int dW = (int)(ow * k + 0.5f);
        int dH = (int)(oh * k + 0.5f);
        int holeW = (int)(g_OvHW * k + 0.5f);
        int holeH = (int)(g_OvHH * k + 0.5f);
        /* 镂空中心对准画面中心；镂空略大于画面时，多出的部分左右/上下均分 */
        int ox = offX - (int)(g_OvHX * k + 0.5f) + (dstW - holeW) / 2;
        int oy = offY - (int)(g_OvHY * k + 0.5f) + (dstH - holeH) / 2;

        for (y = 0; y < dH; y++)
        {
            int py = oy + y;
            int sy;
            unsigned char* orow;

            if (py < 0 || py >= g_FbH) { continue; }
            sy = (int)((long)y * oh / dH);
            orow = op + (size_t)sy * oPitch;

            for (x = 0; x < dW; x++)
            {
                int px_ = ox + x;
                int sx;
                int a;
                unsigned char* sp;
                unsigned int* dstp;

                if (px_ < 0 || px_ >= g_FbW) { continue; }
                sx = (int)((long)x * ow / dW);
                sp = orow + sx * 4;
                a = sp[3];
                if (a <= 8) { continue; }

                dstp = (unsigned int*)(g_OvCache + (size_t)py * g_FbW * 4) + px_;
                {
                    unsigned int b = *dstp;
                    int br = (int)((b >> 16) & 0xFF);
                    int bg = (int)((b >> 8) & 0xFF);
                    int bb = (int)(b & 0xFF);
                    int sr = (int)sp[2];
                    int sg = (int)sp[1];
                    int sb = (int)sp[0];
                    int ia = 255 - a;
                    int nr = (sr * a + br * ia + 127) / 255;
                    int ng = (sg * a + bg * ia + 127) / 255;
                    int nb = (sb * a + bb * ia + 127) / 255;
                    *dstp = 0xFF000000u | ((unsigned int)nr << 16) |
                            ((unsigned int)ng << 8) | (unsigned int)nb;
                }
            }
        }
    }

    g_OvCacheX = offX;
    g_OvCacheY = offY;
    g_OvCacheW = dstW;
    g_OvCacheH = dstH;
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

    if (g_OvCache == NULL || offX != g_OvCacheX || offY != g_OvCacheY ||
        dstW != g_OvCacheW || dstH != g_OvCacheH)
    { JY_FbBuildBorder(dstW, dstH, offX, offY); }

    /* ---- 边框（遮罩或纯色），只重绘画面之外的条带 ---- */
    if (g_OvCache != NULL)
    {
        for (y = 0; y < offY; y++)
        {
            memcpy(g_FbMem + (size_t)y * g_FbStride,
                g_OvCache + (size_t)y * g_FbW * 4, (size_t)g_FbW * 4);
        }
        for (y = offY + dstH; y < g_FbH; y++)
        {
            memcpy(g_FbMem + (size_t)y * g_FbStride,
                g_OvCache + (size_t)y * g_FbW * 4, (size_t)g_FbW * 4);
        }
        for (y = offY; y < offY + dstH; y++)
        {
            unsigned char* row = g_FbMem + (size_t)y * g_FbStride;
            unsigned char* crow = g_OvCache + (size_t)y * g_FbW * 4;
            if (offX > 0)
            { memcpy(row, crow, (size_t)offX * 4); }
            if (offX + dstW < g_FbW)
            {
                int w2 = g_FbW - (offX + dstW);
                memcpy(row + (size_t)(offX + dstW) * 4,
                    crow + (size_t)(offX + dstW) * 4, (size_t)w2 * 4);
            }
        }
    }

    /* ---- 画面本体：1:1 满屏直接整块拷，否则最近邻缩放 ---- */
    if (dstW == srcW && dstH == srcH && offX == 0 && offY == 0 &&
        spitch == g_FbStride && srcH == g_FbH)
    {
        memcpy(g_FbMem, src, (size_t)g_FbH * g_FbStride);
        return 0;
    }

    /* ---- 缩小：按面积平均（盒式滤波），避免最近邻丢笔画 ---- */
    if ((dstW < srcW || dstH < srcH) && g_FbXS0 != NULL && g_FbYS0 != NULL)
    {
        static const unsigned int recip[9] =
        { 0, 65536u, 32768u, 21845u, 16384u, 13107u, 10923u, 9362u, 8192u };

        for (x = 0; x < dstW; x++)
        {
            int s0 = (int)(((long)x * srcW) / dstW);
            int s1 = (int)(((long)(x + 1) * srcW) / dstW);
            if (s1 <= s0) { s1 = s0 + 1; }
            if (s1 > srcW) { s1 = srcW; }
            g_FbXS0[x] = s0;
            g_FbXS1[x] = s1;
        }
        for (y = 0; y < dstH; y++)
        {
            int s0 = (int)(((long)y * srcH) / dstH);
            int s1 = (int)(((long)(y + 1) * srcH) / dstH);
            if (s1 <= s0) { s1 = s0 + 1; }
            if (s1 > srcH) { s1 = srcH; }
            g_FbYS0[y] = s0;
            g_FbYS1[y] = s1;
        }

        for (y = 0; y < dstH; y++)
        {
            unsigned int* r = (unsigned int*)g_FbRow;
            int sy0 = g_FbYS0[y];
            int sy1 = g_FbYS1[y];
            int sh = sy1 - sy0;
            int sy_, x_;

            for (x_ = 0; x_ < dstW; x_++)
            {
                unsigned int sa = 0, sr = 0, sg = 0, sb = 0;
                int sw = g_FbXS1[x_] - g_FbXS0[x_];
                int n = sw * sh;
                unsigned int rc;
                unsigned int* sp;

                if (n > 8) { n = 8; }
                rc = recip[n];

                for (sy_ = sy0; sy_ < sy1; sy_++)
                {
                    unsigned char* row = src + (size_t)sy_ * spitch;
                    int sx_;
                    for (sx_ = g_FbXS0[x_]; sx_ < g_FbXS1[x_]; sx_++)
                    {
                        sp = (unsigned int*)(row + (size_t)sx_ * 4);
                        sa = *sp;
                        sr += (sa >> 16) & 0xFFu;
                        sg += (sa >> 8) & 0xFFu;
                        sb += sa & 0xFFu;
                    }
                }
                r[x_] = 0xFF000000u |
                    (((sr * rc) >> 16) << 16) |
                    (((sg * rc) >> 16) << 8) |
                    (((sb * rc) >> 16));
            }
            memcpy(g_FbMem + (size_t)(y + offY) * g_FbStride + (size_t)offX * 4,
                g_FbRow, (size_t)dstW * 4);
        }
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
