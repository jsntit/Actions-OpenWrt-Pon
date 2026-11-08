#!/bin/bash
#
# 基于 P3TERX/Actions-OpenWrt 模板改造
# File name: diy-part2.sh
# Description: PonWrt DIY script part 2（在 .config 加载之后运行，cwd = ponwrt 根目录）
#
#   1) 时区 Asia/Shanghai (CST-8)
#   1b) 默认 LAN 地址 10.0.0.1
#   1c) failsafe / 预启动网络同步到 10.0.0.1
#   2) 固件版本追加作者与构建时间
#
# 说明：模板原版的「改主题」「改主机名」两段保持注释状态。
#   ponwrt 用的是 ImmortalWrt 的 luci feeds，主题默认就是 argon，
#   不需要把 bootstrap 换成 argon；主机名保持 OpenWrt。
#

set -euo pipefail

echo "=========================================="
echo "默认值定制：时区 + LAN IP (diy-part2.sh)"
echo "=========================================="

# 默认 LAN 地址（编译期常量，写进 config_generate 与 uci-defaults 脚本）
# 想换网段就改这里；failsafe 的预启动网络也跟这个走。
# 也可以用环境变量覆盖：LAN_IP=192.168.5.1 LAN_BROADCAST=192.168.5.255
LAN_IP="${LAN_IP:-10.0.0.1}"
LAN_NETMASK="${LAN_NETMASK:-255.255.255.0}"
LAN_BROADCAST="${LAN_BROADCAST:-10.0.0.255}"

# 固件版本后缀（经 workflow 的 env 注入；本地单独跑时默认 qwe）
FW_AUTHOR="${FW_AUTHOR:-qwe}"
FW_BUILD_TIME="${FW_BUILD_TIME:-}"

echo "配置：LAN=$LAN_IP/$LAN_NETMASK broadcast=$LAN_BROADCAST"
echo "配置：FW_AUTHOR=$FW_AUTHOR"

# ---------------------------------------------------------
# 1. 修改 config_generate 的默认值（首次开机生成的 /etc/config/system）
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
# 1b. 默认 LAN 地址 -> $LAN_IP
#   两层：
#   a) 编译期改 config_generate 里的 lan 默认值 —— 全新刷机、恢复出厂都是它。
#      前提是 CONFIG_TARGET_DEFAULT_LAN_IP_FROM_PREINIT 没开；开了的话
#      board.json 的 lan.ipaddr 优先级更高，会盖掉这里。
#      实测 pbs05/ponwrt 的 image-config.in 里该符号 default n，安全。
#   b) 运行期 uci-defaults 兜底 —— 保留配置升级时 /etc/config/network 已存在，
#      光改 config_generate 不生效，靠脚本改写；但只在地址仍是出厂默认
#      192.168.1.1（或为空）时才动手，用户自己改过的网段不动。
# ---------------------------------------------------------
if [ -f "$CFG" ]; then
  if grep -qF 'lan) ipad=${ipaddr:-"192.168.1.1"} ;;' "$CFG"; then
    sed -i "s|lan) ipad=\${ipaddr:-\"192\.168\.1\.1\"} ;;|lan) ipad=\${ipaddr:-\"$LAN_IP\"} ;;|" "$CFG"
    echo "✅ config_generate 默认 LAN 地址 -> $LAN_IP"
  elif grep -qF "lan) ipad=\${ipaddr:-\"$LAN_IP\"}" "$CFG"; then
    echo "ℹ config_generate 默认 LAN 地址已是 $LAN_IP，跳过"
  else
    echo "::warning::config_generate 里没匹配到预期的 lan 默认地址行（上游改写法了？），交由 uci-defaults 兜底"
  fi
fi

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/95-lan-ip <<UCEOF
#!/bin/sh
# 默认 LAN 地址：$LAN_IP
# 由 diy-part2.sh 生成（编译期常量注入）
# 只在仍是出厂默认 192.168.1.1 时才改写，用户自己调过的网段保持不动。

LAN_IP='$LAN_IP'
LAN_NETMASK='$LAN_NETMASK'

cur=\$(uci -q get network.lan.ipaddr)

case "\$cur" in
	""|192.168.1.1|192.168.1.1/*|192.168.1.1/*/*)
		# config_generate 写的是 list ipaddr 'x.x.x.x/24'，先删再设，
		# 保证变成单独 option，netmask 由下面这行给出
		uci -q delete network.lan.ipaddr
		uci -q set network.lan.proto='static'
		uci -q set network.lan.ipaddr="\$LAN_IP"
		uci -q set network.lan.netmask="\$LAN_NETMASK"
		uci -q commit network
		logger -t 95-lan-ip "默认 LAN 地址 \$cur -> \$LAN_IP"
		;;
	*)
		logger -t 95-lan-ip "LAN 已是 \$cur，保留自定义地址"
		;;
esac

exit 0
UCEOF
chmod +x files/etc/uci-defaults/95-lan-ip
echo "✅ uci-defaults LAN 地址脚本已写入：$LAN_IP/$LAN_NETMASK"

# ---------------------------------------------------------
# 1c. failsafe / 预启动网络同步到 $LAN_IP
#   进 failsafe 时用的是 pi_ip（写进 /lib/preinit/00_preinit.conf），
#   它的值来自 CONFIG_TARGET_PREINIT_IP，只有该符号为空才回落
#   base-files/Makefile 里硬编码的 192.168.1.1。所以两处都要改，
#   否则 LAN 换成 10.0.0.x 后进 failsafe 还得把电脑换回 192.168.1.x。
#
#   ⚠ 只写 .config 不够：TARGET_PREINIT_IP 的 prompt 在 `if PREINITOPT`
#   里，而基座里 PREINITOPT 是关的 —— 没有可见 prompt 的符号，
#   `make defconfig` 会按 default 重算，写进 .config 的值会被直接丢掉。
#   所以三层都要改。
# ---------------------------------------------------------
BF_MK="package/base-files/Makefile"
if [ -f "$BF_MK" ]; then
  sed -i "/pi_ip=/s|\"192\.168\.1\.1\"|\"$LAN_IP\"|" "$BF_MK"
  sed -i "/pi_broadcast=/s|\"192\.168\.1\.255\"|\"$LAN_BROADCAST\"|" "$BF_MK"
  # 这段在 ifeq CONFIG_TARGET_DEFAULT_LAN_IP_FROM_PREINIT,y 里，当前没开；
  # 万一哪天开了，board.json 的 lan.ipaddr 优先级更高，这里不改就会把
  # config_generate 的改动盖掉。
  sed -i "/json_add_string ipaddr/s|\"192\.168\.1\.1\"|\"$LAN_IP\"|" "$BF_MK"
  echo "✅ Makefile 里 pi_ip / pi_broadcast / 99-lan-ip 的默认值 -> $LAN_IP / $LAN_BROADCAST"
else
  echo "::warning::未找到 $BF_MK，跳过 preinit 兜底默认值修改"
fi

if [ -f .config ]; then
  # 先删掉旧的两种写法（含 is not set），再追加，避免 kconfig 报重复赋值
  sed -i '/^CONFIG_TARGET_PREINIT_IP=/d; /^# CONFIG_TARGET_PREINIT_IP is not set/d' .config
  echo "CONFIG_TARGET_PREINIT_IP=\"$LAN_IP\"" >> .config
  sed -i '/^CONFIG_TARGET_PREINIT_BROADCAST=/d; /^# CONFIG_TARGET_PREINIT_BROADCAST is not set/d' .config
  echo "CONFIG_TARGET_PREINIT_BROADCAST=\"$LAN_BROADCAST\"" >> .config
  echo "✅ .config 里 preinit 网络 -> $LAN_IP / $LAN_BROADCAST（failsafe 同网段）"
fi

# Kconfig 侧（决定性的一层）：见上面 1c 的说明
IMG_IN="package/base-files/image-config.in"
if [ -f "$IMG_IN" ]; then
  sed -i "/^config TARGET_PREINIT_IP\$/,/^config /s|^\([[:space:]]*default[[:space:]]*\)\"192\.168\.1\.1\"|\1\"$LAN_IP\"|" "$IMG_IN"
  sed -i "/^config TARGET_PREINIT_BROADCAST\$/,/^config /s|^\([[:space:]]*default[[:space:]]*\)\"192\.168\.1\.255\"|\1\"$LAN_BROADCAST\"|" "$IMG_IN"
  echo "✅ image-config.in 里 preinit 的 Kconfig 默认值 -> $LAN_IP / $LAN_BROADCAST"
else
  echo "::warning::未找到 $IMG_IN，preinit 默认值只有 .config 一层，可能被 defconfig 覆盖"
fi

# ---------------------------------------------------------
# 2. 固件版本后缀追加作者与构建时间
#   写进 files/etc/uci-defaults/，首启时改 /etc/openwrt_release 的
#   DISTRIB_DESCRIPTION，LuCI 概览页「固件版本」那行能看到。
# ---------------------------------------------------------
FW_TIME="${FW_BUILD_TIME:-$(date +'%Y-%m-%d %H:%M')}"
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
