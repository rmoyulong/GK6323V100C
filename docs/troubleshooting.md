# 故障排查

所有这些坑都在真机调试过程中踩过一遍，已在本仓库流水线里固化对应防护措施。

---

## 1. TTL 全静（Starting kernel ... 之后无任何输出）

**最常见原因（按概率排序）**：

- **漏刷 p10（dtbo 分区）** —— arm64 内核不像 ARM32 那样识别追加在 Image 末尾的 dtb，
  它只认 x0 寄存器传进来的设备树地址。p10 没刷，或刷的是原厂旧 dtb，U-Boot 读到的
  不是我们编的设备树，内核在 DT 解析阶段就挂了，连 earlycon 都到不了。
  - 确认：刷写脚本输出里有没有"步骤 4/5：写入 dtb 到 /dev/mmcblk0p10"。
  - 修复：重新执行 `sudo dd if=gk6323v100c-chaoge-z71a.dtb of=/dev/mmcblk0p10 bs=1K conv=fsync && sync`。

- **dtb 被截断** —— U-Boot 从 p10 只读前 16KB，dtb 超过会被截掉尾巴，fdt 解析失败。
  - 确认：workflow 里"dtb 占用引导窗口"百分比应 <100%，目标 dtb ≤10KB。
  - 修复：精简 dts 节点，重新编译。

- **掉进 fastboot 精简模式** —— 启动时按太多次 Ctrl+C 会进 `fastboot#`，那里没有完整
  的 `bootm` 带参功能，只会打 `ATAGS` 然后全静。
  - 确认：提示符是 `hisilicon #` 而不是 `fastboot#`。
  - 修复：`reset` 重启，出现 `Autobooting in 1 seconds` 时只按一次 Ctrl+C。

- **设备树 compatible 与实际硬件不符** —— 比如 Cortex-A55 写成 Cortex-A53、
  GICv3 写成 GIC-400、CRU compatible 写错，都会在核心初始化阶段挂死。

## 2. 出 `Booting Linux` 后停住、串口不再吐字

- 通常是时钟/复位驱动缺失或 compatible 不匹配，外设 probe 永久返回 `-EPROBE_DEFER`。
- 本仓库通过 histb 补丁引入 hi3798mv200 的 CRU 与 reset 驱动，能覆盖 GK6323V100C。
- 若仍卡，在 TTL 里进 U-Boot，手动加载：
  ```
  mmc read 0 0x04000000 0x38000 0x7800
  mmc read 0 0x03FFC000 0x19000 0x20
  bootm 0x04000000 - 0x03FFC000
  ```
  看卡在哪个初始化阶段。

## 3. 能进系统但网口不通

- 确认 `/sys/class/net/eth0` 存在，`ip link set eth0 up` 能否拉起。
- PHY 地址：真机是 `phy@2`（不是 0 或 1），在 dts 里 `reg = <0x2>` 已写对。
- 看 `dmesg | grep -i femac` 有没有错误；phy-mode 是 `rmii` 不是 `rgmii`。

## 4. USB 声卡不识别

- 先确认 USB 主控工作正常：`lsusb` 能看到主控（OHCI/EHCI）。
- 模块是否已加载：`lsmod | grep snd_usb_audio`；没有就 `sudo modprobe snd-usb-audio`。
- 模块是否存在：`find /lib/modules -name 'snd-usb-audio.ko*'`；没有说明 modules.tar.gz
  没解压到 `/`，重新解压并 `sudo depmod -a`。
- 插上声卡后 `dmesg | tail -20` 看有没有 `new full-speed USB device`、`usb audio` 字样。
- 板载 es8316 报错（`asoc-simple-card`、`es8316 0-0011` 失败）是 I2C 通讯问题，
  与 USB 音频无关，可忽略。

## 5. `/dev/mmcblk0p18` 看不到、rootfs 挂载失败

- 必须开 `CONFIG_PARTITION_ADVANCED=y` 与 `CONFIG_CMDLINE_PARTITION=y`，否则内核不认
  bootargs 里的 `blkdevparts=mmcblk0:` 分区表，看不到除 p0/p1 以外的分区。
- 本仓库配置已强制启用这两项，workflow 的配置校验会检查。

## 6. 模块加载报 `Invalid module format`

- vermagic 不匹配：模块是给一个版本的内核编的，你在跑的是另一个版本。
- 内核与模块**必须来自同一次编译**，不要混用不同 build 号的产物。
- 确认：`uname -r` 与 `/lib/modules/` 下的目录名必须逐字一致。

## 7. FDT 诊断里块大小是 GB 级天文数字

- 这是 dtb 大端字节序问题（旧版脚本 bug），已在新仓库里修复：读取 FDT 头字段必须用
  `od --endian=big`，默认小端会把 `0x38` 读成 `0x38000000`（939 MB）。

## 8. 构建时补丁冲突

- 补丁库版本和源码版本不匹配：检查 workflow 里的 `PATCHES_BASE_SHA` 与补丁库
  `baseline` 里的 `BASE_SHA` 是否逐字一致。
- 本仓库把 `PATCHES_BASE_SHA` 钉死在已验证的 commit，升级版本时同步改两处。

---

## 救砖（TTL 全静进不了系统）

- 用 HiTool 或原厂 USB 烧写工具，只勾选 `boot.img` 与 `dtbo.img`（或 `boot.bin` +
  `dtbo.bin`）重新写入对应分区即可，不会破坏 rootfs。
- 或：进 U-Boot，用 `mmc write` 从 TFTP/USB 写回备份镜像。
- 备份镜像在 `/root/boot-backup-*.img`（刷写脚本自动备份）；如果连 rootfs 都进不去，
  就用 HiTool 刷回原厂安卓包，再重刷 Debian、再刷本仓库内核。
