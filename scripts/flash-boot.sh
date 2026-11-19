#!/bin/bash
# ============================================================
# flash-boot.sh —— 在 GK6323V100C（ChaoGe Z71A）上刷入主线内核、
#                 设备树与内核模块
#
# 顺序不可颠倒：
#   1. 备份当前 p15 内核分区
#   2. 先解压模块到根目录（保证 /lib/modules 与新内核版本匹配）
#   3. 写 p15（boot，60MB）
#   4. 写 p10（dtbo，2MB，**本机型必须这一步**）
#   5. sync，提示重启
#
# 用法：
#   sudo bash scripts/flash-boot.sh -i boot.img -m modules.tar.gz -d gk6323v100c-chaoge-z71a.dtb
#   sudo bash scripts/flash-boot.sh ... -n   # 仅演练，不写任何数据
#
# 参数：
#   -i, --boot <file>      boot.img 路径（必填）
#   -m, --modules <file>   modules.tar.gz 路径（必填）
#   -d, --dtb <file>       设备树 dtb 路径（必填，写入 p10）
#   -p, --boot-part <dev>  内核分区，默认 /dev/mmcblk0p15
#   -t, --dtb-part <dev>   设备树分区，默认 /dev/mmcblk0p10
#   -b, --no-backup        跳过备份当前内核分区
#   -n, --dry-run          只打印将执行的动作
#   -y, --yes              不交互确认
#   -h, --help             显示帮助
# ============================================================
set -euo pipefail

BOOT_PART="/dev/mmcblk0p15"
DTB_PART="/dev/mmcblk0p10"
BOOT_IMG=""
MODULES=""
DTB=""
DO_BACKUP=1
DRY=0
ASSUME_YES=0
BAK="（本次未备份）"

usage() {
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -i|--boot)      BOOT_IMG="${2:-}"; shift 2 ;;
        -m|--modules)   MODULES="${2:-}"; shift 2 ;;
        -d|--dtb)       DTB="${2:-}"; shift 2 ;;
        -p|--boot-part) BOOT_PART="${2:-}"; shift 2 ;;
        -t|--dtb-part)  DTB_PART="${2:-}"; shift 2 ;;
        -b|--no-backup) DO_BACKUP=0; shift ;;
        -n|--dry-run)   DRY=1; shift ;;
        -y|--yes)       ASSUME_YES=1; shift ;;
        -h|--help)      usage 0 ;;
        *) echo "未知参数：$1" >&2; usage 1 ;;
    esac
done

die() { echo "错误：$*" >&2; exit 1; }
info() { echo "[INFO] $*"; }

run() {
    if [ "$DRY" -eq 1 ]; then
        echo "  [dry-run] $*"
    else
        "$@"
    fi
}

[ -n "$BOOT_IMG" ] || die "缺少 -i/--boot（boot.img 路径）"
[ -n "$MODULES" ]  || die "缺少 -m/--modules（modules.tar.gz 路径）"
[ -n "$DTB" ]      || die "缺少 -d/--dtb（设备树 dtb 路径）"
[ -f "$BOOT_IMG" ]  || die "找不到 boot.img：$BOOT_IMG"
[ -f "$MODULES" ]   || die "找不到 modules.tar.gz：$MODULES"
[ -f "$DTB" ]       || die "找不到 dtb：$DTB"

if [ "$DRY" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    die "需要 root 权限，请用 sudo 运行"
fi

[ -b "$BOOT_PART" ] || [ "$DRY" -eq 1 ] || die "内核分区不存在：$BOOT_PART"
[ -b "$DTB_PART" ]  || [ "$DRY" -eq 1 ] || die "设备树分区不存在：$DTB_PART"

# 大小检查：p15 为 60MB，boot.img 不得超过；p10 为 2MB，dtb 不得超过 16KB（U-Boot 读窗）
BOOT_MAX=57671680   # 55MB，留 5MB 余量
DTB_MAX=16384       # 16KB，U-Boot mmc read 0x03FFC000 0x19000 0x20 即 32 扇区 = 16KB
BOOT_SIZE=$(stat -c%s "$BOOT_IMG")
DTB_SIZE=$(stat -c%s "$DTB")
if [ "$DRY" -eq 0 ] && [ "$BOOT_SIZE" -gt "$BOOT_MAX" ]; then
    die "boot.img ($BOOT_SIZE 字节) 超过 $BOOT_MAX 字节，无法刷入 $BOOT_PART（60MB）"
fi
if [ "$DRY" -eq 0 ] && [ "$DTB_SIZE" -gt "$DTB_MAX" ]; then
    die "dtb ($DTB_SIZE 字节) 超过 $DTB_MAX 字节，U-Boot 只读 16KB，会被截断"
fi

echo "============================================================"
echo " boot.img    : $BOOT_IMG  ($BOOT_SIZE 字节)"
echo " modules     : $MODULES"
echo " dtb         : $DTB  ($DTB_SIZE 字节)"
echo " 内核分区    : $BOOT_PART"
echo " 设备树分区  : $DTB_PART"
echo " 备份当前内核: $([ "$DO_BACKUP" -eq 1 ] && echo 是 || echo 否)"
echo " 演练模式    : $([ "$DRY" -eq 1 ] && echo 是 || echo 否)"
echo "============================================================"

# 若产物同目录带有 sha256sums.txt，先校验
SUM_DIR="$(cd "$(dirname "$BOOT_IMG")" && pwd)"
if [ -f "$SUM_DIR/sha256sums.txt" ]; then
    info "检测到 sha256sums.txt，校验镜像完整性"
    if [ "$DRY" -eq 1 ]; then
        echo "  [dry-run] (cd $SUM_DIR && sha256sum -c sha256sums.txt --ignore-missing)"
    else
        ( cd "$SUM_DIR" && sha256sum -c sha256sums.txt --ignore-missing )
    fi
else
    info "未找到 sha256sums.txt，跳过校验"
fi

if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY" -eq 0 ]; then
    printf '将解压模块并覆写 %s 与 %s，确认继续？(y/N) ' "$BOOT_PART" "$DTB_PART"
    read -r ans || true
    case "${ans:-}" in
        y|Y) ;;
        *) info "已取消"; exit 0 ;;
    esac
fi

# 步骤 1：备份当前内核分区
if [ "$DO_BACKUP" -eq 1 ]; then
    BAK="/root/boot-backup-$(date +%Y%m%d-%H%M%S).img"
    info "步骤 1/5：备份当前内核分区到 $BAK"
    run dd if="$BOOT_PART" of="$BAK" bs=1M conv=fsync
else
    info "步骤 1/5：按要求跳过备份"
fi

# 步骤 2：先解压模块
info "步骤 2/5：解压模块到 /"
run tar -xzf "$MODULES" -C /
run sync
if [ "$DRY" -eq 0 ]; then
    run depmod -a "$(ls /lib/modules | sort -V | tail -1)" 2>/dev/null || true
fi

# 步骤 3：写入内核分区
info "步骤 3/5：写入 boot.img 到 $BOOT_PART"
run dd if="$BOOT_IMG" of="$BOOT_PART" bs=1M conv=fsync

# 步骤 4：写入设备树分区（**本机型必须**）
info "步骤 4/5：写入 dtb 到 $DTB_PART"
run dd if="$DTB" of="$DTB_PART" bs=1K conv=fsync
run sync

# 步骤 5：完成
info "步骤 5/5：完成"
echo
echo "刷写已结束。请用下面的命令正常重启："
echo "    sudo reboot"
echo
echo "回滚办法（启动异常时）："
echo "    sudo dd if=$BAK of=$BOOT_PART bs=1M conv=fsync && sync && sudo reboot"
echo
echo "重启后验证 USB 音频："
echo "    sudo modprobe snd-usb-audio && aplay -l"
