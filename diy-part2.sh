#!/bin/bash
#
# 基于 P3TERX/Actions-OpenWrt 模板改造
# File name: diy-part2.sh
# Description: PonWrt DIY script part 2（在 .config 加载之后运行，cwd = ponwrt 根目录）
#
#   1) 时区 Asia/Shanghai (CST-8)
#   2) 固件版本追加作者与构建时间
#
# 说明：本仓库刻意**不改默认 LAN 地址**，保持 ponwrt 上游的 192.168.1.1。
#   之前一度沿用另一个仓库（Actions-OpenWrt-AN758X）的 10.0.0.1 方案，
#   已整体撤销 —— 本仓库的定位是「干净的上游源」，未要求的改动一律不加。
#
#   确实要换网段时，在 workflow 里加 LAN_IP / LAN_NETMASK / LAN_BROADCAST
#   环境变量是不生效的（这里已经不再读它们），需要在此文件里显式加回改写逻辑。
#
# 模板原版的「改主题」「改主机名」两段保持注释状态：
#   ponwrt 用的是 ImmortalWrt 的 luci feeds，主题默认就是 argon；
#   主机名保持 OpenWrt。
#

set -euo pipefail

echo "=========================================="
echo "默认值定制：时区 + 版本后缀 (diy-part2.sh)"
echo "=========================================="

# 固件版本后缀（经 workflow 的 env 注入；本地单独跑时默认 qwe）
FW_AUTHOR="${FW_AUTHOR:-qwe}"
FW_BUILD_TIME="${FW_BUILD_TIME:-}"

echo "配置：FW_AUTHOR=$FW_AUTHOR"

# ---------------------------------------------------------
# 1. 修改 config_generate 的默认值（首次开机生成的 /etc/config/system）
#   仅动时区，LAN / 主机名等保持上游。
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
# 2. 固件版本后缀追加作者与构建时间
#   写进 files/etc/uci-defaults/，首启时改 /etc/openwrt_release 的
#   DISTRIB_DESCRIPTION，LuCI 概览页「固件版本」那行能看到。
# ---------------------------------------------------------
FW_TIME="${FW_BUILD_TIME:-$(date +'%Y-%m-%d %H:%M')}"
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/93-fw-version <<UCEOF
#!/bin/sh
# 由 diy-part2.sh 生成：在固件版本后面追加作者与构建时间
REL=/etc/openwrt_release
[ -f "\$REL" ] || exit 0
DESC=\$(. "\$REL" >/dev/null 2>&1; echo "\$DISTRIB_DESCRIPTION")
case "\$DESC" in
	*"$FW_AUTHOR"*) ;;
	*)
		sed -i "s|^DISTRIB_DESCRIPTION=.*|DISTRIB_DESCRIPTION='\$DESC · $FW_AUTHOR · $FW_TIME'|" "\$REL"
		;;
esac
exit 0
UCEOF
chmod +x files/etc/uci-defaults/93-fw-version
echo "✅ 固件版本后缀脚本已写入：· $FW_AUTHOR · $FW_TIME"

echo "=========================================="
echo "diy-part2.sh 完成"
echo "=========================================="
