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

# 本分支（for-zhangbin）在 configs/*.config 里已经开了的包，feeds 里自带，不需要在这里 clone：
#     luci-app-frpc      ← immortalwrt/luci，本体 frpc 来自 immortalwrt/packages 的 net/frp
#     luci-app-zerotier  ← immortalwrt/luci，本体 zerotier 来自 immortalwrt/packages 的 net/zerotier
#     luci-app-homeproxy ← immortalwrt/luci，依赖 sing-box / firewall4 / kmod-nft-tproxy /
#                          ucode-mod-digest，全部在现有 feeds 或主仓库里
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

echo "=========================================="
echo "diy-part1.sh 完成"
echo "=========================================="
