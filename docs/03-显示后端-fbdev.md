# 03 · 显示后端：给 SDL2 引擎加 `/dev/fb0` 直写

---

## 一、问题：能不能直接抄别人移植包里的“视频驱动”？

参考包是「金庸群侠传 4in1」的掌机移植。对比两边 ELF：

| 项目 | 4in1 | 我们（jysdl-bh SDL2 分支） |
|---|---|---|
| 主程序 | `jinyong/jysdllua`（597,800 B） | `build/jysdllua`（1.65~1.69 MB） |
| 依赖 SDL | `libSDL-1.2.so.0` | `libSDL2-2.0.so.0` |
| 程序内显示相关字符串 | `fbdev`（2 处）、`/dev/fb`（1 处） | `SDL_CreateRenderer` / `SDL_UpdateTexture` / `SDL_RenderCopy`，**无 fbdev** |
| 随附 SDL 库的后端 | 只有 `dummy` | 只有 `mali`（`MALI_CreateWindow`、`Mali EGL Video Driver`、`mali-fbdev:`） |

**结论**：4in1 是「SDL1.2 管输入/时间，画面引擎自己写 `/dev/fb0`」的老做法；我们是「SDL2 走 Mali/EGL 贴纹理」。两个层次，**换库无解**。真正能复用的是一个事实：**它可以自己写 fb0，我们也能。**

另一个坑：4in1 自带 `libSDL-1.2.so.0` 加载即 `rc=139`（缺 `libpng16`）—— 说明「同目录的库」不等于「能用的库」，系统库优先才是对的。

---

## 二、做法

### 2.1 改动位置

| 文件 | 改动 |
|---|---|
| `jymain.c` | 新增全局 `int g_FbEnabled = 0` |
| `sdlfun.c` | 新增 `JY_FbInit() / JY_FbBlit() / JY_FbExit()` |
| `sdlfun.c` `InitSDL()` | `JY_FBDEV` 非 0 时置 `g_FbEnabled=1`；**`SDL_Init` 仍带 `SDL_INIT_VIDEO`** |
| `sdlfun.c` `InitGame()` | fb 模式不开渲染器/纹理，改 `JY_FbInit()` + 建 `SDL_WINDOW_HIDDEN` 窗口（只为保留输入通路） |
| `sdlfun.c` `JY_ShowSurface()` | 唯一呈现点，fb 模式改调 `JY_FbBlit()` |
| `sdlfun.c` | `SDL_SetWindowFullscreen`、鼠标坐标换算等「依赖真实窗口」的调用全部加 `if (!g_FbEnabled)` |
| `sdlfun.c` `JY_PlayMPEG()` | fb 模式下无可用窗口 → 跳过并写 `error.txt` |
| `sdlfun.c` `ExitSDL()` | `munmap` + `close` |

补丁脚本 `patches/patch_fbdev.ps1`（幂等，可重复执行）。

### 2.2 核心实现

```c
open("/dev/fb0", O_RDWR);
ioctl(fd, FBIOGET_FSCREENINFO, &finfo);   /* line_length, smem_len */
ioctl(fd, FBIOGET_VSCREENINFO, &vinfo);   /* xres, yres, bits_per_pixel */
mem = mmap(0, finfo.smem_len, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
```

每帧（`g_Surface` 是 32bpp）：

- 宽/高/stride 完全一致 → 整屏 `memcpy`；
- 不一致 → 预计算 X 映射表 `g_FbXMap`，逐行按 `y*srcH/dstH` 取源行；
- **仅 32bpp 才启用**，否则安全退回原渲染路径。

### 2.3 必须保留 `SDL_INIT_VIDEO`

`SDL_Init(SDL_INIT_TIMER|SDL_INIT_EVENTS)` 会**丢掉 evdev 键盘/手柄初始化**，表现为「画面有、按键全无」。所以：

```c
SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER | SDL_INIT_EVENTS | ...);
if (g_FbEnabled) {
    g_Window = SDL_CreateWindow("jy", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                w, h, SDL_WINDOW_HIDDEN);   /* 不显示，只保留输入 */
}
```

---

## 三、会不会影响游戏内特效？

数一下 `SDL_RenderCopy` 在工程里出现几次：只剩「把整张表面贴到屏幕」这一处。所有半透明、渐变、遮罩、旋转都在软件表面算完，GPU 只做搬运 —— **换后端不改特效**。

真正有差异的只有三处：

1. **过场 MPEG**：依赖真实窗口，直写模式跳过；
2. **缩放插值**：GPU 线性 → CPU 最近邻/盒式，非整数缩放时笔画观感变化；
3. **vsync/撕裂**：直写是单缓冲、无 vsync。

---

## 四、开销实测（同一二进制、同一画面）

| 路径 | 单核占用 | 内存 |
|---|---|---|
| 厂商 `mali-fbdev` + EGL | 基线 | 基线 |
| 自写 `/dev/fb0` 直写 | **低约 9%** | **少约 5 MB** |

测法（HZ=100 的嵌入式 Linux）：

```sh
awk '{print $14+$15}' /proc/$pid/stat      # utime+stime，隔 10 s 取两次
awk '/VmRSS/{print $2}' /proc/$pid/status
```

直观解释：厂商后端名叫 `mali-fbdev`，它最终也写 fb0，只是多走了 EGL 上下文、整帧纹理上传与驱动合成。直写省掉这三步。

---

## 五、限制（如实写）

1. **和 MainUI 抢屏**：MainUI 也在刷 fb0。通过 SSH 直跑会被盖掉；必须由 `launch.sh` 先 `kill -STOP MainUI`。这不是缺陷，是"直写"的固有代价，4in1 也要启动器配合。
2. **无 vsync**：快速横移可能撕裂；要解决得用 `FBIOPAN_DISPLAY` 双缓冲。
3. **过场视频跳过**：要支持得把解码帧逐帧 `JY_FbBlit`，本次未做。
4. **不能靠 LD_PRELOAD 修 VT 卡死**：`ioctl(VT_WAITACTIVE)` 在本机永不返回（`wchan=__vt_event_wait`），只能靠 LD_PRELOAD 拦截；这是 4in1 那条线的结论，与直写无关，写在这里避免后来者重试。
5. `fbset` 不支持模式名切换（无 `/etc/fb.modes`），只能 `fbset -g` 改几何。

---

## 六、开关一览

```sh
export JY_FBDEV=1        # 开直写；不设则走原 EGL 路径（保证零回归）
```

出现问题时**第一步永远是去掉这一行**，确认原路径正常，再回到直写排查。
