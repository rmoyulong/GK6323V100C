# GK6323V100C 主线内核：构建 + 刷写 + USB 音频

面向国科微 :ml-search[GK6323V100C]{text="GK6323V100C"}（整机型号 ChaoGe Z71A / Hi3798MV200H 系列）
的主线内核仓库：在 GitHub Actions 上拉取 Linux 主线源码、应用 histb 补丁、编译出可直接
刷入的 `boot.img`（uImage）、设备树 dtb 与内核模块（含 USB 音频），并在真机上完成一轮验证。

本仓库完全独立于旧的 7.4.x merge_config 工程，**结构与构建思路直接参照 hataketsu/
hi3798mv300-mainline 移植经验**，所有踩过的坑（设备树字节序、ARM64 appended dtb、
Cortex-A55 勘误、p10 必须刷等）都已固化在流水线里，不会再复现。

---

## 一、仓库结构

```
.
├── .github/workflows/gk6323.yml   # 构建流水线：拉源码 → 打补丁 → 编译 → 打包 → 发布
├── kernel.config                  # 内核配置（ARM64 Cortex-A55，模块+USB音频）
├── apply_histb_patches.sh         # 补丁应用脚本（有 series 按 series，否则按文件名序号）
├── dts/
│   └── gk6323v100c-chaoge-z71a.dts  # 板级设备树（引导最小集，<10KB）
├── scripts/
│   ├── flash-boot.sh              # 目标机上刷写 boot.img + dtb + 安装模块
│   └── verify-device.sh           # 目标机上一条命令自检
├── docs/
│   ├── build-and-flash.md         # 从构建到刷写的完整步骤
│   ├── partition-layout.md        # 真机实测分区表
│   └── troubleshooting.md         # 踩过的坑与排查办法
└── .gitignore
```

三处触发路径固定为 `.github/workflows/gk6323.yml`、`kernel.config`、
`apply_histb_patches.sh`、`dts/gk6323v100c-chaoge-z71a.dts`，改动其中任一文件即自动
触发构建，也可以在 Actions 页面手动触发。

---

## 二、快速开始

### 1. 构建

把这个目录初始化成 Git 仓库，推到你自己的 GitHub 上：

```bash
git init -b main
git add -A
git commit -m "GK6323V100C mainline kernel (USB audio enabled)"
git remote add origin git@github.com:<你的账号>/<仓库名>.git
git push -u origin main
```

然后在 Actions 里打开写权限，触发构建：

- **Settings → Actions → General → Workflow permissions** 选 **Read and write permissions**
  （发布 Release 需要写权限，不开会在最后一步失败）
- 触发方式：Actions → **GK6323V100C 主线内核自动构建** → **Run workflow**

构建成功后会产出 `boot.img`、`gk6323v100c-chaoge-z71a.dtb`、`modules.tar.gz`、`Image`、
`config-*`、`sha256sums.txt`，并自动创建一个 Release，标签形如
`gk6323v100c-7.4-rc2-b<N>`。

### 2. 刷入设备

```bash
# 把 Release 里的 boot.img、gk6323v100c-chaoge-z71a.dtb 与 modules.tar.gz
# 传到盒子的 /tmp
sudo bash scripts/flash-boot.sh \
     -i /tmp/boot.img \
     -m /tmp/modules.tar.gz \
     -d /tmp/gk6323v100c-chaoge-z71a.dtb
sudo reboot
```

脚本顺序：**先备份 p15 → 解压模块 → 写 p15 → 写 p10 → sync**。只想先看一遍动作加 `-n`。

> **关键提醒**：`p10`（dtbo 分区）**必须单独写**——arm64 内核不像 ARM32 那样识别追加在
> Image 末尾的 dtb，内核拿到设备树全靠 U-Boot 把 p10 的内容读进内存、再通过 x0 传给内核。
> 只刷 p15、漏刷 p10 就会在 earlycon 之前全静。

### 3. 验证

```bash
sudo bash scripts/verify-device.sh
```

七组检查（内核 / 串口 / eMMC / 网口 / USB / 模块 / USB 音频），末尾给出
`PASS / FAIL / SKIP` 汇总，全通过时退出码为 0。

---

## 三、关键约定

| 项目 | 取值 | 说明 |
| --- | --- | --- |
| 架构 | ARM64 / aarch64 | Cortex-A55（MIDR 0x412FD050）+ GICv3 |
| 内核基线 | `7.4-rc2` / commit `fd9230005e85` | 与补丁库 `baseline` 逐字一致 |
| 补丁库 | `histb-mainline_patches` | 根目录平铺 quilt 库，`--fuzz=0`，冲突即回滚 |
| eMMC 驱动 | `CONFIG_MMC_DW_HI3798CV200` | dts emmc 节点 compatible 追加 `"snps,dw-mshc"` |
| 控制台 | `PL011 @ 0xf8b00000` / 115200 | 与真机 U-Boot 串口一致 |
| uImage | 加载/入口 `0x02000000`，`-C none` | ATF 跳转地址，与原机一致 |
| 内核分区 | `/dev/mmcblk0p15`（boot） | 60MB，刷入 boot.img |
| 设备树分区 | `/dev/mmcblk0p10`（dtbo） | 2MB，U-Boot 只读前 16KB |
| 启动参数 | `CONFIG_CMDLINE=""` | `root=`/`blkdevparts=` 由 bootargs 分区下发 |
| USB 音频 | `CONFIG_SND_USB_AUDIO=m` | 本仓库核心目标，模块化编译 |

升级内核版本时，只需把 workflow 里的 `PATCHES_BASE_SHA` 与 `PATCHES_KERNEL_VERSION`
跟着补丁库 `baseline` 一起改，其余步骤照跑。换成自己的补丁库 fork，改 `PATCHES_REPO` 即可。

---

## 四、文档索引

- [构建与刷写](docs/build-and-flash.md)
- [分区表](docs/partition-layout.md)
- [故障排查](docs/troubleshooting.md)
