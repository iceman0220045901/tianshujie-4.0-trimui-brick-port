# 补丁脚本说明

这些是**当时实际执行过的** PowerShell 补丁脚本（原样保留，含绝对路径），用于在原始引擎源码上幂等地打补丁。换机器时请把路径改成自己的。

## 执行顺序（新解压一份引擎源码后，按此顺序跑）

```
patch_luafun.ps1        # Lua 侧 API（LoadPicture 透传 zoom 等）
patch2.ps1 ~ patch5.ps1 # 逐步修的零散问题
patch_cfg.ps1           # 配置项（MP3 标志等）
patch_getpath.ps1       # 资源路径（大小写不敏感匹配）
patch_fbdev.ps1         # 直写 /dev/fb0 后端（第一版）
patch_fbdev2.ps1        # 直写第二版（缩放/映射表）
patch_fbdev3.ps1        # 直写第三版（遮罩合成）
patch_keylog.ps1        # JY_KEYLOG 按键日志
patch_diag.ps1 / 2      # 诊断开关（BGM/音频/fb 日志）
```

## 编译

```powershell
.\build.ps1        # release（-O2）
.\build_dbg.ps1    # 诊断版（打开错误日志宏，静默退出时用这份定位）
```

## 注意

- 脚本是**幂等**的：重复执行不会重复插入代码；执行结果写 `build\patch-*-report.txt`。
- `build.ps1` 必须保存为 **UTF-8 with BOM**，否则中文路径下 PowerShell 解析失败。
- 这些脚本是"当时的施工记录"，用于说明**改了哪些位置**；如果你要自己复刻，建议对照 `docs/03`、`docs/06`、`docs/08` 的代码片段手动改一遍，更可控。
