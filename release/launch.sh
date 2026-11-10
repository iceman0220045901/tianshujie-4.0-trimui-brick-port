#!/bin/sh
# =============================================================================
# 天书劫 4.0 原味强化版 —— TrimUI Brick（吹米）Ports 启动脚本
# -----------------------------------------------------------------------------
# 显示：直写 /dev/fb0；内部渲染面 1280×720（与 4.0 排版一致），
#       输出 0.8 缩到 1024×576（满宽不变形），上下 96 px 用机框遮罩盖住。
# 输入：gptokeyb 把掌机手柄翻译成键盘按键再喂给引擎（引擎只认 SDL 键盘事件）。
# 音频：BGM/音效默认打开，音量 50/40。
# 立绘：固定框 146（大图缩、小图放大，与旧版天书劫同档）。
#
# 想回到 Mali/EGL 原路径：去掉 JY_FBDEV 这一行（或改用 start-mali.sh）
# 想纯黑边：注释 JY_FB_OVERLAY 这一行
# =============================================================================
cd "$(dirname "$0")" || exit 1
ulimit -n 4096 2>/dev/null

# MainUI 会一直往 /dev/fb0 重绘主页，会和直写抢屏；运行期间先挂起，退出后恢复。
# 用标志文件记录，重复启动时只有第一个挂起、只恢复一次。
MAINUI_PID=$(pidof MainUI)
if [ -n "$MAINUI_PID" ] && [ ! -f /tmp/jy4_ui_paused ]; then
    kill -STOP $MAINUI_PID 2>/dev/null
    echo "$MAINUI_PID" > /tmp/jy4_ui_paused
fi

resume_mainui() {
    if [ -f /tmp/jy4_ui_paused ]; then
        kill -CONT $(cat /tmp/jy4_ui_paused) 2>/dev/null
        rm -f /tmp/jy4_ui_paused
    fi
}
cleanup() {
    [ -n "$GPTOKEYB_PID" ] && kill -9 $GPTOKEYB_PID 2>/dev/null
    resume_mainui
}
trap 'cleanup' EXIT INT TERM

# gptokeyb 自身也依赖 SDL2，必须在启动前就把库路径导好，
# 否则从 SSH 或某些启动路径进来时会找不到库、手柄映射静默失效。
export LD_LIBRARY_PATH="$PWD/lib:/usr/trimui/lib:/usr/lib:"
if [ -f ./gamecontrollerdb.txt ]; then
    export SDL_GAMECONTROLLERCONFIG_FILE="$PWD/gamecontrollerdb.txt"
fi
export SDL_AUDIODRIVER=dummy

# ---- 显示 ----
export JY_FBDEV=1
export JY_SURF_W=1280          # = set.ini 的 CONFIG.Width，不要动，否则左右裁边
export JY_SURF_H=720
export JY_FB_SCALE=0.8         # 1280×720 → 1024×576，满宽、不变形
export JY_FB_MASK=000000
export JY_FB_OVERLAY=overlays/bars-crt.png
# 备选遮罩：
#   overlays/bars-crt2.png     CRT 框上下边带拉伸版
#   overlays/bars-wsc.png      WonderSwan Color 机身
#   overlays/crt-visible.png   整圈 CRT 框（需同时把 JY_FB_SCALE 改 0.75）
# 想让画面拉伸铺满（上下不留边）：JY_FB_SCALE=0 并注释上面 overlay 行

# ---- 音频 ----
export JY_MUSIC_VOL=50
export JY_SOUND_VOL=40
# 引擎默认把 JY.EnableMusic / EnableSound 置 1（进游戏即有 BGM）；
# 想恢复 4.0 原版"默认关闭"，加一行：export JY_MUSIC_DEFAULT=0

# ---- 立绘 ----
export JY_HEAD_FIT=146         # 固定框：最长边恒等 146（旧版天书劫对话立绘同档）
export JY_HEAD_MAX=0           # 关闭"最长边封顶"，与 JY_HEAD_FIT 不要同时用
# 战斗属性立绘旧版是 130；若想让战斗那档小一点，需要引擎侧单独加开关（当前未做）

# ---- 输入：手柄 → 键盘映射（跟随游戏进程，游戏退出它自己收工）----
GPTOKEYB_PID=""
if [ -x ./gptokeyb ] && [ -f ./jysdllua.gptk ]; then
    ./gptokeyb -k "jysdllua" -c "./jysdllua.gptk" > /tmp/jysdlbh_gptk.log 2>&1 &
    GPTOKEYB_PID=$!
    sleep 1
fi

run_game() {
    START_TS=$(date +%s)
    ./jysdllua > /tmp/jysdlbh.log 2>&1
    CODE=$?
    ELAPSED=$(( $(date +%s) - START_TS ))
    echo "$(date +%T) exit code=$CODE elapsed=${ELAPSED}s gptk=$(pidof gptokeyb)" >> /tmp/jysdlbh_diag.log
}

run_game
# 极短时间就退出（读卡抖动/初始化失败）时重试一次；重试前把手柄映射重新拉起来
if [ "$ELAPSED" -lt 15 ]; then
    echo "$(date +%T) fast exit (${ELAPSED}s), retrying once" >> /tmp/jysdlbh_diag.log
    sleep 2
    if [ -x ./gptokeyb ] && [ -f ./jysdllua.gptk ]; then
        ./gptokeyb -k "jysdllua" -c "./jysdllua.gptk" > /tmp/jysdlbh_gptk.log 2>&1 &
        GPTOKEYB_PID=$!
        sleep 1
    fi
    run_game
fi

cleanup
