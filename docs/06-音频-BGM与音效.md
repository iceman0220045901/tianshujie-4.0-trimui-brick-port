# 06 · 音频：BGM 与音效

---

## 一、先排环境，再动代码

出现「完全没声音」时最容易误判成驱动/ALSA 问题。本例先逐个排除：

| 检查 | 结果 |
|---|---|
| `/dev/snd` 节点 | 齐全 |
| `/proc/asound/cards` | 有 `audiocodec` |
| `amixer` | `HpSpeaker Switch on`、`DAC volume 160` 正常 |
| `aplay` | MainUI 运行/挂起两种状态下都能出声（`rc=0`） |

→ **音频设备可共享，没有被 MainUI 独占**。问题在引擎和素材。

---

## 二、BGM 的四条真因 + 一条默认开关

### ① 用错了解码入口（决定性）

`JY_PlayMIDI()` 用 `BASS_StreamCreateFile()` 创建流 —— 那是 BASS 核心的通用入口，**核心不认 MIDI**，返回 `code=41`（不支持格式），路径完全正确也失败。引擎明明链着 bassmidi。

```c
/* 修法：先 MIDI 入口，失败再回落通用入口（mp3/wav 曲目仍走通用） */
HSTREAM h = BASS_MIDI_StreamCreateFile(FALSE, path, 0, 0, 0);
if (!h) h = BASS_StreamCreateFile(FALSE, path, 0, 0, 0);
```

### ② 素材大小写不匹配

脚本拼 `game%02d.mid`（小写），卡上实际是 `game01.MID … game29.MID`（29 个大写）+ 一个 `game25.mid`。**这块 FAT32 区分大小写**，小写路径必然打不开。

```c
/* JY_FixAudioPath()：access() 原路径失败后，依次试 .MID/.MP3/.mp3/.mid */
diag: music case-fix [data/sound/game01.mid] -> [data/sound/game01.MID]
```

### ③ `CONFIG.MP3` 原本是 1

`InitSDL` 里 `if (g_MP3 != 1) { BASS_MIDI_FontInit(...) }` —— MP3=1 时**音色库根本不挂**，MIDI 流创建成功也是静音。而 4.0 的 `set.ini` 原配正是 `MP3=1`，脚本在 MP3=1 时还会去找 `game%02d.mp3`（`data/sound` 里有 **0 个 mp3**）。

→ `set.ini` 改回 **`CONFIG.MP3 = 0`**（日志 `diag: font=1 code=0`）。

### ④ 音量只有 20 / 10

4.0 默认 `MusicVolume 20` / `SoundVolume 10`，掌机小喇叭几乎听不见。引擎加环境变量覆盖：

```sh
export JY_MUSIC_VOL=50
export JY_SOUND_VOL=40
```

### ⑤ 默认是关的（每次进游戏都要手动开）

`JY.EnableMusic` / `JY.EnableSound` 默认关。引擎在调用 Lua 主函数 `JY_Main` 之前直接置 1：

```c
const char* mv = getenv("JY_MUSIC_DEFAULT");
if (mv == NULL || atoi(mv) != 0) {
    lua_getglobal(pL_main, "JY");
    if (lua_istable(pL_main, -1)) {
        lua_pushboolean(pL_main, 1); lua_setfield(pL_main, -2, "EnableMusic");
        lua_pushboolean(pL_main, 1); lua_setfield(pL_main, -2, "EnableSound");
    }
    lua_pop(pL_main, 1);
}
```

`JY_MUSIC_DEFAULT=0` 可还原原版行为（默认关）。

---

## 三、修好后的证据

强制自检 `JY_BGM_TEST=1`（引擎启动即点播 `game01`）：

```
diag: mp3=0 musicVol=50 soundVol=40 so=22050 sf2=[./data/sound/mid.sf2]
diag: font=1 code=0 path=[./data/sound/mid.sf2]
diag: PlayMIDI called [data/sound/game01.mid]
diag: music case-fix [data/sound/game01.mid] -> [data/sound/game01.MID]
diag: music play OK [data/sound/game01.mid] vol=50 active=1
```

`active=1` = `BASS_ACTIVE_PLAYING`。修复前同一条路径是 `code=41`。

真机开场路径上也验证过：`PlayMIDI called [./data/sound/game20.mid]` → `case-fix -> .MID` → `active=1`，随后切 `game03.MID` 同样 `active=1`。

---

## 四、音效（已确认可用）

- 早期日志里出现过 `sfx FAIL code=2`（`code=2` 是"文件打不开"），根因与 BGM 同源：**路径解析与文件名大小写**；
- 修 `JY_FixAudioPath()`（逐扩展名重试）与大小写不敏感比较（`jy_ci_equal`）之后，音效与 BGM 走同一套兜底；
- 通道上两者是分开的：BGM 走 BASSMIDI 的 stream（`.mid` + `.sf2` 音色库），音效走 sample 通道，互不抢占；
- `JY_SOUND_VOL` 由 10 提到 **40**（小喇叭上 10 基本等于静音）；
- **真机确认**：进战斗、出招、受击都能听到音效；进入游戏后 BGM 与音效同时正常。

排查口径（万一以后又坏）：`JY_SOUND_VOL=60`、`JY_BGM_DBG=1` 打开 Lua 侧 `JY_Debug`，看 `fbdev.txt` 里有没有 `sfx` 行；若出现 `FAIL code=N` 就按 BASS 错误码判：`code=2` 优先查文件是否真的存在、扩展名大小写是否一致。

---

## 五、诊断开关一览

| 变量 | 作用 |
|---|---|
| `JY_BGM_DBG=1` | 打开 Lua 侧调试输出（`debug.txt`） |
| `JY_BGM_TEST=1` | 引擎启动即点播 `game01`，验证音频链路 |
| `JY_MUSIC_VOL` / `JY_SOUND_VOL` | 覆盖音量（0–100），现为 50 / 40 |
| `JY_MUSIC_DEFAULT=0` | 回到「默认关闭音乐/音效」的原版行为 |

日志统一在端口目录 `fbdev.txt`（或 `debug.txt`）：`PlayMIDI called` → `music open` →（必要时 `case-fix`）→ `music play OK` / `music FAIL code=N`，一条链能看完。

---

## 六、教训

1. **MIDI 一定走 `BASS_MIDI_*`**，`BASS_StreamCreateFile` 不认 MIDI；
2. 音色库（`.sf2`）是否挂上，看 `CONFIG.MP3`，不要只看路径；
3. 老游戏在 Windows 上"大小写随便写"，到 FAT32 上就是**逐个扩展名都要对**；
4. 小喇叭上 20/10 的音量等于静音，先怀疑音量再怀疑解码。
