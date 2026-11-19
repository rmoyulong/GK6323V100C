# 构建与刷写

从零到把新内核刷进盒子，全部在 GitHub Actions 上完成编译，本机只负责下载产物与刷入。

---

## 一、前置条件

- 一个 GitHub 账号，把本仓库推上去（公开或私有均可）
- 仓库 **Settings → Actions → General → Workflow permissions** 选
  **Read and write permissions**，否则最后一步发布 Release 会失败
- 目标机已能进入 Debian 系统并有 root 权限（SSH 登录）
- TTL 串口线可选（用于排查启动问题，正常刷写不需要）

---

## 二、构建流程

`.github/workflows/gk6323.yml` 共 12 个步骤：

| # | 步骤 | 作用 |
| --- | --- | --- |
| 1 | 检出仓库代码 | 取本仓库的配置、补丁脚本、dts |
| 2 | 校验必要文件存在 | 确认 `apply_histb_patches.sh`、`kernel.config`、`dts/gk6323v100c-*.dts` 在位 |
| 3 | 安装 ARM64 交叉编译依赖 | `gcc-aarch64-linux-gnu`、`bc`、`bison`、`flex`、`u-boot-tools`、`device-tree-compiler` 等 |
| 4 | 拉取内核源码 | 按补丁库 `baseline` 的 commit 检出，并校验版本号一致 |
| 5 | 拉取补丁仓库 | 检查补丁库布局 |
| 6 | 应用 histb 补丁 | 调用根目录 `apply_histb_patches.sh`，`--fuzz=0`，冲突即回滚 |
| 7 | 部署内核配置并强制关键项 | 用 `kernel.config` 作 `.config`，再用 `scripts/config` 逐项确认关键符号 |
| 8 | 编译内核、模块 | `make Image` + `make modules`，带 ccache |
| 9 | 编译板级设备树 | `dtc` 编译 dts，反编译回读验证 compatible；检查体积 ≤16KB |
| 10 | 打包 uImage | `mkimage -A arm64 -C none -a 0x02000000` 打包成 boot.img |
| 11 | 整理产物 | 归集 boot.img / dtb / modules.tar.gz / Image / config-*，生成 `sha256sums.txt` |
| 12 | 发布到 GitHub Release | 标签 `gk6323v100c-7.4-rc2-b<N>` |

触发条件：推送到 `master` / `main` 且改动以下任一文件，或在 Actions 页面手动触发。

```
.github/workflows/gk6323.yml
kernel.config
apply_histb_patches.sh
dts/gk6323v100c-chaoge-z71a.dts
```

---

## 三、构建成功后的四处对照

正常构建会在日志里留下下面四组关键输出：

### 1. 补丁步骤

```
[INFO] ====== 补丁应用完成 ======
[INFO] 成功应用：XXX 个
```

数量应与补丁库当时的补丁数一致，不应出现 `[FAIL]` 与「跳过冲突」。

### 2. 配置校验

`=== 关键配置最终取值 ===` 之后应有 27 行 `OK CONFIG_...`，覆盖平台、中断、串口、
eMMC、ext4、分区、网口、USB、模块、USB 音频全链路。

### 3. 设备树校验

- 输出 `OK arm,cortex-a55` / `OK arm,gic-v3` / `OK arm,pl011` / `OK snps,dw-mshc`
- `dtb 占用引导窗口 < 100%`（目标 ≤60%，留足余量）
- 反编译 compatible 包含 `goke,gk6323v100c`

### 4. uImage 打包

`mkimage -l` 输出里应有：

```
Architecture: AArch64
Load Address: 02000000
Entry Point:  02000000
Compression:  uncompressed
```

---

## 四、产物说明

| 文件 | 用途 | 刷入位置 |
| --- | --- | --- |
| `boot.img` | uImage 内核镜像 | `/dev/mmcblk0p15`（boot，60MB） |
| `gk6323v100c-chaoge-z71a.dtb` | 设备树 | `/dev/mmcblk0p10`（dtbo，2MB） |
| `modules.tar.gz` | 内核模块（含 snd-usb-audio） | 解压到 `/` |
| `Image` | 未打包的裸内核，仅供核对 | — |
| `config-<release>` | 本次实际使用的内核配置 | — |
| `sha256sums.txt` | 上述产物的 SHA256 校验值 | — |

---

## 五、刷写

### 方式一：用脚本（推荐）

把 `boot.img`、`gk6323v100c-chaoge-z71a.dtb`、`modules.tar.gz` 传到盒子的 `/tmp`，然后：

```bash
sudo bash scripts/flash-boot.sh \
     -i /tmp/boot.img \
     -m /tmp/modules.tar.gz \
     -d /tmp/gk6323v100c-chaoge-z71a.dtb
sudo reboot
```

脚本会：
1. 校验 sha256（若有）；
2. 备份当前 `/dev/mmcblk0p15` 到 `/root/boot-backup-<时间戳>.img`；
3. 先解压模块到 `/`；
4. 再写 `p15`（boot）；
5. 最后写 `p10`（dtbo）——**本机型必须这一步**；
6. sync 后提示重启。

只想先看一遍动作，加 `-n` 走演练。

### 方式二：手工命令

顺序不可颠倒：

```bash
# 1. 备份原 boot 分区
sudo dd if=/dev/mmcblk0p15 of=/root/boot.bak bs=1M conv=fsync

# 2. 先装模块（内核与模块必须同版本）
cd / && sudo tar -xzf /tmp/modules.tar.gz && sync
sudo depmod -a "$(ls /lib/modules | sort -V | tail -1)"

# 3. 刷内核
sudo dd if=/tmp/boot.img of=/dev/mmcblk0p15 bs=1M conv=fsync && sync

# 4. 刷设备树（必须）
sudo dd if=/tmp/gk6323v100c-chaoge-z71a.dtb of=/dev/mmcblk0p10 bs=1K conv=fsync && sync

# 5. 重启
sudo reboot
```

### 回滚

启动异常（TTL 全静、指示灯异常闪烁）时，用备份镜像写回：

```bash
sudo dd if=/root/boot.bak of=/dev/mmcblk0p15 bs=1M conv=fsync && sync && sudo reboot
```

刷写前建议先在电脑上比对一次 `sha256sums.txt`，确认下载的镜像没有损坏。

---

## 六、验证 USB 音频

系统启动后，插上 USB 声卡：

```bash
# 加载 USB 音频模块（已安装但未自动加载）
sudo modprobe snd-usb-audio

# 查看声卡列表
aplay -l
cat /proc/asound/cards

# 一键自检
sudo bash scripts/verify-device.sh
```

如需开机自动加载，把 `snd-usb-audio` 加到 `/etc/modules`：

```bash
echo 'snd-usb-audio' | sudo tee -a /etc/modules
```

---

## 七、升级内核版本或更换补丁库

- **升版本**：把 workflow 里的 `PATCHES_BASE_SHA` 与 `PATCHES_KERNEL_VERSION`
  跟着补丁库 `baseline` 一起改，其余步骤不动。版本校验会做规范化比较，
  `7.4-rc2` 与内核自报的 `7.4.0-rc2` 视为同一版本。
- **换补丁库**：改 `PATCHES_REPO` 指向自己的 fork 或镜像。
- **用本地补丁**：`apply_histb_patches.sh` 支持 `PATCHES_DIR` 环境变量，
  有 `series` 就按 `series` 顺序，没有就按文件名序号应用根目录全部 `*.patch`。
