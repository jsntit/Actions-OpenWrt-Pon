#!/bin/bash
#
# 基于 P3TERX/Actions-OpenWrt 模板改造
# File name: diy-part2.sh
# Description: PonWrt DIY script part 2（在 .config 加载之后运行，cwd = ponwrt 根目录）
#
#   1) 时区 Asia/Shanghai (CST-8)
#
# 本仓库原则：**除下面这一项，其余全部保持 ponwrt 上游默认**。
#   - 不改默认 LAN 地址（上游 192.168.1.1）
#   - 不改主机名（上游 OpenWrt）
#   - 不改主题（ponwrt 用 ImmortalWrt 的 luci feeds，默认已是 argon）
#   - 不加固件版本后缀（保持上游 DISTRIB_DESCRIPTION 原样）
#
# 想改其中任何一项时，在对应位置显式加回改写逻辑即可。
#

set -euo pipefail

echo "=========================================="
echo "默认值定制：时区 (diy-part2.sh)"
echo "=========================================="

# ---------------------------------------------------------
# 1. 修改 config_generate 的默认值（首次开机生成的 /etc/config/system）
#   只动时区，LAN / 主机名等保持上游。
# ---------------------------------------------------------
CFG="package/base-files/files/bin/config_generate"

if [ -f "$CFG" ]; then
  sed -i "s/option timezone.*/option timezone 'CST-8'/" "$CFG"
  sed -i "s/option zonename.*/option zonename 'Asia\/Shanghai'/" "$CFG"
  echo "✅ config_generate 默认时区 -> CST-8 / Asia/Shanghai"
else
  echo "::warning::未找到 $CFG，跳过默认值修改"
fi

echo "=========================================="
echo "diy-part2.sh 完成"
echo "=========================================="
