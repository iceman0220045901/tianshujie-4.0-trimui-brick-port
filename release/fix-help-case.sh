#!/bin/sh
# 修正内置攻略目录大小写：引擎请求 data/Help/（大写 H），4.0 原包是 data/help。
# 这块 FAT32 按大小写敏感解析文件名，且"只改大小写"的 mv 会失败，所以必须两步。
# 用法：把本脚本放在端口目录（含 data/ 的那一层）执行：  sh fix-help-case.sh
set -e
cd "$(dirname "$0")"
cd data

if [ -d Help ] && [ ! -d help ]; then
    echo "[OK] data/Help 已存在，无需修改"
elif [ -d help ] && [ ! -d Help ]; then
    n=$(ls help/*.txt 2>/dev/null | wc -l)
    echo "[INFO] 发现 data/help（$n 个 txt），开始改名"
    mv help help_tmp
    mkdir Help
    cp help_tmp/*.txt Help/
    mv help_tmp help_orig_lowercase
    echo "[OK] 已建立 data/Help（$(ls Help/*.txt | wc -l) 个 txt），原目录备份为 data/help_orig_lowercase"
elif [ -d help ] && [ -d Help ]; then
    echo "[WARN] data/help 与 data/Help 同时存在，请人工确认保留哪一份"
else
    echo "[ERR] 没有找到 data/help 或 data/Help —— 请确认游戏数据已解压到端口目录"
    exit 1
fi

echo "继续：进入游戏 → 系统 → 系统攻略，应能看到 16 本书"
echo "以后更新攻略：直接覆盖 data/Help/*.txt，行尾 '十六进制数' 标记不要动（否则剧情变色失效）"
