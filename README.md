# Actions-OpenWrt-Pon

用 GitHub Actions 编译 **PonWrt**（`pbs05/ponwrt`）的 Airoha AN758x 平台固件。

源码、feeds、机型定义全部来自上游 `pbs05/ponwrt`，本仓库只负责「选机型 → 拉插件 → 编译 → 发 Release」。

一共两个 workflow，各管一件事：

| Workflow | 干什么 | 什么时候用 |
|---|---|---|
| **Toolchain Builder** | 只编工具链（约 20~40 分钟），结果存进缓存 | 上游升了 GCC / 改了 `toolchain/`，或者想提前把工具链准备好 |
| **PonWrt Builder** | 编固件并发布 Release | 平时编固件都走这个 |

工具链编一次可以一直复用，固件构建会自动跳过那一段。两者通过**工具链指纹**对上同一份缓存。

## 快速开始

> **先选分支**：`main` 是干净基线（不带额外插件）；日常编固件请切到对应分支 ——
> `for-zhangbin`（frpc + zerotier + homeproxy）或 `for-maym`（homeproxy + tailscale）。
> 详见下方「[分支与各分支的插件](#分支与各分支的插件)」。
>
> ⚠ 两个插件分支上跑 Toolchain Builder 编出的工具链缓存**只有该分支能用**。
> 想让两个分支共用一份工具链，请先在 `main` 上跑一次。

### 平时编固件

1. 打开仓库的 **Actions** 页面，左侧选 **PonWrt Builder**
2. 点 **Run workflow**，填/选这几项：
   - **source**：`pbs05/ponwrt`（上游）或 `fork`（你自己的 ponwrt 镜像）
   - **branch**：源码分支，默认 `master`
   - **soc**：`an7581` 或 `an7583`
   - **profile**：**下拉选机型**，全部 20 个机型都在里面；选 `all` = 该 SoC 全部机型
   - **profile_custom**：一般留空。需要临时编一个下拉里没有的机型时才填，
     **填了会覆盖上面的选择**
   - **config_file**：`auto` 表示按机型自动挑配置（一般不用改）
   - **reuse_toolchain**：`true`（默认）= 工具链没变就直接用缓存；`false` = 强制重编工具链
3. 跑完后在 **Releases** 里下载固件，或在本轮 Actions 页面底部下载 Artifacts

### 想单独先把工具链编好

1. Actions 页面左侧选 **Toolchain Builder**
2. 点 **Run workflow**：
   - **soc**：选哪个都行（工具链与机型无关，`an7581`/`an7583` 结果完全一样）
   - **force_rebuild**：`false`（默认）= 已经有缓存就直接跳过；`true` = 不管有没有都重编
3. 编完缓存就存好了，之后跑 **PonWrt Builder** 会自动命中

> ⚠ 请**在默认分支（main）上跑** Toolchain Builder。GitHub 的缓存按分支隔离：
> 在 main 上存的缓存所有分支都能用，在别的分支上存就只有那个分支能用（等于白编）。
> workflow 检测到你不是在默认分支跑时会打一条 warning。

> GitHub 的下拉框不支持「选 an7583 时只显示 3 个机型」这种联动，
> 所以下拉里两个 SoC 的机型是混在一起列的。选错组合会在「环境自检」
> 这一步被拦下并列出该 SoC 的可选值，不会跑到一半才失败。

## 机型表

| SoC | 机型（下拉里都选得到） |
|---|---|
| `an7581` | `fiberhome_hg5585f-ct` `fiberhome_hg5585f-cu`<br>`fiberhome_hg5585f-ct-usb-sfp` `fiberhome_hg5585f-cu-usb-sfp`<br>`fiberhome_hg5382a` `h3c_hm2004-du`<br>`nokia_xg-040g-md-ubi` `nokia_xg-040g-md-ubi-usb-sfp` `nokia_xg-040g-tf-ubi`<br>`nokia_valyrian` `gemtek_xg2010g` `gemtek_w1700k-ubi`<br>`unionman_ung00a` `znxt_zn504xg-d` `znxt_zn515xg-d`<br>`quantum_q1000k-ubi` `airoha_an7581-evb-multievb` |
| `an7583` | `nokia_xg-040g-mf` `nokia_xg-040g-mf-ubi`<br>`airoha_an7583-evb-multievb` |

soc 与 profile 必须配套，填错会在「环境自检」这一步直接报错退出，不会跑到一半才失败。

## 目录说明

| 路径 | 作用 |
|---|---|
| `.github/workflows/openwrt-builder.yml` | **固件构建**（23 步：拉源码 → feeds → 配置 → 工具链缓存 → 编译 → 发布） |
| `.github/workflows/toolchain-builder.yml` | **工具链构建**（只编 tools/ + 工具链，存缓存，不编固件） |
| `.github/workflows/update-checker.yml` | 上游有新提交时自动触发构建（默认手动，取消注释 `schedule` 即开启） |
| `.github/scripts/toolchain-fingerprint.sh` | **工具链指纹算法**，两个 workflow 共用（改这里，不要复制到 yml 里） |
| `.github/actions/build-env/action.yml` | 编译环境准备（apt 依赖 + 时区 + `/workdir`），两个 workflow 共用 |
| `configs/an7581.config` / `an7583.config` | 基础配置，取自 ponwrt 官方 `configs/`，编译时会收敛为单机型 |
| `configs/release.config` | 官方发布版的额外包（BBR / cake / tproxy / wireguard 等），自动叠加 |
| `diy-part1.sh` | feeds update 之前跑：按开关拉取额外插件并修正 po 命名 |
| `diy-part2.sh` | 配置加载之后跑：改时区 + 默认 LAN / failsafe 地址，其余保持上游（主机名 / 主题不动） |
| `.config` | 兜底配置（`configs/` 里找不到对应文件时才会用到） |

## 客制化

### 修改原则：只动必要的

`diy-part2.sh` 只改下面三项，其余一律保持上游：

| 项目 | 上游默认 | 本仓库 |
|---|---|---|
| 时区 | UTC | **Asia/Shanghai** |
| 默认 LAN | `192.168.1.1` | **`10.0.0.1/24`** |
| failsafe 预启动网络 | `192.168.1.1` | **`10.0.0.1/24`** |
| 主机名 | `OpenWrt` | 不动 |
| 主题 | argon（ImmortalWrt luci feeds 自带） | 不动 |
| 固件版本后缀 | 无 | 不加 |

### 关于默认 LAN 地址

**本分支把默认网段改成了 `10.0.0.1/24`**（避开光猫/主路由常用的 `192.168.1.x`）。
这一步要改**两个地方**，少改一个就会出问题：

| 作用域 | 由谁决定 | 改法 |
|---|---|---|
| 正常 LAN（首启生成的 `/etc/config/network`） | `package/base-files/files/bin/config_generate` 的 `lan) ipad=` 行 | `diy-part2.sh` 第 2 段 sed 这一行 |
| failsafe 恢复模式（`/lib/preinit/00_preinit.conf` 的 `pi_ip`） | `.config` 的 `CONFIG_TARGET_PREINIT_IP` / `_BROADCAST` | 三份 config 直接改值，`diy-part2.sh` 第 3 段再兜一次 |

`pi_ip` **不是**静态文件：`package/base-files/Makefile:93` 在编译期现拼

```make
echo 'pi_ip=$(if $(CONFIG_TARGET_PREINIT_IP),$(CONFIG_TARGET_PREINIT_IP),"192.168.1.1")'
```

所以改 `.config` 就够了，**不需要**动 `base-files/Makefile`。

判定固件到底改成功没有，别只看脚本输出，直接解包看实物：

```bash
# 1) 正常 LAN
unsquashfs -c ... 后读 bin/config_generate，lan) 那行应是 10.0.0.1
# 2) failsafe
cat lib/preinit/00_preinit.conf    # pi_ip="10.0.0.1" / pi_broadcast="10.0.0.255"
```

注意 sysupgrade 默认保留旧配置，已刷过的机器升级后 LAN 不会变，要重新配或刷机时不保留配置。

### 加插件

先分清两种情况，**大多数插件属于第一种**：

**A. feeds 里自带的包 → 只改 `configs/*.config`**

ponwrt 的 feeds 已经有 `immortalwrt/luci`（所有 `luci-app-*`）和 `immortalwrt/packages`
（各种后端）。这类包只需要在 config 里把 `is not set` 改成 `=y`。

```bash
sed -i 's|^# CONFIG_PACKAGE_luci-app-xxx is not set|CONFIG_PACKAGE_luci-app-xxx=y|' configs/*.config
```

⚠ 顺手把依赖包也确认一遍。`luci-app-xxx` 的 `LUCI_DEPENDS` 里列的每个包都必须是 `=y`，
否则 `defconfig` 会**静默剔除**整个包（不报错，固件里就是没这个菜单）。

**B. feeds 里没有的包 → 还要在 `diy-part1.sh` 里 clone 源码**

`diy-part1.sh` 里的开关只管「源码有没有拉到 `package/custom`」。两处必须一起改：

- 只开开关不改 config → 白拉
- 只改 config 不开开关 → `defconfig` 把那个 `=y` **静默剔除**，不报错

### 分支与各分支的插件

`main` 保持**纯净**（紧跟上游与本仓库的工具链/流程改进，不额外加插件）。
两个使用分支都从 `main` 分出，各自带一套插件：

| 分支 | 插件组合 | 说明 |
|---|---|---|
| `main` | 无（只有 `luci-app-airoha-npu`） | 基线 / 干净版 |
| `for-zhangbin` | `luci-app-frpc` + `luci-app-zerotier` + `luci-app-homeproxy` | 内网穿透 + 组网 + 代理 |
| `for-maym` | `luci-app-homeproxy` + `luci-app-tailscale-community` | 代理 + Tailscale 组网 |

各插件的依赖与来源（`configs/an7581.config`、`configs/an7583.config`、`.config` 三份同步改）：

| 插件 | config 符号 | 本体依赖 | 来源 |
|---|---|---|---|
| `luci-app-frpc` | `luci-app-frpc` | `frpc` | luci feeds；`frpc` 来自 packages 的 `net/frp` |
| `luci-app-zerotier` | `luci-app-zerotier` | `zerotier` | luci feeds；`zerotier` 来自 packages 的 `net/zerotier` |
| `luci-app-homeproxy` | `luci-app-homeproxy` | `sing-box`、`firewall4`、`kmod-nft-tproxy`、`ucode-mod-digest` | luci feeds；`sing-box` 来自 packages 的 `net/sing-box`；`ucode-mod-digest` 来自主仓库 `package/utils/ucode` |
| `luci-app-tailscale-community` | `luci-app-tailscale-community` | `tailscale`、`ip-full` | luci feeds（作者 Tokisaki-Galaxy）；`tailscale` 来自 packages 的 `net/tailscale`，需 `golang/host` |

> ⚠ 包名就叫 **`luci-app-tailscale-community`**，immortalwrt/luci 里没有 `luci-app-tailscale`。
> config 里必须写全名，写成 `luci-app-tailscale` 会被 `defconfig` 静默剔除。

**这些包全部不需要 `diy-part1.sh` 去 clone 任何源码** —— 包和依赖都在 ponwrt 现有的
feeds 里（`frpc` 由 `net/frp` 这一个 Makefile 同时产出 `frpc` + `frps`）。

`luci-app-airoha-npu`（Airoha SoC 状态页）不在 feeds 里，靠 `diy-part1.sh` 单独 clone。
passwall2 / openclash / mosdns / lucky 的开关都在文件里，默认 `false`。

> 耗时代价：homeproxy 多 15~25 分钟（sing-box 是 Go），tailscale 也多 10~20 分钟
> （tailscaled 同样是 Go，首次要编 `golang/host`）。两者合计固件大约 +50MB。
> 只想保留其中一个时，把另一个插件行和它的本体行一起改回 `is not set`。

## 工具链复用（省 20~40 分钟）

OpenWrt 编译里最贵的一段是**工具链**（binutils → gcc → libc → 内核头文件）加上 `tools/`
那几十个 host 程序，总共 20~40 分钟。但这段产物**只取决于工具链本身**，跟选哪个机型无关：
`an7581` 和 `an7583` 用的都是同一套 `aarch64_cortex-a53 / musl / gcc-14.4.0`（已实测两个
config 的 GCC / binutils / libc / suffix 完全一致）。

所以这段被单独抽成 **Toolchain Builder** 一个 workflow：只编工具链、只存缓存、不编固件。
编一次，之后所有固件构建都跳过这一段。靠一个**工具链指纹**判断能不能复用：

```
指纹 = gcc版本 - binutils版本 - libc - toolchain/build_version - toolchain/目录内容哈希
例：  14.4.0-2.46.1-musl-1-89ea73fa8d9fca70
```

| 情况 | 指纹 | 行为 |
|---|---|---|
| 换机型（an7581 ↔ an7583、不同 profile） | **不变** | 直接吃缓存，跳过工具链 |
| 上游改了 `toolchain/` 里任何文件 | 变化 | 缓存落空，重编工具链后自动存新的 |
| 上游升级 GCC / binutils / libc | 变化 | 同上 |
| 选 `reuse_toolchain: false` | 不查缓存 | 强制从头编工具链 |

缓存内容是三块，缺一不可：

| 路径 | 为什么必须有 |
|---|---|
| `staging_dir/host` | `tools/` 的完成戳 `.tools_compile` 在这里 |
| `staging_dir/toolchain-*` | 工具链本体，**以及 `.gcc_final_installed` 完成戳** |
| `build_dir/toolchain-*` | 工具链中间产物 |

> 关键点：完成戳跟着缓存一起回来，`make` 就认为工具链已经编好了，才会真的跳过。
> 只存 `staging_dir/host` 而不存 `toolchain-*`，戳会丢，工具链照样重编。

### 关于缓存容量

GitHub 每个仓库的缓存总量默认上限 **10 GB**，超了按最久未访问淘汰。
工具链缓存占 **6~9 GB**，所以**本仓库不再单独缓存 `dl/`**（原来那 3~5 GB 会和工具链
抢空间，互相驱逐，结果就是「缓存了反而命中不了」）。

代价是每次都要重新 `make download` 拉源码包。但工具链命中省下的时间（20~40 分钟）
远大于 dl 下载的时间，而且工具链复用后 dl 里那部分工具链源码本来也用不上。

> 如果确实需要 dl 缓存，去 **Settings → Actions → General → Cache size eviction limit**
> 把上限调大（需 Pro/Team 或有付款方式），再把 dl 缓存那几步加回来。

### 强制重编工具链

三种方式，按场景选：

| 方式 | 做法 | 适合 |
|---|---|---|
| 只重编工具链 | 跑 **Toolchain Builder**，`force_rebuild` 选 `true` | 想先单独验证工具链能不能编过 |
| 编固件时跳过缓存 | **PonWrt Builder** 里 `reuse_toolchain` 选 `false` | 一次性，不想管缓存 |
| 彻底清掉 | Actions 页面 **Caches** 里删掉 key 以 `toolchain-` 开头的条目 | 怀疑缓存坏了 |

### 两个 workflow 怎么对上同一份缓存

靠两点，缺一就会「编了但命中不了」：

1. **key 相同** —— 两边都调 `.github/scripts/toolchain-fingerprint.sh` 算指纹
2. **path 相同** —— 两边都存/取 `/workdir/openwrt/{staging_dir/host,staging_dir/toolchain-*,build_dir/toolchain-*}`

所以**不要**把指纹算法复制进 yml 里。要改就改那个脚本，两个 workflow 自动跟着变。

GitHub 的 cache 是**仓库级共享**的，不同 workflow 之间能直接读到，但按分支隔离：
在默认分支（main）上存的缓存，所有分支的 workflow 都能 restore；在别的分支上存的，
只有那个分支能用。这就是为什么 Toolchain Builder 要在 main 上跑。

## 致谢

- [pbs05/ponwrt](https://github.com/pbs05/ponwrt) —— 源码与机型定义
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) —— workflow 模板
- [luanmuc/luci-app-airoha-npu](https://github.com/luanmuc/luci-app-airoha-npu) —— Airoha 状态页

## License

[MIT](./LICENSE)
