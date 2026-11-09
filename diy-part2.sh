#!/bin/bash
#
# 基于 P3TERX/Actions-OpenWrt 模板改造
# File name: diy-part2.sh
# Description: PonWrt DIY script part 2（在 .config 加载之后运行，cwd = ponwrt 根目录）
#
#   1) 时区 Asia/Shanghai (CST-8)
#   2) 默认 LAN 地址 192.168.1.1 -> 10.0.0.1（掩码沿用上游 255.255.255.0 = /24）
#
# 本仓库原则：**除下面这两项，其余全部保持 ponwrt 上游默认**。
#   - 不改主机名（上游 OpenWrt）
#   - 不改主题（ponwrt 用 ImmortalWrt 的 luci feeds，默认已是 argon）
#   - 不加固件版本后缀（保持上游 DISTRIB_DESCRIPTION 原样）
#
# 想改其中任何一项时，在对应位置显式加回改写逻辑即可。
#

set -euo pipefail

echo "=========================================="
echo "默认值定制：时区 + LAN 地址 (diy-part2.sh)"
echo "=========================================="

# ---------------------------------------------------------
# 1. 修改 config_generate 的默认值（首次开机生成的 /etc/config/system）
#    只动时区，主机名等保持上游。
# ---------------------------------------------------------
CFG="package/base-files/files/bin/config_generate"

if [ -f "$CFG" ]; then
  sed -i "s/option timezone.*/option timezone 'CST-8'/" "$CFG"
  sed -i "s/option zonename.*/option zonename 'Asia\/Shanghai'/" "$CFG"
  echo "✅ config_generate 默认时区 -> CST-8 / Asia/Shanghai"
else
  echo "::warning::未找到 $CFG，跳过默认值修改"
fi

# ---------------------------------------------------------
# 2. 默认 LAN 地址 -> 10.0.0.1/24
#
#    上游 package/base-files/files/bin/config_generate 里唯一一处：
#        lan) ipad=${ipaddr:-"192.168.1.1"} ;;
#    下面那行 `*) ipad=${ipaddr:-"192.168.$((addr_offset++)).1"}` 是「第二个
#    及以后的接口」的自动分配，**不要动**。
#
#    掩码不动：紧接着的 netm=${netmask:-"255.255.255.0"} 就是 /24，
#    正好对应 10.0.0.1/24。
#
#    作用范围：只影响「首次开机/恢复出厂」时生成的 /etc/config/network。
#    已经刷过并配好网的路由器升级固件时，sysupgrade 默认保留旧配置，
#    LAN IP 不会变 —— 需要手工改或刷机时不保留配置。
# ---------------------------------------------------------
if [ -f "$CFG" ]; then
  sed -i 's|lan) ipad=\${ipaddr:-"192.168.1.1"} ;;|lan) ipad=\${ipaddr:-"10.0.0.1"} ;;|' "$CFG"
  if grep -q 'lan) ipad=\${ipaddr:-"10.0.0.1"}' "$CFG"; then
    echo "✅ config_generate 默认 LAN -> 10.0.0.1/24（掩码沿用上游 255.255.255.0）"
  else
    echo "::error::默认 LAN 地址替换失败，上游 config_generate 结构可能已变"
    echo "::error::当前 lan) 行："
    grep -n 'lan) ipad' "$CFG" | sed 's/^/::error::  /' || true
    exit 1
  fi
else
  echo "::warning::未找到 $CFG，跳过默认 LAN 地址修改"
fi

echo "=========================================="
echo "diy-part2.sh 完成"
echo "=========================================="
