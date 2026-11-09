#!/bin/bash
#
# 基于 P3TERX/Actions-OpenWrt 模板改造
# File name: diy-part1.sh
# Description: PonWrt DIY script part 1（在 feeds update 之前运行，cwd = ponwrt 根目录）
#
# 本仓库用途：把 pbs05/ponwrt 的 Airoha AN758x 平台编成固件。
# 这里只做「按需拉取额外插件」，默认只开 Airoha 状态页，其余全关贴近上游。
#
# ⚠ 模板原版会往 feeds.conf.default 追加 fw876/helloworld，这里刻意去掉了：
#   ponwrt 是 ImmortalWrt 系，feeds 里已有 immortalwrt/packages + immortalwrt/luci，
#   helloworld 里的 passwall / ssr-plus 等包与它们同名，索引里会出现两个同名
#   Package，scan.mk 按扫描顺序挑一个，行为不可预期。
#

set -o pipefail

echo "=========================================="
echo "拉取可选插件 (diy-part1.sh)"
echo "=========================================="

PKG_DIR="package/custom"
mkdir -p "$PKG_DIR"

clone() {  # clone <url> <dir> [branch]
  local url="$1" dir="$2" br="$3"
  [ -d "$dir" ] && { echo "已存在，跳过: $dir"; return 0; }
  echo "--- git clone $url -> $dir ---"
  if [ -n "$br" ]; then
    git clone --depth 1 -b "$br" "$url" "$dir" 2>&1 | tail -3
  else
    git clone --depth 1 "$url" "$dir" 2>&1 | tail -3
  fi
  if [ -d "$dir" ]; then
    echo "✅ 克隆成功: $dir"
    return 0
  fi
  echo "::error::克隆失败: $url"
  return 1
}

# ---------------------------------------------------------
# 插件开关
#
# ⚠ 开关和 .config 是两套东西，别混：
#   开关只决定「源码有没有被拉到 package/custom」，
#   .config 决定「编不编进去」。两处都要改才生效 ——
#   只开开关不改 config = 白拉；只改 config 不开开关 =
#   defconfig 把那个 =y 静默剔除（不报错，固件里就是没这个菜单）。
# ---------------------------------------------------------
ADD_AIROHA_NPU=true    # luci-app-airoha-npu：Airoha SoC 状态页（NPU/CPU/Frame Engine/PPE）
ADD_TAILSCALE_WHZHNI=true   # luci-app-tailscale（whzhni1 新版，自包含：自带 init.d/config/内核下载器）

# 本分支（for-maym）在 configs/*.config 里已经开了的包，feeds 里自带，不需要在这里 clone：
#     luci-app-homeproxy             ← immortalwrt/luci，依赖 sing-box / firewall4 /
#                                      kmod-nft-tproxy / ucode-mod-digest，全在现有 feeds 或主仓库
#   ⚠ tailscale 已从 feeds 版换成 whzhni1/luci-app-tailscale（见 ADD_TAILSCALE_WHZHNI）：
#     - 旧的 luci-app-tailscale-community 依赖 +tailscale（feeds/packages/net/tailscale），
#       而那个 tailscale 包会装 /etc/init.d/tailscale 和 /etc/config/tailscale；
#     - 新插件自己也装这两个文件 → 同时装必然文件冲突。
#     所以 config 里 tailscale 本体和 community 界面都已关掉，只留新插件。
#     新插件**不带 tailscaled 二进制**。它自带的 /etc/config/tailscale 默认
#     `option enabled '0'`（服务关闭），所以开机不会去下载；用户第一次在 LuCI
#     里把服务打开时，init.d 发现 /usr/sbin/tailscaled 缺失，才会后台跑
#     update.sh ensure-core 下载内核（镜像顺序 GitLab → Cloudflare R2 → GitHub），
#     装好自动重启服务。也可以在「核心」页手动触发。
#     ⚠ 所以第一次启用时必须能联网，否则拉不到内核；不影响路由器其他功能。
#     默认 mode=tun（需要 kmod-tun）、accept_dns=0（不接管 DNS）、
#     不宣告任何子网（advertise_routes 为空），这些默认值对家用是安全的。
#   （luci-app-frpc / luci-app-zerotier 在本分支是关掉的，要开就改 config 里的 =y）
#   保留下面几个变量只是为了「万一要换源」时有地方改，默认 false。
ADD_HOMEProxy=false    # 换成自己的 homeproxy 源时才置 true（默认用 feeds 里的）
ADD_PASSWALL2=false    # luci-app-passwall2（UI + openwrt-passwall-packages 后端）
ADD_OPENCLASH=false    # luci-app-openclash ⚠ 依赖 Ruby/Rust，编译极慢
ADD_MOSDNS=false       # luci-app-mosdns
ADD_LUCKY=false        # luci-app-lucky（DDNS + socat）

# ---------------------------------------------------------
# Airoha SoC 状态页（NPU 卸载 / CPU 频率 / Frame Engine / PPE 流表）
# 包名由目录名决定（luci.mk: PKG_NAME ?= $(notdir ${CURDIR})），
# 目录必须是 luci-app-airoha-npu，否则 config 里的符号对不上。
#
# 源用 luanmuc/luci-app-airoha-npu（rchen14b 的 fork 改进版）：
#   - 自带 po/zh_Hans 完整中文翻译（48 条）
#   - 无 rchen14b 那种「根目录 + 同名子目录」重复结构，feed 索引不会中断
#   - 修了 luci.mk 的 include 路径、加了独立 CPU 温度与 PLL 备用频率
# ---------------------------------------------------------
if [ "$ADD_AIROHA_NPU" = "true" ]; then
  if ! clone https://github.com/luanmuc/luci-app-airoha-npu "$PKG_DIR/luci-app-airoha-npu" main; then
    echo "::error::luci-app-airoha-npu 拉取失败，后续 defconfig 会静默剔除该包"
    exit 1
  fi
  # 包名校验：Makefile 必须存在，否则 buildroot 扫不到这个包
  if [ ! -f "$PKG_DIR/luci-app-airoha-npu/Makefile" ]; then
    echo "::error::$PKG_DIR/luci-app-airoha-npu/Makefile 不存在，包无法被索引"
    exit 1
  fi
  echo "   版本: $(grep -m1 '^PKG_VERSION' "$PKG_DIR/luci-app-airoha-npu/Makefile" 2>/dev/null)"

  # =========================================================
  # 关键：po 文件名必须改成 airoha-npu.po
  #   luci.mk 的 i18n 规则按 po 主名生成 lmo，运行时却按 LUCI_BASENAME
  #   （= airoha-npu）查找。上游两份 po 都叫 luci-app-airoha-npu.po，会生成
  #   luci-app-airoha-npu.zh-cn.lmo → 前端找不到 → 中文不生效。
  # =========================================================
  PODIR="$PKG_DIR/luci-app-airoha-npu/po"
  if [ -f "$PODIR/zh_Hans/luci-app-airoha-npu.po" ]; then
    # 确保 Language 头是 zh_Hans（上游头部缺该字段时 po2lmo 可能识别异常）
    grep -q '^"Language:' "$PODIR/zh_Hans/luci-app-airoha-npu.po" || \
      sed -i 's/^msgstr ""$/msgstr ""\n"Language: zh_Hans\\n"/' "$PODIR/zh_Hans/luci-app-airoha-npu.po"
    mv "$PODIR/zh_Hans/luci-app-airoha-npu.po" "$PODIR/zh_Hans/airoha-npu.po"
    echo "✅ po 改名: luci-app-airoha-npu.po -> airoha-npu.po（luci.mk 按 LUCI_BASENAME 查找）"
  fi
  if [ -f "$PODIR/es/luci-app-airoha-npu.po" ]; then
    mv "$PODIR/es/luci-app-airoha-npu.po" "$PODIR/es/airoha-npu.po"
  fi
  echo "   po/zh_Hans: $(ls -1 "$PODIR/zh_Hans/" 2>/dev/null | tr '\n' ' ')"
fi

# ---------------------------------------------------------
# tailscale 管理界面（whzhni1/luci-app-tailscale，新版 ucode 实现）
#
# 和 feeds 自带的 luci-app-tailscale-community 是**两套完全不同的东西**：
#   community 版 = 纯界面，靠 +tailscale（feeds/packages/net/tailscale）提供
#                  /usr/sbin/tailscaled + /etc/init.d/tailscale + /etc/config/tailscale
#   whzhni1 版  = 界面 + 自己的 init.d + 自己的 config + 内核在线更新器，
#                  **不带二进制**，首次启动时 init.d 会自动联网下载
#
# ⚠ 所以这两者**不能同时开**：/etc/init.d/tailscale 和 /etc/config/tailscale
#   会撞车，构建阶段后装的静默覆盖前面的，运行期行为不可预期。
#   config 里已经把关掉 base tailscale 包和 community 界面，只留本插件。
#
# 仓库是 monorepo，根下还有 .github / images / README 等，真正的包在
# luci-app-tailscale/ 子目录，必须**展平**拷进 $PKG_DIR（理由同 gecoosac：
# 整仓留在那里会触发脚本后方的「清理重复嵌套目录」逻辑误删内层 Makefile）。
#
# Makefile 用的是绝对路径 include：
#     include $(TOPDIR)/feeds/luci/luci.mk
# 原样保留即可，别改成 ../../luci.mk —— 那会解析到 package/luci.mk（不存在）。
# 前提是 diy-part1.sh 在 feeds update/install 之前跑（workflow 已保证）。
# ---------------------------------------------------------
if [ "$ADD_TAILSCALE_WHZHNI" = "true" ]; then
  TS_TMP="$(mktemp -d)/ts"
  if clone https://github.com/whzhni1/luci-app-tailscale "$TS_TMP" main \
     && [ -f "$TS_TMP/luci-app-tailscale/Makefile" ]; then
    rm -rf "$PKG_DIR/luci-app-tailscale"
    mv "$TS_TMP/luci-app-tailscale" "$PKG_DIR/luci-app-tailscale"
    echo "✅ 已展平: luci-app-tailscale"
    echo "   版本: $(grep -m1 '^PKG_VERSION' "$PKG_DIR/luci-app-tailscale/Makefile" 2>/dev/null)"
    echo "   自带文件: $(ls -1 "$PKG_DIR/luci-app-tailscale/root/etc/config" "$PKG_DIR/luci-app-tailscale/root/etc/init.d" 2>/dev/null | tr '\n' ' ')"
  else
    echo "::error::luci-app-tailscale 拉取失败或仓库结构变化，defconfig 会静默剔除"
    rm -rf "$TS_TMP"
    exit 1
  fi
  rm -rf "$(dirname "$TS_TMP")"
fi

# ---------------------------------------------------------
# homeproxy（immortalwrt/homeproxy：luci-app-homeproxy 一个包内含 UI + 守护进程，
# 依赖 +sing-box；sing-box 由 passwall2 的 openwrt-passwall-packages 或 feeds 提供）
# ---------------------------------------------------------
if [ "$ADD_HOMEProxy" = "true" ]; then
  clone https://github.com/immortalwrt/homeproxy "$PKG_DIR/homeproxy" master
fi

# ---------------------------------------------------------
# passwall2
# ⚠ 不要 clone xiaorouji/openwrt-passwall（v1 luci 仓库，现已 404）。
# ---------------------------------------------------------
if [ "$ADD_PASSWALL2" = "true" ]; then
  clone https://github.com/Openwrt-Passwall/openwrt-passwall2 "$PKG_DIR/openwrt-passwall2" main
  clone https://github.com/xiaorouji/openwrt-passwall-packages "$PKG_DIR/openwrt-passwall-packages" main
fi

# ---------------------------------------------------------
# openclash
# 仓库是 monorepo：根目录是 luci-app-openclash，需要把它拷出来
# ---------------------------------------------------------
if [ "$ADD_OPENCLASH" = "true" ]; then
  echo "::warning::OpenClash 会触发 Ruby/Rust 编译，耗时极长"
  clone https://github.com/vernesong/OpenClash "$PKG_DIR/OpenClash" master
  mv "$PKG_DIR/OpenClash/luci-app-openclash" "$PKG_DIR/luci-app-openclash" 2>/dev/null
  rm -rf "$PKG_DIR/OpenClash"
fi

# ---------------------------------------------------------
# mosdns
# ⚠ 只拷 luci-app-mosdns 子目录：仓库里还带 mosdns 本体与 v2ray-geodata，
#   两个都与 feeds 同名。本体用 feeds 的。
# ---------------------------------------------------------
if [ "$ADD_MOSDNS" = "true" ]; then
  MD_TMP="$(mktemp -d)/mosdns"
  if clone https://github.com/sbwml/luci-app-mosdns "$MD_TMP" v5 \
     && [ -f "$MD_TMP/luci-app-mosdns/Makefile" ]; then
    rm -rf "$PKG_DIR/luci-app-mosdns" "$PKG_DIR/geo2txt"
    cp -r "$MD_TMP/luci-app-mosdns" "$PKG_DIR/"
    # geo2txt 是 luci-app-mosdns 的硬依赖（LUCI_DEPENDS 里 +geo2txt），
    # feeds 里没有同名包，必须一起拷进来，否则索引时报
    # "has a dependency on 'geo2txt', which does not exist"
    if [ -f "$MD_TMP/geo2txt/Makefile" ]; then
      cp -r "$MD_TMP/geo2txt" "$PKG_DIR/"
      echo "✅ 已拷贝: geo2txt（luci-app-mosdns 依赖）"
    else
      echo "::warning::mosdns 仓库里没有 geo2txt，luci-app-mosdns 会缺这个依赖"
    fi
    echo "✅ 已拷贝: luci-app-mosdns（本体用 feeds）"
  else
    echo "::error::luci-app-mosdns 拉取失败或结构变化"
  fi
  rm -rf "$MD_TMP"
fi

# --- lucky ---
if [ "$ADD_LUCKY" = "true" ]; then
  clone https://github.com/sirpdboy/luci-app-lucky "$PKG_DIR/luci-app-lucky" main
fi

# ---------------------------------------------------------
# 校验：默认开启的插件必须拉到，否则 defconfig 会静默剔除
# ---------------------------------------------------------
if [ "$ADD_AIROHA_NPU" = "true" ] && [ ! -d "$PKG_DIR/luci-app-airoha-npu" ]; then
  echo "::error::luci-app-airoha-npu 未拉到，config 里的 =y 会被 defconfig 剔除"
  exit 1
fi

if [ "$ADD_TAILSCALE_WHZHNI" = "true" ] && [ ! -f "$PKG_DIR/luci-app-tailscale/Makefile" ]; then
  echo "::error::luci-app-tailscale 未拉到（或没展平），config 里的 =y 会被 defconfig 剔除"
  exit 1
fi

echo "=========================================="
echo "diy-part1.sh 完成"
echo "=========================================="
