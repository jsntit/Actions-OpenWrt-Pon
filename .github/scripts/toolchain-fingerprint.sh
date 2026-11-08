#!/usr/bin/env bash
#
# 计算工具链指纹
#
# ⚠ 这个脚本被两个 workflow 共用：
#     .github/workflows/toolchain-builder.yml   （独立编工具链）
#     .github/workflows/openwrt-builder.yml     （编固件）
#   两边必须用同一份算法，否则 cache key 对不上，工具链永远命中不了。
#   —— 所以千万不要把这段逻辑复制进 yml 里，只改这里。
#
# 用法：toolchain-fingerprint.sh <openwrt 源码目录>
#
# 输出：
#   stdout          key=value（便于本地调试）
#   $GITHUB_OUTPUT  若已设置，额外写入 fingerprint=（供 workflow 取用）
#

set -euo pipefail

TOPDIR="${1:-.}"

if [ ! -d "$TOPDIR" ]; then
	echo "::error::目录不存在: $TOPDIR" >&2
	exit 1
fi
cd "$TOPDIR"

if [ ! -f .config ]; then
	echo "::error::$TOPDIR/.config 不存在，无法计算工具链指纹（需要先 make defconfig）" >&2
	exit 1
fi

# ---------------------------------------------------------------
# 1) 决定性的工具链参数
#
#    这四项决定编出来的是哪套工具链。取不到就立刻失败 ——
#    绝不能让指纹静默退化成残缺串，否则会命中错误的缓存。
# ---------------------------------------------------------------
get_cfg() {
	grep -E "^CONFIG_${1}=" .config | head -1 | cut -d'"' -f2
}

GCCV=$(get_cfg GCC_VERSION)
BINV=$(get_cfg BINUTILS_VERSION)
LIBC=$(get_cfg LIBC)
SUFFIX=$(get_cfg TARGET_SUFFIX)

for pair in "GCC_VERSION=$GCCV" "BINUTILS_VERSION=$BINV" "LIBC=$LIBC"; do
	if [ -z "${pair#*=}" ]; then
		echo "::error::${pair%%=*} 为空（.config 可能没生成好，或用了不完整的配置）" >&2
		exit 1
	fi
done

# toolchain/build_version 是上游的「工具链构建版本号」，改动它等于宣布
# 所有已编好的工具链作废。只取首行并去空白，防止文件被追加内容后把换行灌进指纹。
BUILDER=$(head -1 toolchain/build_version 2>/dev/null | tr -d '[:space:]')
BUILDER=${BUILDER:-0}

# ---------------------------------------------------------------
# 2) toolchain/ 目录内容指纹
#
#    沿上游 toolchain/Makefile 里 toolchain_hash 的算法：
#    逐文件取内容 md5 → 排序 → 再 md5。
#    这样上游改了任何一个 patch 或 Makefile，指纹都会变。
# ---------------------------------------------------------------
if [ -d toolchain ]; then
	TREE_HASH=$(find toolchain -type f ! -path '*/.*' \
		! -name '*.orig' ! -name '*.rej' ! -name '*~' \
		-exec md5sum {} + | awk '{print $1}' | LC_ALL=C sort | md5sum | cut -c1-16)
else
	echo "::error::$TOPDIR/toolchain 目录不存在" >&2
	exit 1
fi

if [ -z "$TREE_HASH" ]; then
	echo "::error::toolchain/ 目录哈希计算失败" >&2
	exit 1
fi

# ---------------------------------------------------------------
# 3) 拼指纹
#
#    刻意不含：机型（TARGET_DEVICE）、包列表、主机名、时区
#    理由：这些换掉不影响工具链，换机型应该继续复用同一份缓存。
#    —— 实测 an7581 / an7583 两个官方 config defconfig 后的
#       GCC/BINUTILS/LIBC/SUFFIX 完全一致。
# ---------------------------------------------------------------
FPRINT="${GCCV}-${BINV}-${LIBC}-${BUILDER}-${TREE_HASH}"

ARCH=$(get_cfg ARCH)
CPU=$(get_cfg CPU_TYPE)

echo "gcc=${GCCV} binutils=${BINV} libc=${LIBC} build_version=${BUILDER}"
echo "toolchain 目录哈希=${TREE_HASH}"
echo "工具链目录名=toolchain-${ARCH}_${CPU}_gcc-${GCCV}_${LIBC}"
echo "指纹=${FPRINT}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "fingerprint=${FPRINT}" >>"$GITHUB_OUTPUT"
fi
