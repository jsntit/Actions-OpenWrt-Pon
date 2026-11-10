#!/bin/bash
#
# 基于 P3TERX/Actions-OpenWrt 模板改造
# File name: diy-part2.sh
# Description: PonWrt DIY script part 2（在 .config 加载之后运行，cwd = ponwrt 根目录）
#
#   1) 时区 Asia/Shanghai (CST-8)
#   2) 默认 LAN 地址 192.168.1.1 -> 10.0.0.1（掩码沿用上游 255.255.255.0 = /24）
#   3) failsafe 预启动网络同步为 10.0.0.1/24（不改的话进 failsafe 连不上）
#
# 本仓库原则：**除下面这三项，其余全部保持 ponwrt 上游默认**。
#   - 不改主机名（上游 OpenWrt）
#   - 不改主题（ponwrt 用 ImmortalWrt 的 luci feeds，默认已是 argon）
#   - 不加固件版本后缀（保持上游 DISTRIB_DESCRIPTION 原样）
#
# 想改其中任何一项时，在对应位置显式加回改写逻辑即可。
#

set -euo pipefail

echo "=========================================="
echo "默认值定制：时区 + LAN 地址 + failsafe 地址 (diy-part2.sh)"
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

# ---------------------------------------------------------
# 3. failsafe 预启动网络 -> 10.0.0.1/24
#
#    和上面第 2 段是**两套独立的东西**，必须一起改：
#
#      config_generate         → 首启生成的 /etc/config/network，正常 LAN
#      CONFIG_TARGET_PREINIT_* → /lib/preinit/00_preinit.conf 的 pi_ip，
#                                掉电中断启动 3 次 / 长按 reset 进的
#                                failsafe 恢复模式用的网段
#
#    只改前者的话，进了 failsafe 还是 192.168.1.1，得把电脑改回 192.168.1.x
#    才能连上 —— 而 192.168.1.x 往往正是光猫/主路由占着的网段，等于进不去。
#
#    pi_ip 不是静态文件：package/base-files/Makefile:93 在编译期现拼的
#        echo 'pi_ip=$(if $(CONFIG_TARGET_PREINIT_IP),$(CONFIG_TARGET_PREINIT_IP),"192.168.1.1")'
#    所以改 .config 就够了，**不用**动 base-files/Makefile。
#    （README 里「还要改 base-files/Makefile 的 pi_ip」那句是多余的，已更正。）
#
#    ⚠ 只改 .config **不够**。上面那个符号的定义是：
#        config TARGET_PREINIT_IP
#          string
#          prompt "IP address for preinit network messages" if PREINITOPT
#          default "192.168.1.1"
#      而本分支的 config 是 `# CONFIG_IMAGEOPT is not set` +
#      `# CONFIG_PREINITOPT is not set` → prompt 的两个条件都不成立 →
#      符号**不可见** → kconfig 的 defconfig 模式按 default 重算，
#      这里写进去的 10.0.0.1 每次都被抹回 192.168.1.1。
#      （2026-11-10 run 42756018562 就是被这道校验拦下的：
#        「预启动 IP：期望 10.0.0.1 / 实际 192.168.1.1」。）
#
#      所以下面除了改 .config，还必须改 image-config.in 的 default（第 3b 段）。
#      .config 那两行仍然保留：万一以后有人打开 PREINITOPT=y，它就是权威值。
# ---------------------------------------------------------
if [ -f .config ]; then
  sed -i 's|^CONFIG_TARGET_PREINIT_IP=.*|CONFIG_TARGET_PREINIT_IP="10.0.0.1"|' .config
  sed -i 's|^CONFIG_TARGET_PREINIT_BROADCAST=.*|CONFIG_TARGET_PREINIT_BROADCAST="10.0.0.255"|' .config

  if grep -q '^CONFIG_TARGET_PREINIT_IP="10.0.0.1"' .config; then
    echo "✅ failsafe 预启动地址 -> 10.0.0.1/24（pi_ip / pi_broadcast）"
  else
    echo "::error::config 里没有 CONFIG_TARGET_PREINIT_IP，或替换失败"
    grep -n 'CONFIG_TARGET_PREINIT' .config | sed 's/^/::error::  /' || true
    exit 1
  fi

  # 掩码保持 /24 不动，只提示一下，免得以后有人以为漏改了
  grep -q '^CONFIG_TARGET_PREINIT_NETMASK="255.255.255.0"' .config \
    && echo "   （掩码沿用 255.255.255.0 = /24）" \
    || echo "::warning::CONFIG_TARGET_PREINIT_NETMASK 不是 255.255.255.0，failsafe 网段可能不是 /24"
else
  echo "::warning::当前目录没有 .config，跳过 failsafe 地址修改"
fi


# ---------------------------------------------------------
# 3b. 把 PREINIT 两个符号的 Kconfig **default** 一起改掉
#
#     kconfig 的 defconfig 模式下，「不可见符号一律按 default 重算」，
#     所以改 .config 是无效的，只有改 default 才能在 defconfig 之后仍然成立。
#
#     这两个 default 在 image-config.in 里各只有一处（已核对）：
#       94:	default "192.168.1.1"     → TARGET_PREINIT_IP
#      110:	default "192.168.1.255"   → TARGET_PREINIT_BROADCAST
#     TARGET_PREINIT_NETMASK 的 default 本来就是 255.255.255.0，不用动。
# ---------------------------------------------------------
IMGIN="package/base-files/image-config.in"
if [ -f "$IMGIN" ]; then
  sed -i 's|^\([[:space:]]*default \)"192\.168\.1\.1"$|\1"10.0.0.1"|' "$IMGIN"
  sed -i 's|^\([[:space:]]*default \)"192\.168\.1\.255"$|\1"10.0.0.255"|' "$IMGIN"
  if grep -q 'default "10.0.0.1"' "$IMGIN" && grep -q 'default "10.0.0.255"' "$IMGIN"; then
    echo "✅ image-config.in：PREINIT_IP / PREINIT_BROADCAST 的 default -> 10.0.0.1 / 10.0.0.255"
  else
    echo "::error::$IMGIN 里没找到 PREINIT 的 default，上游结构可能已变"
    grep -n 'TARGET_PREINIT_IP\|TARGET_PREINIT_BROADCAST\|default "192\.168' "$IMGIN" | sed 's/^/::error::  /' || true
    exit 1
  fi
else
  echo "::warning::未找到 $IMGIN，跳过 PREINIT default 修改"
fi

echo "=========================================="
echo "diy-part2.sh 完成"
echo "=========================================="
