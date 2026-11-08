# Actions-OpenWrt-Pon

用 GitHub Actions 编译 **PonWrt**（`pbs05/ponwrt`）的 Airoha AN758x 平台固件。

源码、feeds、机型定义全部来自上游 `pbs05/ponwrt`，本仓库只负责「选机型 → 拉插件 → 编译 → 发 Release」。

## 快速开始

1. 打开仓库的 **Actions** 页面，左侧选 **PonWrt Builder**
2. 点 **Run workflow**，填/选这几项：
   - **source**：`pbs05/ponwrt`（上游）或 `fork`（你自己的 ponwrt 镜像）
   - **branch**：源码分支，默认 `master`
   - **soc**：`an7581` 或 `an7583`
   - **profile**：机型名，见下方机型表；填 `all` = 该 SoC 全部机型
   - **config_file**：`auto` 表示按机型自动挑配置（一般不用改）
3. 跑完后在 **Releases** 里下载固件，或在本轮 Actions 页面底部下载 Artifacts

## 机型表

| SoC | profile |
|---|---|
| `an7581` | `fiberhome_hg5585f-ct` `fiberhome_hg5585f-cu` `fiberhome_hg5382a`<br>`fiberhome_hg5585f-ct-usb-sfp` `fiberhome_hg5585f-cu-usb-sfp`<br>`h3c_hm2004-du` `gemtek_xg2010g` `gemtek_w1700k-ubi`<br>`nokia_xg-040g-md-ubi` `nokia_xg-040g-md-ubi-usb-sfp` `nokia_xg-040g-tf-ubi`<br>`nokia_valyrian` `unionman_ung00a` `znxt_zn504xg-d` `znxt_zn515xg-d`<br>`quantum_q1000k-ubi` `airoha_an7581-evb-multievb` |
| `an7583` | `nokia_xg-040g-mf` `nokia_xg-040g-mf-ubi`<br>`airoha_an7583-evb-multievb` |

soc 与 profile 必须配套，填错会在「环境自检」这一步直接报错退出，不会跑到一半才失败。

## 目录说明

| 路径 | 作用 |
|---|---|
| `.github/workflows/openwrt-builder.yml` | 主构建流程（21 步：拉源码 → feeds → 配置 → 编译 → 发布） |
| `.github/workflows/update-checker.yml` | 上游有新提交时自动触发构建（默认手动，取消注释 `schedule` 即开启） |
| `configs/an7581.config` / `an7583.config` | 基础配置，取自 ponwrt 官方 `configs/`，编译时会收敛为单机型 |
| `configs/release.config` | 官方发布版的额外包（BBR / cake / tproxy / wireguard 等），自动叠加 |
| `diy-part1.sh` | feeds update 之前跑：按开关拉取额外插件并修正 po 命名 |
| `diy-part2.sh` | 配置加载之后跑：改时区、追加固件版本后缀（**不改 LAN 地址**） |
| `.config` | 兜底配置（`configs/` 里找不到对应文件时才会用到） |

## 客制化

### 关于默认 LAN 地址

**本仓库不改默认 LAN 地址，保持 ponwrt 上游的 `192.168.1.1`。**

`diy-part2.sh` 只改时区和固件版本后缀，不碰网络配置。上游配置里
`CONFIG_TARGET_PREINIT_IP="192.168.1.1"`，failsafe 预启动网络也是同一网段。

确实要换成别的网段（比如避开光猫的 `192.168.1.x`），有两条路：

- **简单**：在 `diy-part2.sh` 里加一句
  `sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate`
- **完整**：还需要同步 failsafe 的预启动网络，否则进了 failsafe 得把电脑换回
  `192.168.1.x` 才能连上 —— 要改 `base-files/Makefile` 的 `pi_ip` /
  `pi_broadcast` 和 `image-config.in` 里 `TARGET_PREINIT_IP` 的 Kconfig default
  （后者不改的话，光写 `.config` 会被 defconfig 按 default 重算丢掉）。

### 加插件

`diy-part1.sh` 里的开关只管「源码有没有拉到 `package/custom`」，
还要在对应的 `configs/*.config` 里把包改成 `=y` 才会编进去。两处必须一起改：

- 只开开关不改 config → 白拉
- 只改 config 不开开关 → `defconfig` 把那个 `=y` **静默剔除**，不报错

当前默认开启的只有 `luci-app-airoha-npu`（Airoha SoC 状态页）。
homeproxy / passwall2 / openclash / mosdns / lucky 的开关都在文件里，默认 `false`。

## 缓存

`dl` 目录走 `actions/cache`，命中后能省 20~40 分钟。想强制全量重新下载，
把 **ignore_cache** 选成 `true`。

## 致谢

- [pbs05/ponwrt](https://github.com/pbs05/ponwrt) —— 源码与机型定义
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) —— workflow 模板
- [luanmuc/luci-app-airoha-npu](https://github.com/luanmuc/luci-app-airoha-npu) —— Airoha 状态页

## License

[MIT](./LICENSE)
