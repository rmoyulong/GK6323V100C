#!/bin/bash
# ============================================================
# verify-device.sh —— GK6323V100C 主线内核实机自检
#
# 用法：sudo bash scripts/verify-device.sh
# 七组检查：内核/串口/eMMC/网口/USB/音频/模块，末尾给 PASS/FAIL/SKIP 汇总。
# 全通过退出码 0，任一关键项失败退出码 1。
# ============================================================
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0; SKIP=0

pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; SKIP=$((SKIP+1)); }

echo "============================================================"
echo "GK6323V100C 主线内核自检"
echo "时间：$(date)"
echo "主机：$(hostname)"
echo "============================================================"
echo

# 1. 内核版本
echo "[1/7] 内核版本"
KVER="$(uname -r)"
echo "    版本：$KVER"
echo "    架构：$(uname -m)"
if echo "$KVER" | grep -qE '^[0-9]+\.[0-9]+'; then
    pass "内核启动成功（$KVER）"
else
    fail "无法识别内核版本"
fi

# 2. 串口控制台
echo
echo "[2/7] 串口控制台"
CMDLINE="$(cat /proc/cmdline 2>/dev/null || echo '')"
if echo "$CMDLINE" | grep -q 'ttyAMA'; then
    pass "内核命令行包含串口控制台"
    echo "    cmdline: $CMDLINE"
elif [ -c /dev/ttyAMA0 ] || [ -c /dev/console ]; then
    pass "控制台设备节点存在"
else
    fail "未检测到串口控制台"
fi

# 3. eMMC
echo
echo "[3/7] eMMC 存储"
if [ -b /dev/mmcblk0 ]; then
    SIZE=$(cat /sys/block/mmcblk0/size 2>/dev/null)
    SIZE_MB=$((SIZE*512/1024/1024))
    pass "eMMC 检测到（/dev/mmcblk0，约 ${SIZE_MB}MB）"
    echo "    分区数：$(ls /dev/mmcblk0p* 2>/dev/null | wc -l)"
else
    fail "未检测到 eMMC（/dev/mmcblk0 不存在）"
fi

# 4. 网口
echo
echo "[4/7] 以太网"
if ls /sys/class/net/eth* 1>/dev/null 2>&1; then
    IF=$(ls /sys/class/net/eth* 2>/dev/null | head -1 | xargs -I{} basename {})
    IP=$(ip -4 addr show "$IF" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    LINK=$(cat /sys/class/net/"$IF"/carrier 2>/dev/null || echo 0)
    if [ "$LINK" = "1" ]; then
        pass "网口 $IF 已连接（IP: ${IP:-未分配}）"
    else
        pass "网口 $IF 存在但未插线"
    fi
else
    fail "未检测到以太网接口"
fi

# 5. USB 主控制器
echo
echo "[5/7] USB 主控"
USB_LS=$(lsusb 2>/dev/null || echo '')
if ls /sys/bus/usb/devices/usb* 1>/dev/null 2>&1; then
    USB_CNT=$(ls /sys/bus/usb/devices/usb* 2>/dev/null | wc -l)
    pass "USB 主控存在（${USB_CNT} 个）"
    if [ -n "$USB_LS" ]; then
        echo "    $USB_LS" | sed 's/^/    /'
    fi
else
    fail "未检测到 USB 主控"
fi

# 6. 内核模块支持
echo
echo "[6/7] 模块支持"
if [ -d "/lib/modules/$KVER" ]; then
    MOD_CNT=$(find "/lib/modules/$KVER" -name '*.ko*' -type f 2>/dev/null | wc -l)
    pass "模块目录存在（约 ${MOD_CNT} 个模块）"
else
    fail "/lib/modules/$KVER 不存在（模块未安装）"
fi

# 7. USB 音频模块
echo
echo "[7/7] USB 音频"
if lsmod 2>/dev/null | grep -q snd_usb_audio; then
    CARD=$(cat /proc/asound/cards 2>/dev/null | grep -i usb | head -1)
    pass "snd-usb-audio 已加载"
    [ -n "$CARD" ] && echo "    $CARD" | sed 's/^/    /'
elif [ -f "/lib/modules/$KVER/kernel/sound/usb/snd-usb-audio.ko" ] || \
     [ -f "/lib/modules/$KVER/kernel/sound/usb/snd-usb-audio.ko.xz"] || \
     [ -f "/lib/modules/$KVER/kernel/sound/usb/snd-usb-audio.ko.gz" ]; then
    skip "snd-usb-audio 模块已安装但未加载（插卡后 modprobe snd-usb-audio）"
else
    fail "snd-usb-audio.ko 未找到（检查 modules.tar.gz 是否正确解压）"
fi

echo
echo "============================================================"
echo "汇总：$PASS 通过 / $FAIL 失败 / $SKIP 跳过"
echo "============================================================"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
